import { Module } from '@nestjs/common';
import { ConfigModule, ConfigService } from '@nestjs/config';
import { APP_FILTER, APP_GUARD, APP_INTERCEPTOR } from '@nestjs/core';
import { ThrottlerGuard, ThrottlerModule } from '@nestjs/throttler';
import { LoggerModule } from 'nestjs-pino';
import { ApiExceptionFilter } from './common/http/api-exception.filter.js';
import { ApiResponseInterceptor } from './common/http/api-response.interceptor.js';
import { AccessTokenGuard } from './common/auth/access-token.guard.js';
import { RolesGuard } from './common/auth/roles.guard.js';
import { MaintenanceGuard } from './common/maintenance/maintenance.guard.js';
import { type Environment, validateEnvironment } from './config/environment.js';
import { DatabaseModule } from './infrastructure/database/database.module.js';
import { RedisModule } from './infrastructure/redis/redis.module.js';
import { MessagingQueueModule } from './infrastructure/messaging/messaging-queue.module.js';
import { HealthModule } from './modules/health/health.module.js';
import { MapModule } from './modules/map/map.module.js';
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
import { GeofencingModule } from './modules/agent/geofencing.module.js';
import { createRequire } from 'node:module';

/**
 * True only when `pino-pretty` can actually be loaded from this install.
 *
 * It ships as a devDependency, so a production image built with
 * `npm ci --omit=dev` does not have it even when NODE_ENV says development.
 */
function prettyLoggingAvailable(): boolean {
  try {
    createRequire(import.meta.url).resolve('pino-pretty');
    return true;
  } catch {
    return false;
  }
}

@Module({
  imports: [
    ConfigModule.forRoot({
      isGlobal: true,
      cache: true,
      validate: validateEnvironment,
    }),
    LoggerModule.forRootAsync({
      inject: [ConfigService],
      useFactory: (config: ConfigService<Environment, true>) => ({
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
          // Pretty logs are a convenience for a developer reading a
          // terminal, so they must never be the reason a process refuses to
          // boot. NODE_ENV alone is not enough to decide: the container
          // image is built with `npm ci --omit=dev` while compose passes it
          // NODE_ENV=development from backend/.env, and pino-pretty is a
          // devDependency — that combination crashed the API on startup
          // with "unable to determine transport target". Ask whether the
          // module is actually there instead of inferring it.
          ...(config.get('NODE_ENV', { infer: true }) === 'development' && prettyLoggingAvailable()
            ? { transport: { target: 'pino-pretty', options: { singleLine: true } } }
            : {}),
        },
      }),
    }),
    ThrottlerModule.forRootAsync({
      inject: [ConfigService],
      useFactory: (config: ConfigService<Environment, true>) => ({
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
    MessagingQueueModule,
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
    MapModule,
    // Only the CAMARA geofence callback endpoint — the rest of the agent
    // stack lives in the worker.
    GeofencingModule,
  ],
  providers: [
    { provide: APP_GUARD, useClass: ThrottlerGuard },
    { provide: APP_GUARD, useClass: AccessTokenGuard },
    { provide: APP_GUARD, useClass: RolesGuard },
    // Last, and the order matters: the maintenance gate exempts admins so an
    // operator cannot lock themselves out, and it can only see the caller's
    // role because AccessTokenGuard has already run.
    { provide: APP_GUARD, useClass: MaintenanceGuard },
    { provide: APP_FILTER, useClass: ApiExceptionFilter },
    { provide: APP_INTERCEPTOR, useClass: ApiResponseInterceptor },
  ],
})
export class AppModule {}
