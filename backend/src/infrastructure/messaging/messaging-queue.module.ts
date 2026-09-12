import { BullModule } from '@nestjs/bullmq';
import { Global, Module } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import type { Environment } from '../../config/environment.js';

@Global()
@Module({
  imports: [
    BullModule.forRootAsync({
      inject: [ConfigService],
      useFactory: (config: ConfigService<Environment, true>) => ({
        connection: { url: config.get('REDIS_URL', { infer: true }) },
        prefix: `${config.get('REDIS_KEY_PREFIX', { infer: true })}bull`,
      }),
    }),
    BullModule.registerQueue({ name: 'domain-events' }),
    BullModule.registerQueue({ name: 'media-reclaim' }),
    BullModule.registerQueue({ name: 'streak-reminders' }),
    BullModule.registerQueue({ name: 'quest-maintenance' }),
    BullModule.registerQueue({ name: 'submission-verification' }),
    BullModule.registerQueue({ name: 'quest-assignment-agent' }),
    BullModule.registerQueue({ name: 'proof-verification' }),
    // Branded video renders (migration 0050): one ffmpeg job per submission.
    BullModule.registerQueue({ name: 'branded-export' }),
  ],
  exports: [BullModule],
})
export class MessagingQueueModule {}
