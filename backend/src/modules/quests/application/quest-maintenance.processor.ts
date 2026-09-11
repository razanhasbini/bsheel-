import { Processor, WorkerHost } from '@nestjs/bullmq';
import { Injectable, Logger } from '@nestjs/common';
import type { Job } from 'bullmq';
import { QuestMaintenanceService } from './quest-maintenance.service.js';

@Injectable()
@Processor('quest-maintenance', { concurrency: 1 })
export class QuestMaintenanceProcessor extends WorkerHost {
  private readonly logger = new Logger(QuestMaintenanceProcessor.name);

  constructor(private readonly maintenance: QuestMaintenanceService) {
    super();
  }

  async process(job: Job): Promise<void> {
    if (job.name === 'quest.expire-and-warn') {
      const outcome = await this.maintenance.expireAndWarn();
      // Journeys are swept on the same tick as quest expiry, and for the
      // same reason: both are about a player's board going stale while they
      // are not looking at it. Kept a separate transaction so a failure in
      // one does not roll back the other's notifications.
      const journeysAbandoned = await this.maintenance.abandonUnansweredJourneys();
      this.logger.debug(
        { jobId: job.id, ...outcome, journeysAbandoned },
        'Quest maintenance sweep finished',
      );
      return;
    }
    if (job.name === 'quest.pending-review-reminders') {
      const outcome = await this.maintenance.remindPendingReviews();
      this.logger.debug(
        { jobId: job.id, ...outcome },
        'Pending review reminder sweep finished',
      );
      return;
    }
    throw new Error(`Unknown quest maintenance job: ${job.name}`);
  }
}
