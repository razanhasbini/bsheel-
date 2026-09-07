var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { LoggerModule } from 'nestjs-pino';
import { validateEnvironment } from './config/environment.js';
import { DatabaseModule } from './infrastructure/database/database.module.js';
import { DomainEventsProcessor } from './infrastructure/messaging/domain-events.processor.js';
import { DomainEventsRepository } from './infrastructure/messaging/domain-events.repository.js';
import { MessagingQueueModule } from './infrastructure/messaging/messaging-queue.module.js';
import { DeviceTokenCipher } from './modules/notifications/infrastructure/device-token-cipher.js';
import { FirebasePushService } from './modules/notifications/infrastructure/firebase-push.service.js';
import { MediaModule } from './modules/media/media.module.js';
import { AuthActionTokenCipher } from './modules/auth/infrastructure/auth-action-token-cipher.js';
import { TransactionalEmailService } from './modules/auth/infrastructure/transactional-email.service.js';
import { RedisModule } from './infrastructure/redis/redis.module.js';
import { RealtimeEventPublisher } from './infrastructure/realtime/realtime-event.publisher.js';
import { TelegramModule } from './integrations/telegram/telegram.module.js';
let WorkerModule = class WorkerModule {
};
WorkerModule = __decorate([
    Module({
        imports: [
            ConfigModule.forRoot({ isGlobal: true, cache: true, validate: validateEnvironment }),
            LoggerModule.forRoot(),
            DatabaseModule,
            MessagingQueueModule,
            MediaModule,
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
        ],
    })
], WorkerModule);
export { WorkerModule };
//# sourceMappingURL=worker.module.js.map