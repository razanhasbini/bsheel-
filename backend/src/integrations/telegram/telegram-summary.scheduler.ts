import { InjectQueue } from '@nestjs/bullmq';
import { Injectable, type OnApplicationBootstrap } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import type { Queue } from 'bullmq';
import type { Environment } from '../../config/environment.js';

@Injectable()
export class TelegramSummaryScheduler implements OnApplicationBootstrap {
  constructor(
    private readonly config: ConfigService<Environment, true>,
    @InjectQueue('domain-events') private readonly queue: Queue<Record<string, unknown>, unknown, string>,
  ) {}

  async onApplicationBootstrap(): Promise<void> {
    if (!this.config.get('TELEGRAM_ENABLED', { infer: true })) return;
    await this.queue.upsertJobScheduler(
      'telegram-daily-summary',
      { pattern: '0 6 * * *', tz: 'UTC' },
      {
        name: 'telegram.daily_summary',
        data: {},
        opts: {
          attempts: 5,
          backoff: { type: 'exponential', delay: 2_000 },
          removeOnComplete: 1_000,
          removeOnFail: 5_000,
        },
      },
    );
  }
}
