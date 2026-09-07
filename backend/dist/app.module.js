var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
import { Module } from '@nestjs/common';
import { ConfigModule, ConfigService } from '@nestjs/config';
import { APP_FILTER, APP_GUARD, APP_INTERCEPTOR } from '@nestjs/core';
import { ThrottlerGuard, ThrottlerModule } from '@nestjs/throttler';
import { LoggerModule } from 'nestjs-pino';
import { ApiExceptionFilter } from './common/http/api-exception.filter.js';
import { ApiResponseInterceptor } from './common/http/api-response.interceptor.js';
import { AccessTokenGuard } from './common/auth/access-token.guard.js';
import { RolesGuard } from './common/auth/roles.guard.js';
import { validateEnvironment } from './config/environment.js';
import { DatabaseModule } from './infrastructure/database/database.module.js';
import { RedisModule } from './infrastructure/redis/redis.module.js';
import { MessagingModule } from './infrastructure/messaging/messaging.module.js';
import { HealthModule } from './modules/health/health.module.js';
import { AuthModule } from './modules/auth/auth.module.js';
import { QuestsModule } from './modules/quests/quests.module.js';
import { ProfilesModule } from './modules/profiles/profiles.module.js';
import { SubmissionsModule } from './modules/submissions/submissions.module.js';
import { FeedModule } from './modules/feed/feed.module.js';
import { SocialModule } from './modules/social/social.module.js';
import { SearchModule } from './modules/search/search.module.js';
import { LeaderboardModule } from './modules/leaderboard/leaderboard.module.js';
import { NotificationsModule } from './modules/notifications/notifications.module.js';
import { MediaModule } from './modules/media/media.module.js';
import { CollabModule } from './modules/collab/collab.module.js';
import { AdminModule } from './modules/admin/admin.module.js';
import { PublicIntakeModule } from './modules/public-intake/public-intake.module.js';
import { AccountModule } from './modules/account/account.module.js';
import { RealtimeModule } from './infrastructure/realtime/realtime.module.js';
import { TelegramModule } from './integrations/telegram/telegram.module.js';
let AppModule = class AppModule {
};
AppModule = __decorate([
    Module({
        imports: [
            ConfigModule.forRoot({
                isGlobal: true,
                cache: true,
                validate: validateEnvironment,
            }),
            LoggerModule.forRootAsync({
                inject: [ConfigService],
                useFactory: (config) => ({
                    forRoutes: ['{*path}'],
                    pinoHttp: {
                        level: config.get('LOG_LEVEL', { infer: true }),
                        genReqId: (request, response) => {
                            const supplied = request.headers['x-request-id'];
                            const id = typeof supplied === 'string' ? supplied : crypto.randomUUID();
                            response.setHeader('x-request-id', id);
                            return id;
                        },
                        redact: {
                            paths: [
                                'req.headers.authorization',
                                'req.headers.cookie',
                                'res.headers["set-cookie"]',
                                '*.password',
                                '*.token',
                                '*.secret',
                            ],
                            censor: '[REDACTED]',
                        },
                        ...(config.get('NODE_ENV', { infer: true }) === 'development'
                            ? { transport: { target: 'pino-pretty', options: { singleLine: true } } }
                            : {}),
                    },
                }),
            }),
            ThrottlerModule.forRootAsync({
                inject: [ConfigService],
                useFactory: (config) => ({
                    throttlers: [
                        {
                            ttl: config.get('THROTTLE_TTL_MS', { infer: true }),
                            limit: config.get('THROTTLE_LIMIT', { infer: true }),
                        },
                    ],
                }),
            }),
            DatabaseModule,
            RedisModule,
            MessagingModule,
            AuthModule,
            QuestsModule,
            ProfilesModule,
            SubmissionsModule,
            FeedModule,
            SocialModule,
            SearchModule,
            LeaderboardModule,
            NotificationsModule,
            MediaModule,
            CollabModule,
            AdminModule,
            PublicIntakeModule,
            AccountModule,
            RealtimeModule,
            TelegramModule,
            HealthModule,
        ],
        providers: [
            { provide: APP_GUARD, useClass: ThrottlerGuard },
            { provide: APP_GUARD, useClass: AccessTokenGuard },
            { provide: APP_GUARD, useClass: RolesGuard },
            { provide: APP_FILTER, useClass: ApiExceptionFilter },
            { provide: APP_INTERCEPTOR, useClass: ApiResponseInterceptor },
        ],
    })
], AppModule);
export { AppModule };
//# sourceMappingURL=app.module.js.map