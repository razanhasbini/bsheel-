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
import { BrandedExportProcessor } from './modules/media/infrastructure/branded-export.processor.js';
import { MediaReclaimScheduler } from './modules/media/application/media-reclaim.scheduler.js';
import { StreakReminderProcessor } from './modules/profiles/application/streak-reminder.processor.js';
import { StreakReminderScheduler } from './modules/profiles/application/streak-reminder.scheduler.js';
import { ProfilesModule } from './modules/profiles/profiles.module.js';
import { QuestsModule } from './modules/quests/quests.module.js';
import { DiscoveryModule } from './modules/discovery/discovery.module.js';
import { QuestMaintenanceProcessor } from './modules/quests/application/quest-maintenance.processor.js';
import { QuestMaintenanceScheduler } from './modules/quests/application/quest-maintenance.scheduler.js';
import { AgentModule } from './modules/agent/agent.module.js';
import { AgentRecoveryScheduler } from './modules/agent/infrastructure/agent-recovery.scheduler.js';
import { SubmissionVerificationProcessor } from './modules/agent/infrastructure/submission-verification.processor.js';
import { QuestAssignmentAgentProcessor } from './modules/agent/infrastructure/quest-assignment-agent.processor.js';
import { SubmissionsModule } from './modules/submissions/submissions.module.js';
import { ProofVerificationProcessor } from './modules/submissions/application/proof-verification.processor.js';
import { ProofVerificationScheduler } from './modules/submissions/application/proof-verification.scheduler.js';

@Module({
  imports: [
    ConfigModule.forRoot({ isGlobal: true, cache: true, validate: (configuration) => validateEnvironment({ ...configuration, PROCESS_ROLE: 'worker' }) }),
    LoggerModule.forRoot(),
    DatabaseModule,
    MessagingModule,
    MediaModule,
    ProfilesModule,
    QuestsModule,
    // Hidden-quest unlocks are evaluated off submission.approved, in the
    // worker, so a discovery lands while the player is still standing where
    // they earned it.
    DiscoveryModule,
    RedisModule,
    TelegramModule,
    AgentModule,
    // AI proof verification (#47): the submission.created consumer and the
    // catch-up sweep both run here, never in an API replica.
    SubmissionsModule,
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
    // Branded video renders (0050): ffmpeg lives here, never in the API.
    BrandedExportProcessor,
    StreakReminderProcessor,
    StreakReminderScheduler,
    QuestMaintenanceProcessor,
    QuestMaintenanceScheduler,
    SubmissionVerificationProcessor,
    AgentRecoveryScheduler,
    QuestAssignmentAgentProcessor,
    ProofVerificationProcessor,
    ProofVerificationScheduler,
  ],
})
export class WorkerModule {}
