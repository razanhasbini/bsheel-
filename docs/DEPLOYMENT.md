# Deployment

## What ships, and how

There are three separate deliverables with three different paths:

| Deliverable | Path | Automated? |
|---|---|---|
| API + worker (`backend/`) | container image → your host | **not yet wired** |
| Admin dashboard (`apps/admin_web`) | Flutter web build → static hosting | **not yet wired** |
| Business dashboard (`apps/business_web`) | Flutter web build → static hosting under the admin origin at `/business` | **not yet wired** |
| Mobile app | App Store / Play Store via `scripts/ios_release.sh` | manual, see `PUBLISHING.md` |

> **Status, stated plainly.** This repository has a complete, working local
> container topology and no production deployment pipeline. The previous
> `deploy-server.yml` workflow was removed: it rsynced the *legacy Supabase*
> edge functions and SQL to a shared production host, which no longer matches
> what the applications talk to, and firing it from this repository would have
> pushed obsolete code at a live box running five unrelated services.
>
> Wiring a real pipeline needs decisions only the owner can make — where the
> API runs, where secrets come from, and what the rollback story is. The
> sections below give the shape and the constraints.

## Local / staging stack

```bash
cp backend/.env.example backend/.env    # then replace every development secret
docker compose up --build
# API:     http://localhost:8080/api/v1
# OpenAPI: http://localhost:8080/docs
```

`docker-compose.yml` brings up six services:

| Service | Role |
|---|---|
| `postgres` | PostgreSQL 17, published on `127.0.0.1:54329` |
| `redis` | Redis 7.4, append-only, `noeviction`, on `127.0.0.1:63799` |
| `migrate` | one-shot migration runner; the API waits for it to complete successfully |
| `api` | stateless NestJS API |
| `worker` | BullMQ worker from the same image, scaled separately |
| `proxy` | nginx on `:8080` — rate limiting, WebSocket upgrade, request IDs |

**This compose file is for local use only.** `api` and `worker` read
`backend/.env.example`, so they boot with placeholder secrets. Production must
supply real values from the deployment platform's secret store — never from a
committed env file. The environment schema rejects placeholder secrets when
`NODE_ENV=production`.

Scale the worker independently:

```bash
docker compose up -d --scale worker=3
```

## What a production deployment must satisfy

These follow from how the backend is built, so treat them as requirements
rather than suggestions.

**Migrations run before new code.** The `migrate` service is a one-shot job and
the API depends on `service_completed_successfully`. Any orchestrator must
preserve that ordering. Migrations are forward-only, checksummed and immutable
once applied — `backend/scripts/migrate.mjs` refuses to run a modified applied
migration.

**Schema changes must be backward compatible across one deploy window.**
During a rolling release both old and new code run against the same schema. Add
a column, deploy, backfill, then remove the old path in a later release. Never
in one step.

**API replicas are stateless.** Sessions are JWTs; realtime fanout goes through
Redis pub/sub. That is what makes horizontal scaling safe — do not introduce
in-process state that a second replica would not see.

**Pool size multiplies per replica.** `DATABASE_POOL_MAX` defaults to 20, so
five replicas plus workers can demand 120+ connections. Size it against
PostgreSQL's `max_connections`, or put a pooler in front. See
`backend/PERFORMANCE.md`.

**Readiness gates traffic; liveness does not.** `/api/v1/health/ready` checks
PostgreSQL and Redis and should gate load-balancer membership.
`/api/v1/health/live` only reports process health — never gate on it, or a
database blip will restart every container at once.

**Graceful shutdown is already wired** (`enableShutdownHooks`, 30s
`stop_grace_period`). Give the proxy time to drain before SIGKILL.

**Secrets required at runtime**, all rejected as placeholders in production:
`JWT_ACCESS_SECRET`, `JWT_REFRESH_SECRET`, `DEVICE_TOKEN_ENCRYPTION_KEY`,
`AUTH_ACTION_TOKEN_ENCRYPTION_KEY`, plus provider credentials for whatever is
enabled (`FIREBASE_SERVICE_ACCOUNT`, R2 keys, `EMAIL_DELIVERY_WEBHOOK_*`,
`TELEGRAM_*`). Each of the four crypto secrets must be independent — reusing
one across two purposes means one leak compromises both.

