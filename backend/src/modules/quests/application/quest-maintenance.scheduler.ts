import { InjectQueue } from '@nestjs/bullmq';
import { Injectable, type OnApplicationBootstrap } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import type { Queue } from 'bullmq';
import type { Environment } from '../../../config/environment.js';

@Injectable()
export class QuestMaintenanceScheduler implements OnApplicationBootstrap {
  constructor(
    private readonly config: ConfigService<Environment, true>,
    @InjectQueue('quest-maintenance') private readonly queue: Queue,
  ) {}

  async onApplicationBootstrap(): Promise<void> {
    if (!this.config.get('QUEST_MAINTENANCE_ENABLED', { infer: true })) {
      await Promise.all([
        this.queue.removeJobScheduler('quest-expiration-and-warning-sweep'),
        this.queue.removeJobScheduler('pending-review-reminder-sweep'),
      ]);
      return;
    }
    const options = {
      attempts: 3,
      backoff: { type: 'exponential' as const, delay: 5_000 },
      removeOnComplete: 100,
      removeOnFail: 1_000,
    };
    await Promise.all([
      this.queue.upsertJobScheduler(
        'quest-expiration-and-warning-sweep',
        {
          every: this.config.get('QUEST_MAINTENANCE_INTERVAL_MS', {
            infer: true,
          }),
        },
        { name: 'quest.expire-and-warn', data: {}, opts: options },
      ),
      this.queue.upsertJobScheduler(
        'pending-review-reminder-sweep',
        {
          every: this.config.get('PENDING_REVIEW_REMINDER_INTERVAL_MS', {
            infer: true,
          }),
        },
        { name: 'quest.pending-review-reminders', data: {}, opts: options },
      ),
    ]);
  }
}
