# Bsheel API

NestJS 11 modular monolith that replaces the legacy Supabase application
backend while preserving its product behavior. PostgreSQL is authoritative,
Redis backs queues and disposable coordination state, and private media lives
in S3-compatible object storage (Cloudflare R2 in production).

The Flutter applications remain in `../apps`. Shared models and both legacy
and Nest repository adapters are in `../packages` during the controlled
strangler migration.

## Requirements

- Node.js 24 or newer
- PostgreSQL 17
- Redis 7.4
- S3-compatible object storage for real media integration

Copy `.env.example` to a local, untracked environment file and replace every
development secret. Production startup rejects placeholder secrets.

## Local commands

```bash
npm ci
npm run db:migrate
npm run start:dev
npm run start:worker
```

Password recovery tokens are SHA-256 indexed, AES-256-GCM encrypted at rest,
single-use, and delivered only by the worker. Configure
`AUTH_ACTION_TOKEN_ENCRYPTION_KEY`, `APP_PUBLIC_URL`,
`EMAIL_DELIVERY_WEBHOOK_URL`, and `EMAIL_DELIVERY_WEBHOOK_SECRET`; the API never
returns a raw recovery token and unknown-email requests deliberately return the
same response.

The default API prefix and version are `/api/v1`. Swagger is available at
`/docs` when `SWAGGER_ENABLED=true`.

```bash
npm run lint
npm test
npm run test:e2e
npm run build
npm run db:migrate:check
```

With the local PostgreSQL and Redis services running, the stateful contract
journey is:

```bash
DATABASE_URL=postgresql://bsheel:bsheel@127.0.0.1:54329/bsheel \
API_BASE_URL=http://127.0.0.1:3010/api/v1 \
npm run test:smoke
```

## Architecture

Each domain is split into presentation, application, domain, and
infrastructure layers. Controllers only validate/translate HTTP. Services
orchestrate use cases, repositories own parameterized persistence, and
critical state changes use row/advisory locks inside transactions.

State-changing transactions append `outbox_events`. The publisher claims
events with `SKIP LOCKED` and enqueues deterministic BullMQ job IDs with
exponential retries. The separate worker records `processed_messages` only
after its real side effect completes. It performs encrypted-token Firebase
fanout, transactional auth email, cross-instance Socket.IO invalidation,
private R2 GDPR export generation, idempotent account erasure, Telegram
signup/report/submission alerts, and the 06:00 UTC admin summary. Realtime
connections use access-token authentication and user/admin/post rooms; Redis
pub/sub fans each event to every horizontally scaled API instance. The
allowlisted Telegram webhook uses constant-time secret verification,
duplicate suppression, persisted multi-step command state, and canonical
moderation services. Thumbnail generation remains an explicit migration
ledger item.

Database migrations are forward-only, checksummed, and immutable after
application. Use a new numbered migration for every schema correction.

See [the architecture record](../docs/migration/ARCHITECTURE.md),
[parity ledger](../docs/migration/PARITY_LEDGER.md), and
[legacy source audit](../docs/migration/SOURCE_AUDIT.md).

## Containers

From the repository root:

```bash
docker compose up --build
```

The compose topology provides PostgreSQL, Redis, a one-shot migration task,
the stateless API, a separately scalable BullMQ worker, and an Nginx reverse
proxy. Runtime secrets must be supplied by the deployment platform rather
than committed env files. Set `PUSH_NOTIFICATIONS_ENABLED=true` only with a
valid `FIREBASE_SERVICE_ACCOUNT` secret.
