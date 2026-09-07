# Target architecture

## Shape

The backend is a modular monolith. Each domain owns its presentation, application, domain, and infrastructure code. Controllers validate and translate HTTP only; services orchestrate business rules; repositories own persistence. Cross-domain side effects are durable outbox events consumed by idempotent BullMQ workers.

```text
Flutter mobile / Flutter admin
              |
        HTTPS + REST v1
        WebSocket (events only)
              |
       reverse proxy / CDN
              |
      stateless NestJS replicas
      |        |          |
 PostgreSQL   Redis     R2 object storage
 primary      cache,    original/private media
 + replicas   queues,
              locks
```

The first deploy is one independently scalable API service and one worker service from the same codebase. A domain becomes a microservice only after measured scaling or isolation requirements justify the operational cost.

## Domain boundaries

| Module | Owns |
|---|---|
| auth | identities, password credentials, JWT access tokens, rotating refresh families |
| profiles | profile lifecycle, consent, account status, GDPR export/deletion |
| quests | catalog, picker, assignment, timers, rerolls, QOTD, injections |
| submissions | proof metadata, review state machine, appeals, XP transaction |
| feed | keyset feed query, visibility/block filtering, saved posts |
| social | reactions, comments/replies/mentions, follows, blocks, reports |
| collab | groups, membership, quest abandonment, votes and winners |
| notifications | in-app inbox, FCM devices, templates, push queue |
| media | upload intents, MIME/size policy, signed URLs, variants and cleanup |
| admin | moderation commands, user controls, broadcasts, audit log |
| platform | config, flags, health, metrics, tracing, idempotency, outbox |

## Data and consistency rules

- PostgreSQL constraints remain the final guard for uniqueness and legal values.
- Critical state transitions lock their aggregate and run in one database transaction.
- API retries use idempotency records; background consumers use `processed_messages`.
- A transaction that changes state and emits an event inserts both the state and `outbox_events` atomically.
- Feed/list APIs use keyset cursors and bounded limits; admin exports are asynchronous.
- PostgreSQL uses a bounded pool per replica. Pool sizing is an environment setting and must account for replica count.
- Redis data is disposable unless explicitly documented. PostgreSQL/object storage are authoritative.
- Media bytes never enter PostgreSQL. Private objects are returned through short-lived signed URLs; thumbnails and compressed variants are jobs.

## Security

- Authentication establishes identity; guards/permissions authorize each action.
- Refresh tokens rotate, are hashed at rest, and revoke the family on reuse.
- Service credentials exist only in runtime secret stores.
- Inputs are allow-listed and validated globally; SQL is parameterized.
- Logs redact credentials and tokens and attach a request ID.
- Sensitive admin/account actions append immutable audit records.
- Timeouts, bounded retries with jitter, and circuit breakers wrap external services.

## Delivery and operations

- CI gates formatting, static analysis, unit, integration, E2E, migration checks, image scanning, and contract generation.
- Schema changes are immutable, checksummed, forward-only, transactional, and backward compatible across one deploy window.
- Readiness includes mandatory dependencies; liveness checks process health only.
- Containers run non-root and shut down gracefully. The proxy drains replicas for rolling, canary, or blue-green releases.
- Metrics cover request latency/errors, pool saturation, cache hit rate, queue lag/failures, outbox age, WebSocket count, and business transitions.
- Alerts and dashboards are deployment configuration, not hardcoded application behavior.

