# Architecture

## Shape

Two Flutter clients talk to one self-hosted NestJS API over versioned HTTPS
plus a WebSocket for events. PostgreSQL is authoritative. Redis backs queues,
locks and disposable coordination state. Private media lives in S3-compatible
object storage.

```text
Flutter mobile              Flutter admin web
        \                          /
         \   HTTPS /api/v1        /
          \  WebSocket /realtime /
                    |
              nginx proxy
              (rate limit, WS upgrade)
                    |
        stateless NestJS API replicas
                    |
        +-----------+-----------+-------------+
        |           |           |             |
   PostgreSQL     Redis      R2 / S3     BullMQ worker
   primary        queues,    private     (same codebase,
   (+ replicas)   locks      media        scaled apart)
```

The API (`backend/src/main.ts`) and the worker
(`backend/src/main.worker.ts`) are separate processes built from one codebase
and scale independently. A domain becomes its own service only when measured
scaling or isolation requirements justify the operational cost — not before.

## Backend layering

Each domain under `backend/src/modules/<domain>/` is split the same way:

```text
presentation/    controller + DTO   validate and translate HTTP, nothing else
application/     service            orchestrate the use case
domain/          types              rules and shapes
infrastructure/  repository         parameterised SQL, transactions, locks
```

Rules that hold everywhere:

- Controllers are thin. No business logic, no SQL.
- Services orchestrate; they do not build SQL.
- Repositories own persistence and are the only place SQL exists.
- A repository never calls another domain's repository. Cross-domain effects
  are events.

### Domain boundaries

| Module | Owns |
|---|---|
| `auth` | identities, password credentials, access tokens, rotating refresh families, one-time action tokens |
| `profiles` | profile lifecycle, consent, account status, XP stats, GDPR export/deletion queue |
| `quests` | catalog, picker, assignment, timers, rerolls, Quest of the Day, admin injections |
| `submissions` | proof metadata, review state machine, appeals, XP transaction, moderation queues |
| `feed` | keyset feed query, hot ordering, visibility and block filtering |
| `social` | reactions, comments/replies/mentions, follows, blocks, reports, saved posts and quests |
| `collab` | groups, membership, abandonment, votes and winners |
| `notifications` | in-app inbox, encrypted device tokens, templates, push queue |
| `media` | upload intents, MIME/size policy, signed URLs, variants and cleanup |
| `admin` | moderation commands, user controls, config, broadcasts, audit log, XP audit |
| `account` | device registration, blocks list, deletion queue, private export |
| `public-intake` | public config, waitlist, quest suggestions |
| `search`, `leaderboard`, `health` | reads and probes |
| `integrations/telegram` | moderation bot, alerts, daily summary |

## Client layering

```text
UI widget
  → Riverpod provider
    → abstract repository contract        (packages/app_repositories)
      → Api*Repository                    (HTTP, envelope parsing, media signing)
        → ApiClient                       (transport, timeouts, refresh rotation)
```

Package dependency graph:

```text
app_core              (pure Dart: theme tokens, logger, utils)
app_contracts         (pure Dart: domain values + API field names)
        \       /
       app_models     (models; depends on app_core + contracts)
            |
     app_repositories (contracts + HTTP implementations)
            |
       shared_ui      (Flutter widgets; depends on app_core)
        /      \
mobile_app    admin_web
```

### Composition

Each app has exactly one composition root — `AppBackend` in
`lib/core/backend/app_backend.dart` — which owns a single
`ApiRepositoryBundle`: one HTTP client, one rotating secure token store, and
one instance of each repository. Repository providers are thin accessors onto
that bundle.

This is deliberate. Two HTTP clients means two token stores, which means two
processes racing to spend the same single-use refresh token. Never construct
an `ApiClient`, a token store or a repository inside a screen.

`BackendConfig` resolves `API_URL` at build time and validates it at startup,
so a misconfigured build fails immediately with a readable message rather than
on the first network call. Debug builds fall back to a local API; release
builds require an absolute HTTPS URL and have no fallback.

