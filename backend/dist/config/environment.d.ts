import { z } from 'zod';
declare const environmentSchema: z.ZodObject<{
    NODE_ENV: z.ZodDefault<z.ZodEnum<{
        development: "development";
        test: "test";
        staging: "staging";
        production: "production";
    }>>;
    PORT: z.ZodDefault<z.ZodCoercedNumber<unknown>>;
    APP_NAME: z.ZodDefault<z.ZodString>;
    APP_VERSION: z.ZodDefault<z.ZodString>;
    API_PREFIX: z.ZodDefault<z.ZodString>;
    CORS_ORIGINS: z.ZodDefault<z.ZodString>;
    DATABASE_URL: z.ZodDefault<z.ZodString>;
    DATABASE_POOL_MIN: z.ZodDefault<z.ZodCoercedNumber<unknown>>;
    DATABASE_POOL_MAX: z.ZodDefault<z.ZodCoercedNumber<unknown>>;
    DATABASE_IDLE_TIMEOUT_MS: z.ZodDefault<z.ZodCoercedNumber<unknown>>;
    DATABASE_STATEMENT_TIMEOUT_MS: z.ZodDefault<z.ZodCoercedNumber<unknown>>;
    REDIS_URL: z.ZodDefault<z.ZodString>;
    REDIS_KEY_PREFIX: z.ZodDefault<z.ZodString>;
    OUTBOX_POLL_MS: z.ZodDefault<z.ZodCoercedNumber<unknown>>;
    OUTBOX_BATCH_SIZE: z.ZodDefault<z.ZodCoercedNumber<unknown>>;
    JWT_ACCESS_SECRET: z.ZodDefault<z.ZodString>;
    JWT_ACCESS_TTL_SECONDS: z.ZodDefault<z.ZodCoercedNumber<unknown>>;
    JWT_REFRESH_SECRET: z.ZodDefault<z.ZodString>;
    JWT_REFRESH_TTL_SECONDS: z.ZodDefault<z.ZodCoercedNumber<unknown>>;
    DEVICE_TOKEN_ENCRYPTION_KEY: z.ZodDefault<z.ZodString>;
    PUSH_NOTIFICATIONS_ENABLED: z.ZodPipe<z.ZodDefault<z.ZodEnum<{
        true: "true";
        false: "false";
    }>>, z.ZodTransform<boolean, "true" | "false">>;
    FIREBASE_SERVICE_ACCOUNT: z.ZodPreprocess<z.ZodOptional<z.ZodString>, unknown>;
    FIREBASE_PROJECT_ID: z.ZodDefault<z.ZodString>;
    FIREBASE_TIMEOUT_MS: z.ZodDefault<z.ZodCoercedNumber<unknown>>;
    OAUTH_GOOGLE_CLIENT_IDS: z.ZodDefault<z.ZodString>;
    OAUTH_APPLE_CLIENT_IDS: z.ZodDefault<z.ZodString>;
    OAUTH_TIMEOUT_MS: z.ZodDefault<z.ZodCoercedNumber<unknown>>;
    AUTH_ACTION_TOKEN_ENCRYPTION_KEY: z.ZodDefault<z.ZodString>;
    AUTH_EMAIL_CONFIRMATION_REQUIRED: z.ZodPipe<z.ZodDefault<z.ZodEnum<{
        true: "true";
        false: "false";
    }>>, z.ZodTransform<boolean, "true" | "false">>;
    APP_PUBLIC_URL: z.ZodDefault<z.ZodString>;
    EMAIL_DELIVERY_WEBHOOK_URL: z.ZodPreprocess<z.ZodOptional<z.ZodString>, unknown>;
    EMAIL_DELIVERY_WEBHOOK_SECRET: z.ZodPreprocess<z.ZodOptional<z.ZodString>, unknown>;
    EMAIL_TIMEOUT_MS: z.ZodDefault<z.ZodCoercedNumber<unknown>>;
    TELEGRAM_ENABLED: z.ZodPipe<z.ZodDefault<z.ZodEnum<{
        true: "true";
        false: "false";
    }>>, z.ZodTransform<boolean, "true" | "false">>;
    TELEGRAM_BOT_TOKEN: z.ZodPreprocess<z.ZodOptional<z.ZodString>, unknown>;
    TELEGRAM_ADMIN_CHAT_ID: z.ZodPreprocess<z.ZodOptional<z.ZodString>, unknown>;
    TELEGRAM_WEBHOOK_SECRET: z.ZodPreprocess<z.ZodOptional<z.ZodString>, unknown>;
    TELEGRAM_ALLOWED_CHAT_IDS: z.ZodDefault<z.ZodString>;
    TELEGRAM_TIMEOUT_MS: z.ZodDefault<z.ZodCoercedNumber<unknown>>;
    TELEGRAM_API_BASE_URL: z.ZodDefault<z.ZodString>;
    R2_ENDPOINT: z.ZodPreprocess<z.ZodOptional<z.ZodString>, unknown>;
    R2_REGION: z.ZodDefault<z.ZodString>;
    S3_FORCE_PATH_STYLE: z.ZodPipe<z.ZodDefault<z.ZodEnum<{
        true: "true";
        false: "false";
    }>>, z.ZodTransform<boolean, "true" | "false">>;
    R2_ACCESS_KEY_ID: z.ZodPreprocess<z.ZodOptional<z.ZodString>, unknown>;
    R2_SECRET_ACCESS_KEY: z.ZodPreprocess<z.ZodOptional<z.ZodString>, unknown>;
    R2_BUCKET: z.ZodPreprocess<z.ZodOptional<z.ZodString>, unknown>;
    R2_PUBLIC_BASE_URL: z.ZodPreprocess<z.ZodOptional<z.ZodString>, unknown>;
    SIGNED_URL_TTL_SECONDS: z.ZodDefault<z.ZodCoercedNumber<unknown>>;
    MEDIA_MAX_SUBMISSION_OBJECTS_PER_USER: z.ZodDefault<z.ZodCoercedNumber<unknown>>;
    MEDIA_MAX_AVATAR_OBJECTS_PER_USER: z.ZodDefault<z.ZodCoercedNumber<unknown>>;
    MEDIA_MAX_AVATAR_BYTES: z.ZodDefault<z.ZodCoercedNumber<unknown>>;
    MEDIA_MAX_SUBMISSION_BYTES: z.ZodDefault<z.ZodCoercedNumber<unknown>>;
    MEDIA_RECLAIM_ENABLED: z.ZodPipe<z.ZodDefault<z.ZodEnum<{
        true: "true";
        false: "false";
    }>>, z.ZodTransform<boolean, "true" | "false">>;
    MEDIA_RECLAIM_INTERVAL_MS: z.ZodDefault<z.ZodCoercedNumber<unknown>>;
    MEDIA_RECLAIM_GRACE_HOURS: z.ZodDefault<z.ZodCoercedNumber<unknown>>;
    MEDIA_RECLAIM_BATCH_SIZE: z.ZodDefault<z.ZodCoercedNumber<unknown>>;
    LOG_LEVEL: z.ZodDefault<z.ZodEnum<{
        error: "error";
        fatal: "fatal";
        warn: "warn";
        info: "info";
        debug: "debug";
        trace: "trace";
        silent: "silent";
    }>>;
    SWAGGER_ENABLED: z.ZodPipe<z.ZodDefault<z.ZodEnum<{
        true: "true";
        false: "false";
    }>>, z.ZodTransform<boolean, "true" | "false">>;
    THROTTLE_TTL_MS: z.ZodDefault<z.ZodCoercedNumber<unknown>>;
    THROTTLE_LIMIT: z.ZodDefault<z.ZodCoercedNumber<unknown>>;
}, z.core.$strip>;
export type Environment = z.infer<typeof environmentSchema>;
export declare function validateEnvironment(configuration: Record<string, unknown>): Environment;
export {};
