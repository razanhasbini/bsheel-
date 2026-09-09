import { InjectQueue } from '@nestjs/bullmq';
import { Injectable, type OnApplicationBootstrap } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import type { Queue } from 'bullmq';
import type { Environment } from '../../../config/environment.js';

@Injectable()
export class StreakReminderScheduler implements OnApplicationBootstrap {
  constructor(
    private readonly config: ConfigService<Environment, true>,
    @InjectQueue('streak-reminders') private readonly queue: Queue,
  ) {}

  async onApplicationBootstrap(): Promise<void> {
    if (!this.config.get('STREAK_REMINDER_ENABLED', { infer: true })) {
      await this.queue.removeJobScheduler('streak-reminder-sweep');
      return;
    }
    await this.queue.upsertJobScheduler(
      'streak-reminder-sweep',
      { every: this.config.get('STREAK_REMINDER_INTERVAL_MS', { infer: true }) },
      {
        name: 'streak.remind',
        data: {},
        opts: {
          attempts: 3,
          backoff: { type: 'exponential', delay: 5_000 },
          removeOnComplete: 100,
          removeOnFail: 1_000,
        },
      },
    );
  }
}
