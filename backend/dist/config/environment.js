import { z } from 'zod';
const booleanFromString = z
    .enum(['true', 'false'])
    .default('true')
    .transform((value) => value === 'true');
const emptyToUndefined = (value) => typeof value === 'string' && value.trim() === '' ? undefined : value;
const optionalString = z.preprocess(emptyToUndefined, z.string().optional());
const optionalUrl = z.preprocess(emptyToUndefined, z.string().url().optional());
const environmentSchema = z
    .object({
    NODE_ENV: z
        .enum(['development', 'test', 'staging', 'production'])
        .default('development'),
    PORT: z.coerce.number().int().positive().max(65_535).default(3000),
    APP_NAME: z.string().min(1).default('bsheel-api'),
    APP_VERSION: z.string().min(1).default('1.0.0'),
    API_PREFIX: z.string().min(1).default('api'),
    CORS_ORIGINS: z.string().default('http://localhost:3000'),
    DATABASE_URL: z
        .string()
        .min(1)
        .default('postgresql://bsheel:bsheel@localhost:5432/bsheel'),
    DATABASE_POOL_MIN: z.coerce.number().int().nonnegative().default(2),
    DATABASE_POOL_MAX: z.coerce.number().int().positive().default(20),
    DATABASE_IDLE_TIMEOUT_MS: z.coerce.number().int().positive().default(30_000),
    DATABASE_STATEMENT_TIMEOUT_MS: z.coerce
        .number()
        .int()
        .positive()
        .default(15_000),
    REDIS_URL: z.string().min(1).default('redis://localhost:6379'),
    REDIS_KEY_PREFIX: z.string().default('bsheel:dev:'),
    OUTBOX_POLL_MS: z.coerce.number().int().min(250).max(60_000).default(1000),
    OUTBOX_BATCH_SIZE: z.coerce.number().int().min(1).max(500).default(50),
    JWT_ACCESS_SECRET: z.string().min(16).default('development-access-secret-change-me'),
    JWT_ACCESS_TTL_SECONDS: z.coerce.number().int().positive().default(900),
    JWT_REFRESH_SECRET: z.string().min(16).default('development-refresh-secret-change-me'),
    JWT_REFRESH_TTL_SECONDS: z.coerce
        .number()
        .int()
        .positive()
        .default(2_592_000),
    DEVICE_TOKEN_ENCRYPTION_KEY: z.string().min(32).default('development-device-token-key-change-me'),
    PUSH_NOTIFICATIONS_ENABLED: z
        .enum(['true', 'false'])
        .default('false')
        .transform((value) => value === 'true'),
    FIREBASE_SERVICE_ACCOUNT: optionalString,
    FIREBASE_PROJECT_ID: z.string().min(1).default('bitsheel'),
    FIREBASE_TIMEOUT_MS: z.coerce.number().int().min(1000).max(60_000).default(10_000),
    OAUTH_GOOGLE_CLIENT_IDS: z.string().default(''),
    OAUTH_APPLE_CLIENT_IDS: z.string().default(''),
    OAUTH_TIMEOUT_MS: z.coerce.number().int().min(1000).max(60_000).default(10_000),
    AUTH_ACTION_TOKEN_ENCRYPTION_KEY: z.string().min(32).default('development-auth-action-key-change-me'),
    AUTH_EMAIL_CONFIRMATION_REQUIRED: z
        .enum(['true', 'false'])
        .default('true')
        .transform((value) => value === 'true'),
    APP_PUBLIC_URL: z.string().url().default('https://admin.bsheel.app'),
    EMAIL_DELIVERY_WEBHOOK_URL: optionalUrl,
    EMAIL_DELIVERY_WEBHOOK_SECRET: optionalString,
    EMAIL_TIMEOUT_MS: z.coerce.number().int().min(1000).max(60_000).default(10_000),
    TELEGRAM_ENABLED: z
        .enum(['true', 'false'])
        .default('false')
        .transform((value) => value === 'true'),
    TELEGRAM_BOT_TOKEN: optionalString,
    TELEGRAM_ADMIN_CHAT_ID: optionalString,
    TELEGRAM_WEBHOOK_SECRET: optionalString,
    TELEGRAM_ALLOWED_CHAT_IDS: z.string().default(''),
    TELEGRAM_TIMEOUT_MS: z.coerce.number().int().min(1000).max(60_000).default(10_000),
    TELEGRAM_API_BASE_URL: z.string().url().default('https://api.telegram.org'),
    R2_ENDPOINT: optionalUrl,
    R2_REGION: z.string().default('auto'),
    S3_FORCE_PATH_STYLE: z
        .enum(['true', 'false'])
        .default('false')
        .transform((value) => value === 'true'),
    R2_ACCESS_KEY_ID: optionalString,
    R2_SECRET_ACCESS_KEY: optionalString,
    R2_BUCKET: optionalString,
    R2_PUBLIC_BASE_URL: optionalUrl,
    SIGNED_URL_TTL_SECONDS: z.coerce.number().int().positive().default(900),
    MEDIA_MAX_SUBMISSION_OBJECTS_PER_USER: z.coerce
        .number()
        .int()
        .positive()
        .default(5000),
    MEDIA_MAX_AVATAR_OBJECTS_PER_USER: z.coerce
        .number()
        .int()
        .positive()
        .default(20),
    MEDIA_MAX_AVATAR_BYTES: z.coerce
        .number()
        .int()
        .positive()
        .default(5 * 1024 * 1024),
    MEDIA_MAX_SUBMISSION_BYTES: z.coerce
        .number()
        .int()
        .positive()
        .default(50 * 1024 * 1024),
    MEDIA_RECLAIM_ENABLED: z
        .enum(['true', 'false'])
        .default('true')
        .transform((value) => value === 'true'),
    MEDIA_RECLAIM_INTERVAL_MS: z.coerce
        .number()
        .int()
        .min(60_000)
        .default(3_600_000),
    MEDIA_RECLAIM_GRACE_HOURS: z.coerce.number().int().min(1).default(24),
    MEDIA_RECLAIM_BATCH_SIZE: z.coerce
        .number()
        .int()
        .min(1)
        .max(1000)
        .default(200),
    LOG_LEVEL: z
        .enum(['fatal', 'error', 'warn', 'info', 'debug', 'trace', 'silent'])
        .default('info'),
    SWAGGER_ENABLED: booleanFromString,
    THROTTLE_TTL_MS: z.coerce.number().int().positive().default(60_000),
    THROTTLE_LIMIT: z.coerce.number().int().positive().default(120),
})
    .superRefine((environment, context) => {
    if (environment.DATABASE_POOL_MIN > environment.DATABASE_POOL_MAX) {
        context.addIssue({
            code: 'custom',
            path: ['DATABASE_POOL_MIN'],
            message: 'DATABASE_POOL_MIN cannot exceed DATABASE_POOL_MAX',
        });
    }
    if (environment.NODE_ENV === 'production') {
        for (const key of ['JWT_ACCESS_SECRET', 'JWT_REFRESH_SECRET', 'DEVICE_TOKEN_ENCRYPTION_KEY', 'AUTH_ACTION_TOKEN_ENCRYPTION_KEY']) {
            if (environment[key].length < 32 || environment[key].includes('change-me')) {
                context.addIssue({
                    code: 'custom',
                    path: [key],
                    message: `${key} must be an independent secret of at least 32 characters`,
                });
            }
        }
    }
    if (environment.PUSH_NOTIFICATIONS_ENABLED && !environment.FIREBASE_SERVICE_ACCOUNT) {
        context.addIssue({
            code: 'custom',
            path: ['FIREBASE_SERVICE_ACCOUNT'],
            message: 'FIREBASE_SERVICE_ACCOUNT is required when push notifications are enabled',
        });
    }
    if (environment.EMAIL_DELIVERY_WEBHOOK_URL && !environment.EMAIL_DELIVERY_WEBHOOK_SECRET) {
        context.addIssue({
            code: 'custom',
            path: ['EMAIL_DELIVERY_WEBHOOK_SECRET'],
            message: 'EMAIL_DELIVERY_WEBHOOK_SECRET is required when email delivery is configured',
        });
    }
    if (environment.TELEGRAM_ENABLED) {
        for (const key of ['TELEGRAM_BOT_TOKEN', 'TELEGRAM_ADMIN_CHAT_ID', 'TELEGRAM_WEBHOOK_SECRET']) {
            if (!environment[key]) {
                context.addIssue({ code: 'custom', path: [key], message: `${key} is required when Telegram is enabled` });
            }
        }
    }
});
export function validateEnvironment(configuration) {
    const result = environmentSchema.safeParse(configuration);
    if (!result.success) {
        throw new Error(`Invalid environment configuration: ${z.prettifyError(result.error)}`);
    }
    return result.data;
}
//# sourceMappingURL=environment.js.map