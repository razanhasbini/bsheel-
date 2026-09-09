import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { LoggerModule } from 'nestjs-pino';
import { validateEnvironment } from './config/environment.js';
import { DatabaseModule } from './infrastructure/database/database.module.js';
import { DomainEventsProcessor } from './infrastructure/messaging/domain-events.processor.js';
import { DomainEventsRepository } from './infrastructure/messaging/domain-events.repository.js';
import { MessagingModule } from './infrastructure/messaging/messaging.module.js';
import { DeviceTokenCipher } from './modules/notifications/infrastructure/device-token-cipher.js';
import { FirebasePushService } from './modules/notifications/infrastructure/firebase-push.service.js';
import { MediaModule } from './modules/media/media.module.js';
import { AuthActionTokenCipher } from './modules/auth/infrastructure/auth-action-token-cipher.js';
import { TransactionalEmailService } from './modules/auth/infrastructure/transactional-email.service.js';
import { RedisModule } from './infrastructure/redis/redis.module.js';
import { RealtimeEventPublisher } from './infrastructure/realtime/realtime-event.publisher.js';
import { TelegramModule } from './integrations/telegram/telegram.module.js';
import { MediaReclaimProcessor } from './modules/media/application/media-reclaim.processor.js';
import { MediaReclaimScheduler } from './modules/media/application/media-reclaim.scheduler.js';
import { StreakReminderProcessor } from './modules/profiles/application/streak-reminder.processor.js';
import { StreakReminderScheduler } from './modules/profiles/application/streak-reminder.scheduler.js';
import { ProfilesModule } from './modules/profiles/profiles.module.js';

@Module({
  imports: [
    ConfigModule.forRoot({ isGlobal: true, cache: true, validate: (configuration) => validateEnvironment({ ...configuration, PROCESS_ROLE: 'worker' }) }),
    LoggerModule.forRoot(),
    DatabaseModule,
    MessagingModule,
    MediaModule,
    ProfilesModule,
    RedisModule,
    TelegramModule,
  ],
  providers: [
    DomainEventsProcessor,
    DomainEventsRepository,
    DeviceTokenCipher,
    FirebasePushService,
    AuthActionTokenCipher,
    TransactionalEmailService,
    RealtimeEventPublisher,
    MediaReclaimProcessor,
    MediaReclaimScheduler,
    StreakReminderProcessor,
    StreakReminderScheduler,
  ],
})
export class WorkerModule {}