**Integrations fail silently when unconfigured — check them explicitly.**
`TELEGRAM_ENABLED`, `PUSH_NOTIFICATIONS_ENABLED` and the email delivery webhook
each default to off, and the environment schema treats an empty value as
"absent". That is the right default, but it means a half-configured
environment looks healthy while doing nothing. This exact failure mode once
cost the legacy system 165 submissions that never reached the moderation
channel, and five password resets that sent no email, with nothing alerting.
After any environment bring-up, assert delivery end to end rather than assuming
it: send one test notification, one test email, and one Telegram message.

**Feature flags fail closed.** `app_config` rows seeded by migration `0014`
drive the social-login kill switch, maintenance mode and the force-update gate.
An absent row reads as "off" in the client, which is the safe direction for a
kill switch. Confirm the rows exist after any fresh database bring-up.

## Admin dashboard

A static Flutter web bundle:

```bash
cd apps/admin_web
flutter build web --dart-define=API_URL=https://api.bsheel.app/api/v1
# → build/web
```

It is a public bundle, so it must not carry secrets — the API enforces
authorisation, and admin routes assert a role. Put an outer access control
layer (basic auth or SSO) in front of it anyway; it is an admin surface and
defence in depth is cheap here.

Serve `/.well-known/assetlinks.json` and
`/.well-known/apple-app-site-association` from the same origin if deep links
are in use — see `docs/deep_links/README.md`.

## Business dashboard

A second static Flutter web bundle (`apps/business_web`), served **under the
admin origin at `/business`** rather than on its own subdomain:

```bash
cd apps/business_web
flutter build web \
  --base-href=/business/ \
  --dart-define=API_URL=https://api.bsheel.app/api/v1
# → build/web  (serve at https://admin.bsheel.app/business/)
```

Three things make that placement the right one, and they are worth knowing
before someone "tidies it up" onto `business.bsheel.app`:

- **It needs no CORS change.** `CORS_ORIGINS` is an exact-match allowlist
  (`src/main.ts`) that gates HTTP *and* the WebSocket adapter, and production
  carries `https://admin.bsheel.app` alone. An origin is scheme + host +
  port, so a bundle at `/business` on that host is already allowed. A new
  subdomain would load perfectly and fail every API call until someone adds
  the origin and restarts the API. If you do want the subdomain, add it
  first: `CORS_ORIGINS=https://admin.bsheel.app,https://business.bsheel.app`.
- **It is a separate app, not a route in the admin console.** `SEC-027` in
  `admin_router.dart` bounces every signed-in non-admin to the login gate so
  feature pages never run their reads for one. A business member is an
  ordinary user with no admin role, so putting the dashboard inside
  `admin_web` would mean carving an exception into that control. A separate
  bundle keeps it untouched, and businesses never reach the console.
- **Its token store namespace is `bsheel.business`.** Same origin means
  shared browser storage, so a shared namespace would have an admin and a
  business owner in one browser silently evict each other's session.

Serving requirements: the path must fall back to `/business/index.html` for
unknown sub-paths (Flutter web uses path URLs, so a deep link like
`/business/?business=<id>` must not 404), and the bundle carries no secrets —
authorisation is the API's, by membership and subscription.

The mobile app links here via `DASHBOARD_URL` in
`apps/mobile_app/dart_defines.release.json`. It is a build-time value and
deliberately not derived from `API_URL`: guessing a host produces a link that
looks right, ships, and 404s for every owner who taps it.

## Mobile app

Not deployed by any backend pipeline. It ships through the App Store and Play
Store. See [`PUBLISHING.md`](PUBLISHING.md).

A release build compiles `apps/mobile_app/dart_defines.release.json`, which
carries `API_URL`. A build made without it signs and installs perfectly and
cannot reach the API, which is why `scripts/ios_release.sh` refuses to run when
the file is missing.

**Client builds pin the API URL at compile time.** Moving the API to a new
hostname therefore requires an app release, so put the API behind a stable
hostname you control from the start.

## Rules that keep deploys safe

- **Never edit a server by hand.** A manual change drifts the host away from
  git and skips migration tracking. Whatever pipeline you build, make it the
  only path.
- **Never edit an applied migration.** Add the next number.
- **Use a disposable database for tests.** Never point a test suite at
  production; the integration suite creates and deletes real rows.
- **Verify a fresh bring-up replays cleanly** (`npm run db:migrate` from empty,
  then `npm run db:migrate:check`) before trusting a new environment.
- **Test backup restoration before you need it.** An untested backup is a
  hypothesis.
