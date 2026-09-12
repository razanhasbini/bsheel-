import { InjectQueue } from '@nestjs/bullmq';
import { BadRequestException, Injectable, NotFoundException } from '@nestjs/common';
import type { Queue } from 'bullmq';
import { BrandedExportRepository, type BrandedExportRecord } from '../infrastructure/branded-export.repository.js';
import { ObjectStorageService } from '../infrastructure/object-storage.service.js';

export interface BrandedExportView {
  readonly submissionId: string;
  readonly status: BrandedExportRecord['status'];
  /// Signed, short-lived, present only when `status` is `ready`.
  readonly downloadUrl: string | null;
  readonly error: string | null;
}

/**
 * Branded video exports (migration 0050): the request side.
 *
 * A viewer asks for a post's video with the Bsheel band burned in; the
 * render happens on the worker (`BrandedExportProcessor`) and the result is
 * fetched here as a signed URL. One export per post — a second requester
 * gets the first render — and a failed render may be asked for again.
 */
@Injectable()
export class BrandedExportService {
  constructor(
    private readonly exports: BrandedExportRepository,
    private readonly storage: ObjectStorageService,
    @InjectQueue('branded-export') private readonly queue: Queue,
  ) {}

  async request(viewerId: string, submissionId: string): Promise<BrandedExportView> {
    const source = await this.exports.source(viewerId, submissionId);
    // 404 rather than 403 for a post the viewer may not see, like the rest
    // of the media surface: the export would hand out the bytes.
    if (!source) throw new NotFoundException({ code: 'NOT_FOUND', message: 'Post not found' });
    if (!source.mediaType.toLowerCase().startsWith('video')) {
      throw new BadRequestException({
        code: 'NOT_A_VIDEO',
        message: 'Only video posts are rendered on the server; photos are branded on the device.',
      });
    }

    const { record, created } = await this.exports.ensure(submissionId, viewerId);
    let current = record;
    if (created || record.status === 'failed') {
      if (!created) await this.exports.requeue(submissionId);
      current = { ...record, status: 'queued', error: null };
      await this.queue.add(
        'branded-export.render',
        { exportId: record.id, submissionId },
        {
          // One job per attempt; a failed render's retry gets a new id so
          // BullMQ does not collapse it onto the finished job. ':' is not
          // allowed in a custom id.
          jobId: `branded-export-${record.id}-${Math.floor(Date.now() / 1000)}`,
          attempts: 1,
          removeOnComplete: { age: 86_400, count: 5_000 },
          removeOnFail: { age: 604_800, count: 20_000 },
        },
      );
    }
    return this.view(current);
  }

  async status(viewerId: string, submissionId: string): Promise<BrandedExportView> {
    const source = await this.exports.source(viewerId, submissionId);
    if (!source) throw new NotFoundException({ code: 'NOT_FOUND', message: 'Post not found' });
    const record = await this.exports.find(submissionId);
    if (!record) throw new NotFoundException({ code: 'NOT_FOUND', message: 'No export has been requested for this post' });
    return this.view(record);
  }

  private async view(record: BrandedExportRecord): Promise<BrandedExportView> {
    return {
      submissionId: record.submission_id,
      status: record.status,
      downloadUrl:
        record.status === 'ready' && record.object_key
          ? await this.storage.presignDownload(record.object_key)
          : null,
      error: record.status === 'failed' ? record.error : null,
    };
  }
}
