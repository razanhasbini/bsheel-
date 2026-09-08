import { InjectQueue } from '@nestjs/bullmq';
import { Injectable, type OnApplicationBootstrap } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import type { Queue } from 'bullmq';
import type { Environment } from '../../../config/environment.js';

@Injectable()
export class MediaReclaimScheduler implements OnApplicationBootstrap {
  constructor(
    private readonly config: ConfigService<Environment, true>,
    @InjectQueue('media-reclaim') private readonly queue: Queue,
  ) {}

  async onApplicationBootstrap(): Promise<void> {
    if (!this.config.get('MEDIA_RECLAIM_ENABLED', { infer: true })) return;
    await this.queue.upsertJobScheduler(
      'media-reclaim-hourly',
      { every: this.config.get('MEDIA_RECLAIM_INTERVAL_MS', { infer: true }) },
      {
        name: 'media.reclaim',
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