### Feature layout

Each feature under `lib/features/<feature>/` uses:

- `data/` — providers and datasources
- `domain/` — entities and use cases where the feature warrants them
- `presentation/` — pages, widgets and controllers

Import rules:

- A feature must not import another feature's `presentation/`.
- Features depend on the abstract repository, never on a concrete
  `Api*Repository`.
- Shared models live in `app_models`, never duplicated per feature.

## Data and consistency

- PostgreSQL constraints are the final guard for uniqueness and legal values.
  Uniqueness lives in an index, not in application code.
- Critical state transitions lock their aggregate (`SELECT … FOR UPDATE`, or an
  advisory lock per user for quest assignment) and run in one transaction.
- A transaction that changes state and emits an event inserts the row and its
  `outbox_events` row atomically. The publisher claims events with
  `SKIP LOCKED` and enqueues deterministic BullMQ job IDs. Consumers record
  `processed_messages` only after the real side effect completes, so a retry is
  safe.
- Feed and list APIs use bounded limits; the feed uses keyset cursors. Admin
  exports are asynchronous.
- Redis is disposable unless documented otherwise. PostgreSQL and object
  storage are authoritative.
- Media bytes never enter PostgreSQL. Private objects return short-lived
  signed URLs; thumbnails and compressed variants are jobs.

## Realtime

The API exposes an authenticated Socket.IO namespace at `/realtime`. Clients
join a user room and, on demand, per-post rooms. Because API replicas are
stateless, events fan out through Redis pub/sub so a client connected to one
replica still receives an event emitted by another.

Clients treat realtime as an **invalidation signal**, not as data: an event
invalidates a provider, which refetches over HTTP. That keeps one code path for
reads and means a dropped socket degrades to stale-until-refresh rather than
to wrong.

## Security

- Authentication establishes identity; guards and permissions authorise each
  action. They are separate layers, and admin routes assert a role explicitly.
- Refresh tokens rotate, are hashed at rest, and reuse revokes the whole
  family.
- Sensitive tokens (device push tokens, one-time action tokens) are encrypted
  at rest with dedicated keys.
- Inputs are allow-listed and validated globally
  (`whitelist` + `forbidNonWhitelisted`), so an unknown field is rejected
  rather than ignored.
- SQL is parameterised. Where a fragment must be interpolated it comes only
  from a closed set the DTO already validated, and the code says so.
- Logs redact credentials and attach a request ID, which is echoed to the
  client in the response envelope for correlation.
- Sensitive admin and account actions append immutable audit records.
- External calls have timeouts and bounded retries with jitter.

## API contract

Every response is enveloped:

```json
{ "success": true,  "data": { }, "meta": { "requestId": "…", "timestamp": "…" } }
{ "success": false, "error": { "code": "…", "message": "…" }, "meta": { … } }
```

`error.code` is a stable machine-readable string (`EMAIL_TAKEN`,
`ACTIVE_QUEST_EXISTS`, `ALREADY_APPEALED`, …). Clients branch on the code and
never parse the message. Adding a code is a compatible change; changing the
meaning of one is not.

Routes are versioned by URI under `/api/v1`. OpenAPI is served at `/docs` when
`SWAGGER_ENABLED=true`.

## Delivery and operations

- CI gates formatting, static analysis, unit tests, migration replay from an
  empty database, the checksum ledger, and the integration suite against real
  Postgres and Redis service containers.
- Schema changes are forward-only, checksummed and immutable once applied, and
  must be backward compatible across one deploy window so a rolling deploy is
  safe.
- Readiness checks mandatory dependencies; liveness checks only process health.
- Containers shut down gracefully; the proxy drains replicas for rolling
  releases.
- Metrics worth watching: request latency and errors, pool saturation, queue
  lag and failures, outbox age, WebSocket connection count, and business
  transitions (assignments, approvals, XP awarded).

Index and scalability measurements live in `backend/PERFORMANCE.md`.
