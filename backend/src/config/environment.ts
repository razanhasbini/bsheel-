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
    QUEST_MAINTENANCE_ENABLED: z
      .enum(['true', 'false'])
      .default('true')
      .transform((value) => value === 'true'),
    QUEST_MAINTENANCE_INTERVAL_MS: z.coerce.number().int().min(60_000).default(300_000),
    PENDING_REVIEW_REMINDER_INTERVAL_MS: z.coerce.number().int().min(60_000).default(3_600_000),
    QUEST_MAINTENANCE_BATCH_SIZE: z.coerce.number().int().min(1).max(5000).default(500),
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

    // AI agent phase — submission verification only. Every flag below
    // defaults to disabled, so the pipeline is fully inert until turned on
    // deliberately. QoS on Demand / Emergency Mode is out of scope here.
    AGENT_SUBMISSION_VERIFICATION_ENABLED: z
      .enum(['true', 'false'])
      .default('false')
      .transform((value) => value === 'true'),
    OPENAI_AGENT_ENABLED: z
      .enum(['true', 'false'])
      .default('false')
      .transform((value) => value === 'true'),
    OPENAI_API_KEY: optionalString,
    OPENAI_AGENT_MODEL: optionalString,
    OPENAI_AGENT_TIMEOUT_MS: z.coerce.number().int().min(1000).max(120_000).default(30_000),
    OPENAI_AGENT_MAX_TURNS: z.coerce.number().int().min(1).max(20).default(6),
    OPENAI_AGENT_PROMPT_VERSION: z.string().min(1).default('v1'),
    OPENAI_TRACING_ENABLED: z
      .enum(['true', 'false'])
      .default('false')
      .transform((value) => value === 'true'),
    OPENAI_PROJECT_ID: optionalString,
    OPENAI_ORGANIZATION_ID: optionalString,

    // Nokia Network-as-Code / CAMARA. Provider failures are mapped to
    // UNAVAILABLE so they can never masquerade as negative evidence.
    CAMARA_ENABLED: z
      .enum(['true', 'false'])
      .default('false')
      .transform((value) => value === 'true'),
    CAMARA_BASE_URL: optionalUrl,
    // The official Network-as-Code SDK used by the location/geofencing
    // adapters authenticates through the Nokia/RapidAPI application key.
    CAMARA_API_KEY: optionalString,
    CAMARA_TOKEN_URL: optionalUrl,
    CAMARA_CLIENT_ID: optionalString,
    CAMARA_CLIENT_SECRET: optionalString,
    CAMARA_SCOPE: optionalString,
    CAMARA_REQUEST_TIMEOUT_MS: z.coerce.number().int().min(1000).max(60_000).default(10_000),
    // Public base URL CAMARA posts geofence entry/exit events to. The local
    // subscription id is appended; authentication uses a bearer sink
    // credential and the secret never appears in the URL, e.g.
    // https://api.bsheel.app/api/v1/integrations/camara/geofencing
    // Must be reachable from the internet or no geofence evidence arrives.
    CAMARA_GEOFENCING_SINK_BASE_URL: optionalUrl,
    // The `x-rapidapi-host` ROUTING KEY, not a connect address. Defaults to
    // network-as-code.nokia.rapidapi.com (see camara-client.factory.ts) —
    // the value Nokia documents, and the only one that routes to the API.
    // Leave blank unless Nokia moves the API within their hub.
    CAMARA_RAPIDAPI_HOST: optionalString,

    // CAMARA Number Verification (issue #1) — a separate 3-legged flow from
    // the evidence adapter above. AUTHORIZE_URL/TOKEN_URL are not published
    // in Nokia's public docs; they come from the Nokia dashboard once this
    // product is registered there, same place the redirect_uri is registered.
    CAMARA_NUMBER_VERIFICATION_AUTHORIZE_URL: optionalUrl,
    CAMARA_NUMBER_VERIFICATION_TOKEN_URL: optionalUrl,
    CAMARA_NUMBER_VERIFICATION_CLIENT_ID: optionalString,
    CAMARA_NUMBER_VERIFICATION_CLIENT_SECRET: optionalString,
    // Our own backend callback, registered with Nokia as the redirect_uri.
    CAMARA_NUMBER_VERIFICATION_REDIRECT_URI: optionalUrl,
    // Where the backend sends the browser after completing the flow, so the
    // mobile app's universal link / deep link handler picks it up. Carries
    // only an opaque, short-lived handoff code — never a token.
    PHONE_SIGNIN_MOBILE_REDIRECT_URL: optionalUrl,

    // Computer vision. 'none' is the fail-closed default (NullCvEvidenceProvider);
    // 'http' calls an external service at CV_SERVICE_BASE_URL implementing
    // the CvEvidenceSchema contract (see http-cv-evidence.provider.ts).
    CV_PROVIDER: z.enum(['none', 'http']).default('none'),
    CV_SERVICE_BASE_URL: optionalUrl,
    CV_SERVICE_AUTH_TOKEN: optionalString,
    CV_TIMEOUT_MS: z.coerce.number().int().min(1000).max(120_000).default(20_000),
    SUBMISSION_VERIFICATION_CONCURRENCY: z.coerce.number().int().min(1).max(20).default(2),

    // The absolute range any AI recommendation is clamped into, never
    // overridden by a model output. 4 hours is the floor even for the
    // simplest at-home quest; 2 weeks is the rare ceiling for genuine
    // long-distance travel. XP runs 5 (simple, no travel) to 100 (hard,
    // travelled for it). The per-user shaping inside this range lives in
    // verification-policy.ts.
    AGENT_QUEST_TIME_MIN_MINUTES: z.coerce.number().int().positive().default(240),
    AGENT_QUEST_TIME_MAX_MINUTES: z.coerce.number().int().positive().default(20_160),
    AGENT_XP_MIN: z.coerce.number().int().nonnegative().default(5),
    AGENT_XP_MAX: z.coerce.number().int().positive().default(100),
    AGENT_APPROVE_CONFIDENCE_THRESHOLD: z.coerce.number().min(0).max(1).default(0.85),
    AGENT_REJECT_CONFIDENCE_THRESHOLD: z.coerce.number().min(0).max(1).default(0.85),
  })
  .superRefine((environment, context) => {
    if (environment.DATABASE_POOL_MIN > Math.min(environment.DATABASE_POOL_MAX, environment.DATABASE_WORKER_POOL_MAX)) {
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

    if (environment.OPENAI_AGENT_ENABLED) {
      for (const key of ['OPENAI_API_KEY', 'OPENAI_AGENT_MODEL'] as const) {
        if (!environment[key]) {
          context.addIssue({ code: 'custom', path: [key], message: `${key} is required when OPENAI_AGENT_ENABLED is true` });
        }
      }
    }

    if (environment.CAMARA_ENABLED) {
      if (!environment.CAMARA_API_KEY) {
        context.addIssue({
          code: 'custom',
          path: ['CAMARA_API_KEY'],
          message: 'CAMARA_API_KEY is required when CAMARA_ENABLED is true',
        });
      }
    }

    if (environment.CV_PROVIDER === 'http' && !environment.CV_SERVICE_BASE_URL) {
      context.addIssue({ code: 'custom', path: ['CV_SERVICE_BASE_URL'], message: "CV_SERVICE_BASE_URL is required when CV_PROVIDER is 'http'" });
    }

    // Phone verification is not optional — every account is anchored to a
    // CAMARA-verified number, and there is deliberately no switch that
    // turns the gate off (see migration 0031). So a deployed environment
    // that cannot reach Nokia is a broken deployment, not a degraded one:
    // fail at boot, loudly, rather than let every user hit an unpassable
    // VERIFY YOUR PHONE wall.
    //
    // Same NODE_ENV shape as the secret check above: dev and test machines
    // still enforce the gate in the app, they just don't need real Nokia
    // credentials to start the server or run the suite. The OAuth endpoints
    // and client credentials are never configured by hand — they come from
    // Nokia at call time via CamaraOAuthMetadataService.
    if (environment.NODE_ENV === 'production' || environment.NODE_ENV === 'staging') {
      for (const key of [
        'CAMARA_NUMBER_VERIFICATION_REDIRECT_URI',
        'PHONE_SIGNIN_MOBILE_REDIRECT_URL',
        'CAMARA_API_KEY',
      ] as const) {
        if (!environment[key]) {
          context.addIssue({
            code: 'custom',
            path: [key],
            message: `${key} is required — phone verification is mandatory for every account`,
          });
        }
      }
    }

    if (environment.AGENT_QUEST_TIME_MIN_MINUTES > environment.AGENT_QUEST_TIME_MAX_MINUTES) {
      context.addIssue({ code: 'custom', path: ['AGENT_QUEST_TIME_MIN_MINUTES'], message: 'AGENT_QUEST_TIME_MIN_MINUTES cannot exceed AGENT_QUEST_TIME_MAX_MINUTES' });
    }
    if (environment.AGENT_XP_MIN > environment.AGENT_XP_MAX) {
      context.addIssue({ code: 'custom', path: ['AGENT_XP_MIN'], message: 'AGENT_XP_MIN cannot exceed AGENT_XP_MAX' });
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
