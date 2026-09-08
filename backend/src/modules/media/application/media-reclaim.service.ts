import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import type { Environment } from '../../../config/environment.js';
import { MediaRepository, type ReclaimCandidate } from '../infrastructure/media.repository.js';
import { ObjectStorageService } from '../infrastructure/object-storage.service.js';

export interface ReclaimOutcome {
  readonly claimed: number;
  readonly deleted: number;
  readonly failed: number;
  readonly byReason: Readonly<Record<string, number>>;
}

/// Deletes object-storage bytes that nothing references any more.
///
/// The Cloudflare worker this replaces swept by LISTing the whole bucket and
/// diffing it against the database: O(objects) network round-trips, no way to
/// batch, and it had to be deployed and torn down by hand. Because
/// `media_objects` tracks every object's lifecycle, the same question is an
/// indexed query — see `MediaRepository.claimReclaimable`.
///
/// The repository commits a permanent lifecycle tombstone before returning a
/// candidate. External deletes may safely retry, but the file cannot be bound
/// to a profile/submission or completed after that point.
@Injectable()
export class MediaReclaimService {
  private readonly logger = new Logger(MediaReclaimService.name);

  constructor(
    private readonly repository: MediaRepository,
    private readonly storage: ObjectStorageService,
    private readonly config: ConfigService<Environment, true>,
  ) {}

  async sweep(): Promise<ReclaimOutcome> {
    const empty: ReclaimOutcome = { claimed: 0, deleted: 0, failed: 0, byReason: {} };
    if (!this.config.get('MEDIA_RECLAIM_ENABLED', { infer: true })) return empty;

    const graceHours = this.config.get('MEDIA_RECLAIM_GRACE_HOURS', { infer: true });
    const batchSize = this.config.get('MEDIA_RECLAIM_BATCH_SIZE', { infer: true });

    const candidates = await this.repository.claimReclaimable(graceHours, batchSize);
    if (candidates.length === 0) return empty;

    const byReason: Record<string, number> = {};
    const reclaimed: ReclaimCandidate[] = [];
    let failed = 0;

    for (const candidate of candidates) {
      try {
        // The tombstone remains even on failure, so a retry cannot delete a
        // file which another request has since rebound.
        await this.storage.delete(candidate.object_key);
        reclaimed.push(candidate);
        byReason[candidate.reason] = (byReason[candidate.reason] ?? 0) + 1;
      } catch (error) {
        failed += 1;
        await this.repository.releaseReclaim(candidate);
        this.logger.warn(
          { objectKey: candidate.object_key, reason: candidate.reason, error },
          'Could not delete a reclaimable object; leaving it for the next pass',
        );
      }
    }

    const deleted = await this.repository.markReclaimed(reclaimed);

    // Worth a log line at info: a sweep that keeps finding the full batch
    // every hour means the backlog is growing faster than the batch size.
    if (deleted > 0 || failed > 0) {
      this.logger.log(
        { claimed: candidates.length, deleted, failed, byReason, batchSize },
        'Reclaimed unreferenced media objects',
      );
    }

    return { claimed: candidates.length, deleted, failed, byReason };
  }
}
