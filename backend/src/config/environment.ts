import { z } from 'zod';

const booleanFromString = z
  .enum(['true', 'false'])
  .default('true')
  .transform((value) => value === 'true');

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
    FIREBASE_SERVICE_ACCOUNT: z.string().optional(),
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
    EMAIL_DELIVERY_WEBHOOK_URL: z.string().url().optional(),
    EMAIL_DELIVERY_WEBHOOK_SECRET: z.string().optional(),
    EMAIL_TIMEOUT_MS: z.coerce.number().int().min(1000).max(60_000).default(10_000),
    TELEGRAM_ENABLED: z
      .enum(['true', 'false'])
      .default('false')
      .transform((value) => value === 'true'),
    TELEGRAM_BOT_TOKEN: z.string().optional(),
    TELEGRAM_ADMIN_CHAT_ID: z.string().optional(),
    TELEGRAM_WEBHOOK_SECRET: z.string().optional(),
    TELEGRAM_ALLOWED_CHAT_IDS: z.string().default(''),
    TELEGRAM_TIMEOUT_MS: z.coerce.number().int().min(1000).max(60_000).default(10_000),
    TELEGRAM_API_BASE_URL: z.string().url().default('https://api.telegram.org'),
    R2_ENDPOINT: z.string().url().optional(),
    R2_REGION: z.string().default('auto'),
    R2_ACCESS_KEY_ID: z.string().optional(),
    R2_SECRET_ACCESS_KEY: z.string().optional(),
    R2_BUCKET: z.string().optional(),
    R2_PUBLIC_BASE_URL: z.string().url().optional(),
    SIGNED_URL_TTL_SECONDS: z.coerce.number().int().positive().default(900),
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
      for (const key of ['JWT_ACCESS_SECRET', 'JWT_REFRESH_SECRET', 'DEVICE_TOKEN_ENCRYPTION_KEY', 'AUTH_ACTION_TOKEN_ENCRYPTION_KEY'] as const) {
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
      for (const key of ['TELEGRAM_BOT_TOKEN', 'TELEGRAM_ADMIN_CHAT_ID', 'TELEGRAM_WEBHOOK_SECRET'] as const) {
        if (!environment[key]) {
          context.addIssue({ code: 'custom', path: [key], message: `${key} is required when Telegram is enabled` });
        }
      }
    }
  });

export type Environment = z.infer<typeof environmentSchema>;

export function validateEnvironment(configuration: Record<string, unknown>): Environment {
  const result = environmentSchema.safeParse(configuration);
  if (!result.success) {
    throw new Error(`Invalid environment configuration: ${z.prettifyError(result.error)}`);
  }
  return result.data;
}
