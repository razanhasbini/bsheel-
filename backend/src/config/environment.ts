import { z } from 'zod';

const booleanFromString = z
  .enum(['true', 'false'])
  .default('true')
  .transform((value) => value === 'true');

// An unset env var and one present but empty (`FOO=`) mean the same thing: the
// optional feature is not configured. dotenv and docker-compose both yield ''
// rather than undefined, so normalise before validation — otherwise an empty
// optional URL fails `.url()` instead of reading as absent, and the documented
// `cp .env.example .env` quick start cannot boot.
const emptyToUndefined = (value: unknown): unknown =>
  typeof value === 'string' && value.trim() === '' ? undefined : value;

const optionalString = z.preprocess(emptyToUndefined, z.string().optional());
const optionalUrl = z.preprocess(emptyToUndefined, z.string().url().optional());

const environmentSchema = z
  .object({
    NODE_ENV: z
      .enum(['development', 'test', 'staging', 'production'])
      .default('development'),
    PORT: z.coerce.number().int().positive().max(65_535).default(3000),
    APP_NAME: z.string().min(1).default('bsheel-api'),
    PROCESS_ROLE: z.enum(['api', 'worker']).default('api'),
    APP_VERSION: z.string().min(1).default('1.0.0'),
    API_PREFIX: z.string().min(1).default('api'),
    CORS_ORIGINS: z.string().default('http://localhost:3000'),
    DATABASE_URL: z
      .string()
      .min(1)
      .default('postgresql://bsheel:bsheel@localhost:5432/bsheel'),
    DATABASE_POOL_MIN: z.coerce.number().int().nonnegative().default(2),
    DATABASE_POOL_MAX: z.coerce.number().int().positive().default(10),
    DATABASE_WORKER_POOL_MAX: z.coerce.number().int().positive().default(12),
    DATABASE_CONNECTION_TIMEOUT_MS: z.coerce.number().int().positive().default(5000),
    DATABASE_IDLE_TIMEOUT_MS: z.coerce.number().int().positive().default(30_000),
    DATABASE_STATEMENT_TIMEOUT_MS: z.coerce
      .number()
      .int()
      .positive()
      .default(15_000),
    REDIS_URL: z.string().min(1).default('redis://localhost:6379'),
    REDIS_KEY_PREFIX: z.string().default('bsheel:dev:'),
    OUTBOX_POLL_MS: z.coerce.number().int().min(250).max(60_000).default(250),
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
    // AI proof verification (#47). Off by default: an unconfigured deployment
    // must behave exactly as it did before the feature existed, rather than
    // failing every submission it cannot analyse.
    AI_VERIFICATION_ENABLED: z
      .enum(['true', 'false'])
      .default('false')
      .transform((value) => value === 'true'),
    // Which vision provider runs the analysis. The pipeline is written
    // against an interface, so this is the only place the choice appears.
    AI_VERIFICATION_PROVIDER: z.enum(['openai', 'anthropic']).default('openai'),
    ANTHROPIC_API_KEY: optionalString,
    OPENAI_API_KEY: optionalString,

    // Shadow mode: the agent analyses and records, and acts on nothing. The
    // default, and it stays the default until an eval has scored the agent
    // against real human decisions. Shipping an approval agent whose accuracy
    // nobody has measured is not a feature.
    AI_VERIFICATION_SHADOW_MODE: z
      .enum(['true', 'false'])
      .default('true')
      .transform((value) => value === 'true'),

    // Three rungs, because the price spread between them is ~50x and most
    // submissions never need the top one. Pinned rather than floating, so a
    // model change is a deploy and shows up in the verdict rows that record
    // which model produced them.
    //
    // The asymmetry is the point: the cheapest model may wave a clean
    // submission through, but only the most capable model may conclude that a
    // user's proof is fake.
    AI_VERIFICATION_MODEL_TRIAGE: z.string().default('gpt-5.6-luna'),
    AI_VERIFICATION_MODEL_DEEP: z.string().default('gpt-5.6-sol'),
    AI_VERIFICATION_MODEL_REJECT: z.string().default('gpt-6-astra'),
    // Used when AI_VERIFICATION_PROVIDER=anthropic.
    AI_VERIFICATION_MODEL_TRIAGE_ANTHROPIC: z.string().default('claude-haiku-4-5'),
    AI_VERIFICATION_MODEL_DEEP_ANTHROPIC: z.string().default('claude-sonnet-5'),
    AI_VERIFICATION_MODEL_REJECT_ANTHROPIC: z.string().default('claude-opus-5'),
    AI_VERIFICATION_TIMEOUT_MS: z.coerce.number().int().min(5_000).max(300_000).default(60_000),
    // Confidence floors, separately tunable because the two errors are not
    // symmetric. A false approval costs leaderboard integrity and is
    // recoverable through takedown and XP rollback; a false rejection tells an
    // honest player they cheated, which is a churn event. So the reject bar
    // sits higher, and both are set from the eval rather than by taste.
    AI_VERIFICATION_APPROVE_MIN_CONFIDENCE: z.coerce.number().min(0).max(1).default(0.85),
    AI_VERIFICATION_REJECT_MIN_CONFIDENCE: z.coerce.number().min(0).max(1).default(0.95),
    // Perceptual-hash distance at or below which two images are the same
    // picture. Exposed so the eval harness can sweep it.
    AI_VERIFICATION_NEAR_DUPLICATE_DISTANCE: z.coerce.number().int().min(0).max(32).default(10),
    // Vision input cap per image. The Messages API rejects oversized images,
    // and base64 inflates bytes by ~4/3, so this sits well under the request
    // ceiling rather than at it.
    AI_VERIFICATION_MAX_IMAGE_BYTES: z.coerce.number().int().min(65_536).max(5_242_880).default(3_145_728),
    // How many images from one submission are sent. Proof is usually one
    // frame; the cap stops a mixed-media submission becoming an unbounded
    // request.
    AI_VERIFICATION_MAX_IMAGES: z.coerce.number().int().min(1).max(8).default(4),
    // Video is read whole to be decoded, so its cap is the submission cap
    // rather than the per-image one.
    AI_VERIFICATION_MAX_VIDEO_BYTES: z.coerce.number().int().min(1_048_576).max(104_857_600).default(52_428_800),
    // Frames sampled evenly across the clip. Enough to see the activity,
    // few enough that a video costs a small multiple of a photo.
    AI_VERIFICATION_VIDEO_FRAMES: z.coerce.number().int().min(1).max(8).default(3),
    AI_VERIFICATION_FFMPEG_TIMEOUT_MS: z.coerce.number().int().min(5_000).max(120_000).default(30_000),
    AI_VERIFICATION_SWEEP_INTERVAL_MS: z.coerce.number().int().min(60_000).max(86_400_000).default(900_000),
    AI_VERIFICATION_SWEEP_BATCH_SIZE: z.coerce.number().int().min(1).max(200).default(25),
    AI_VERIFICATION_MAX_ATTEMPTS: z.coerce.number().int().min(1).max(10).default(3),
    R2_ENDPOINT: optionalUrl,
    R2_REGION: z.string().default('auto'),
    // MinIO (and any self-hosted S3) addresses buckets as a path segment
    // rather than a subdomain, because there is no wildcard DNS in front of
    // it. Cloudflare R2 accepts both, so this is safe to leave on.
    S3_FORCE_PATH_STYLE: z
      .enum(['true', 'false'])
      .default('false')
      .transform((value) => value === 'true'),
    R2_ACCESS_KEY_ID: optionalString,
    R2_SECRET_ACCESS_KEY: optionalString,
    R2_BUCKET: optionalString,
    R2_PUBLIC_BASE_URL: optionalUrl,
    SIGNED_URL_TTL_SECONDS: z.coerce.number().int().positive().default(900),

    // Per-user object caps. The deleted Cloudflare worker enforced these by
    // listing the user's bucket prefix on every upload; they are now an
    // indexed COUNT. Generous on purpose — they exist to bound a runaway
    // client or a scripted abuse case, not to ration normal use.
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
    // Size caps were hard-coded in the service. Same class of magic number.
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

    // How long an object may sit unreferenced before the reclaim sweep takes
    // it. A user can hold a presigned URL and upload minutes later, and a
    // submission is created after its object completes, so the grace period
    // must comfortably exceed both. Too short reclaims live media.
    // Streak reminders (#46). A streak whose last approved day was
    // yesterday dies at the end of today, so the reminder is only useful
    // while that is true. Runs hourly by default rather than once a day
    // because "today" differs per reader and a single fixed hour would reach
    // half the users after their streak had already lapsed.
    /**
     * The timezone whose calendar days a streak is counted in.
     *
     * This was UTC, and the app's users are in UTC+3, so the day boundary
     * fell at 03:00 local. Two submissions at 23:00 and 01:00 local are two
     * consecutive days to the person who made them and one single day to a
     * UTC bucket, so a late-night post did not advance the streak — issue
     * #63, reproduced. Every local midnight-to-03:00 submission was being
     * credited to the previous day.
     *
     * A single zone rather than one per user: the audience is one country,
     * and a per-user zone needs a column, a client that reports it, and a
     * decision about what happens when someone travels. Configurable so
     * that decision can change without a code change.
     */
    STREAK_TIMEZONE: z.string().min(1).default('Asia/Beirut'),
    STREAK_REMINDER_ENABLED: z
      .enum(['true', 'false'])
      .default('true')
      .transform((value) => value === 'true'),
    STREAK_REMINDER_INTERVAL_MS: z.coerce
      .number()
      .int()
      .min(60_000)
      .default(3_600_000),
    STREAK_REMINDER_BATCH_SIZE: z.coerce
      .number()
      .int()
      .min(1)
      .max(5000)
      .default(500),
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
    if (environment.DATABASE_POOL_MIN > Math.min(environment.DATABASE_POOL_MAX, environment.DATABASE_WORKER_POOL_MAX)) {
      context.addIssue({
        code: 'custom',
        path: ['DATABASE_POOL_MIN'],
        message: 'DATABASE_POOL_MIN cannot exceed DATABASE_POOL_MAX',
      });
    }

    // Caught at startup rather than on the first streak query. An unknown
    // zone name makes Postgres raise on every one of them, which would look
    // like the streak feature being broken rather than a typo in the config.
    try {
      new Intl.DateTimeFormat('en-US', { timeZone: environment.STREAK_TIMEZONE });
    } catch {
      context.addIssue({
        code: 'custom',
        path: ['STREAK_TIMEZONE'],
        message: `STREAK_TIMEZONE must be an IANA timezone name (got "${environment.STREAK_TIMEZONE}")`,
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

    // Fail at boot rather than on the first submission. A deployment that
    // claims to verify proof and silently cannot is worse than one that
    // refuses to start.
    if (environment.AI_VERIFICATION_ENABLED) {
      const keyForProvider = environment.AI_VERIFICATION_PROVIDER === 'openai'
        ? 'OPENAI_API_KEY' as const
        : 'ANTHROPIC_API_KEY' as const;
      if (!environment[keyForProvider]) {
        context.addIssue({
          code: 'custom',
          path: [keyForProvider],
          message: `${keyForProvider} is required when AI_VERIFICATION_ENABLED is true and the provider is ${environment.AI_VERIFICATION_PROVIDER}`,
        });
      }
      // A reject bar at or below the approve bar means the more damaging
      // decision is the easier one to reach. Refuse to boot rather than
      // discover it from a user's appeal.
      if (environment.AI_VERIFICATION_REJECT_MIN_CONFIDENCE < environment.AI_VERIFICATION_APPROVE_MIN_CONFIDENCE) {
        context.addIssue({
          code: 'custom',
          path: ['AI_VERIFICATION_REJECT_MIN_CONFIDENCE'],
          message: 'AI_VERIFICATION_REJECT_MIN_CONFIDENCE must be >= AI_VERIFICATION_APPROVE_MIN_CONFIDENCE: rejecting a user is the more costly error and must not be the easier one to reach',
        });
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
