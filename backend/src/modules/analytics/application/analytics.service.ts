import { Injectable, Logger, NotFoundException } from '@nestjs/common';
import { clampOccurredAt, type PostAttribution } from '../domain/analytics-events.js';
import { AnalyticsEventsRepository } from '../infrastructure/analytics-events.repository.js';
import type { AnalyticsBatchDto } from '../presentation/analytics.dto.js';

@Injectable()
export class AnalyticsService {
  private readonly logger = new Logger(AnalyticsService.name);

  constructor(private readonly events: AnalyticsEventsRepository) {}

  /// Records a client's batch of exposure events.
  ///
  /// Returns how many were newly recorded, which is deliberately allowed to
  /// be fewer than were sent: duplicates from a retried flush and events
  /// whose quest has since been deleted are both dropped silently and
  /// neither is an error the client can act on. Reporting the count rather
  /// than a bare 204 gives a client something to log when it suspects it is
  /// double-flushing.
  async record(userId: string, batch: AnalyticsBatchDto): Promise<{ recorded: number }> {
    const receivedAt = new Date();
    const recorded = await this.events.append(
      userId,
      batch.events.map((event) => ({
        clientEventId: event.clientEventId,
        eventType: event.eventType,
        questId: event.questId,
        surface: event.surface,
        // The client's own timestamp, brought into a window we are willing
        // to chart. Both values are stored so the clamp is visible.
        occurredAt: clampOccurredAt(new Date(event.occurredAt), receivedAt),
        sourceSubmissionId: event.sourceSubmissionId ?? null,
      })),
    );
    if (recorded < batch.events.length) {
      this.logger.debug(
        { userId, sent: batch.events.length, recorded },
        'Some analytics events were duplicates or referenced a deleted quest',
      );
    }
    return { recorded };
  }

  /// What one post led to (0049), for its author or a moderator.
  ///
  /// 404 for anyone else — the same shape as every other "not yours" in this
  /// API: a 403 would confirm the post exists and that someone else owns
  /// the numbers about it. Counts only; never who.
  async attribution(viewerId: string, isModerator: boolean, submissionId: string): Promise<PostAttribution> {
    const author = await this.events.postAuthor(submissionId);
    if (!author || (author !== viewerId && !isModerator)) {
      throw new NotFoundException({ code: 'NOT_FOUND', message: 'Post not found' });
    }
    const attribution = await this.events.attributionFor(submissionId);
    if (!attribution) throw new NotFoundException({ code: 'NOT_FOUND', message: 'Post not found' });
    return attribution;
  }
}
