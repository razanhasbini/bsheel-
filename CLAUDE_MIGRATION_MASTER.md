# Bsheel migration master handoff

Last updated: 2026-09-07 (Asia/Beirut)

This is the authoritative continuation document for migrating the legacy
Bsheel checkout to the standalone NestJS-backed Bsheel repository. Read this
entire file before changing code. Then read the focused documents under
**Required reading**. The root `CLAUDE.md` contains required legacy product
behavior, but this file takes precedence for migration status and workflow.

## Mission and non-negotiable outcome

Reproduce the existing product exactly while replacing Supabase as the runtime
backend with a maintainable production NestJS/Node.js backend. Keep both
Flutter applications and their UI/product logic. The target is a modular
monolith built for stateless horizontal scaling, clear domain layers,
PostgreSQL, Redis/BullMQ, R2-compatible object storage, durable events,
versioned contracts, and strong automated evidence.

This is a parity migration, not a redesign. Do not silently simplify a legacy
behavior, state transition, notification, permission, copy string, ordering
rule, or edge case. Improvements are acceptable only when they preserve the
observable contract or deliberately fix a documented defect.

## Paths and repository relationship

- Legacy authority: `/Users/razanhasbini/Desktop/bsheel2/4hoursonly`
- New standalone repository: `/Users/razanhasbini/Desktop/bsheel2/new bsheel`
- New backend: `new bsheel/backend`
- Flutter mobile: `new bsheel/apps/mobile_app`
- Flutter admin: `new bsheel/apps/admin_web`
- Shared REST adapters: `new bsheel/packages/app_repositories`
- Legacy SQL/functions retained as evidence: `new bsheel/supabase`
- Legacy media workers retained as evidence: `new bsheel/cloudflare`

Never edit the original. Read it to resolve ambiguity and compare later SQL
redefinitions. Do not delete the copied `supabase/`, `cloudflare/`, or
`Supabase*Repository` code yet: they are the behavior oracle and rollback path.

The target is not currently a Git repository. The owner plans to put it in a
new repository after migration, so do not assume Git can recover an overwrite.

## Current truth

The migration is substantial but **not complete**. The Nest backend and most
shared Flutter REST adapters exist. Mobile composition and many high-traffic
surfaces can run in Nest mode. The admin feature pages still contain substantial
direct Supabase access. Live-provider fixtures, data-migration rehearsals, and
full end-to-end parity journeys remain.

Production/normal Flutter builds default to legacy. Nest mode is an explicit
compile-time canary:

```bash
--dart-define=BACKEND_MODE=nest \
--dart-define=NEST_API_URL=https://api.example.com/api/v1
```

Supported modes are `legacy` and `nest`; the Nest URL must be absolute and
production must use HTTPS. Do not change the default until all required
journeys are verified and a rollback-capable canary has run.

## Required reading

1. `docs/migration/README.md` — phases and exact source-reading order.
2. `docs/migration/PARITY_LEDGER.md` — domain status and evidence.
3. `docs/migration/ARCHITECTURE.md` — target boundaries and operating rules.
4. `docs/migration/SOURCE_AUDIT.md` — immutable snapshot audit.
5. `docs/database_contract.md` — database contract discipline.
6. Root `README.md`, `CLAUDE.md`, and `FIXLOG.md` — product behavior/fixes.
7. Every relevant definition in `supabase/migrations/`, in chronological
   order, then `supabase/functions_canonical/` where present.
8. Matching repository, Dart model/constants, providers, UI callers, and tests.

Never implement from the first SQL function with a matching name. Later legacy
migrations frequently redefine earlier behavior.

## Source audit and preservation

The target started from legacy commit
`c739439bce0508dc1a29ceea63b3a4cf548d3ca4`:

- 638 tracked legacy files;
- 411 relevant app/shared/backend-reference files;
- about 122,000 relevant lines;
- 150 numbered legacy database migrations;
- 19 client-visible tables and 36 named client RPCs;
- two Flutter applications and five shared Dart packages.

Run from the target root:

```bash
./scripts/verify-legacy-snapshot.sh
```

It byte-compares every unlisted tracked Flutter, Supabase, and Cloudflare file
against the original. Every intentionally changed tracked file must appear as
one exact repository-relative line in
`scripts/legacy-migration-allowlist.txt`. Do not add wildcards/directories or
unrelated files to hide drift. New files need no allowlist entry.

The allowlist is an audit log, not parity proof. Keep Nest/legacy branches
isolated and rerun the verifier after every tracked legacy edit.

## Implemented target architecture

The backend is a NestJS 11 modular monolith:

```text
presentation/controller + validated DTO
              -> application/service
              -> infrastructure/repository
              -> PostgreSQL / Redis / R2 / external provider
```

Controllers stay thin. Services/repositories own business rules and
transactions. SQL is parameterized. Slow/cross-domain effects use the
transactional outbox and idempotent consumers, not request handlers.

Implemented modules:

- `auth`: password signup/login, access/rotating refresh tokens, logout,
  encrypted one-time confirmation/recovery tokens, Google/Apple verification;
- `profiles`: reads/updates, onboarding, consent, account status, XP stats;
- `quests`: catalog/admin CRUD/bulk creation, picker, assignment, active/history,
  expiry, rerolls, QOTD, following-active users, targeted injections;
- `submissions`: proof creation, visibility, moderation, appeal, XP transitions;
- `feed`: global/following feed, hot ordering, detail, saves, visibility/blocks;
- `social`: reactions, comments/replies/mentions, follows, blocks, reports;
- `collab`: create/join/status/abandon and vote lifecycle;
- `leaderboard`: global/following ranking and stats;
- `notifications`: inbox/read state, encrypted device tokens, announcements,
  Firebase v1 fanout workers;
- `media`: R2-compatible upload intents, validation, signed URL lifecycle;
- `admin`: roles, moderation, users, quests, config, announcements, reports,
  public-intake operations and audit-sensitive actions;
- `account`: queued deletion and private export jobs;
- `public-intake`: public config, waitlist and quest suggestions;
- `search`, `health`, and a full `integrations/telegram` port.

Platform foundations already present:

- global DTO validation, `/api/v1`, response envelope and exception filter;
- JWT authentication separate from RBAC authorization;
- environment validation, server-only secrets and encrypted sensitive tokens;
- Pino structured logging/request IDs, health checks, graceful shutdown;
- throttling, PostgreSQL pooling/statement timeout;
- Redis/BullMQ queues, transactional outbox and processed-message idempotency;
- authenticated Socket.IO `/realtime` with user/post rooms and Redis fanout;
- Swagger/OpenAPI, Docker API/worker/migration separation, Nginx proxy.

API and worker use `src/main.ts` and `src/main.worker.ts` and can scale
independently. Do not split microservices without measured justification.

## New database

Forward-only SQL lives in `backend/migrations/`:

```text
0001_initial_domain_schema.sql
0002_search_and_ranking_indexes.sql
0003_media_object_lifecycle.sql
0004_collaboration_contract_alignment.sql
0005_admin_surface_alignment.sql
0006_public_intake_contract.sql
0007_visibility_contract_alignment.sql
0008_admin_role_contract_alignment.sql
0009_notification_delivery_tracking.sql
0010_profile_contract_alignment.sql
0011_auth_action_tokens.sql
0012_quest_delete_parity.sql
0013_telegram_integration.sql
```

`backend/scripts/migrate.mjs` records checksums and rejects modified applied
migrations. Never edit an applied migration. Add a backward-compatible forward
migration and integration tests. Keep uniqueness/legal-state constraints in
PostgreSQL. Preserve transactions/locking for assignments, moderation/appeals,
XP, reactions, follows, quest deletion and outbox writes.

Local developer state currently uses:

- PostgreSQL `127.0.0.1:54329`, container `newbsheel-postgres-1`;
- Redis `127.0.0.1:63799`, container `newbsheel-redis-1`;
- test DBs `bsheel_clean_20260906`, `bsheel_replay_20260907_a`,
  `bsheel_replay_20260907_b`.

These are machine-local, not portable config. Use a fresh disposable DB for a
migration replay and never point tests at production.

## Flutter repository and composition layer

`packages/app_repositories` is the strangler boundary. Existing interfaces and
models remain stable where practical; `Api*Repository` maps the Nest envelope
into legacy Dart models.

Core pieces:

- `api/api_client.dart`: JSON transport, envelope parsing, timeout,
  authenticated calls and serialized refresh;
- `api/secure_api_token_store.dart`: atomic secure access/refresh storage;
- `api/nest_repository_bundle.dart`: one shared client/adapters per app;
- `auth/api_auth_repository.dart`: Nest auth/session mapping;
- `realtime/api_realtime_client.dart`: authenticated Socket.IO, websocket-only,
  bounded reconnect/backoff, one auth refresh retry, typed events/post rooms;
- `public_config/api_public_config_repository.dart`: pre-auth config,
  scalar normalization, non-overlapping five-second polling/deduplication;
- media signer/uploader for private object access.

The Dart Socket.IO dependency is `socket_io_client ^3.1.6` against server 4.x.
Flutter uses websocket transport. Always call `dispose()` to release resources.

Composition roots:

- mobile: `apps/mobile_app/lib/core/backend/{backend_config,mobile_nest_backend,mobile_nest_overrides}.dart`;
- admin: `apps/admin_web/lib/core/backend/{backend_config,admin_nest_backend,admin_nest_overrides}.dart`.

Each app creates one bundle only in Nest mode. `bootstrap.dart` initializes the
selected backend and `main.dart` applies centralized Riverpod overrides. Do
not construct raw API clients/token stores in screens.

## Flutter work completed

Shared Nest adapters exist for auth, profile, quests, submissions, feed,
comments, follows, reactions, saved posts/quests, notifications, leaderboard,
search, collab, moderation, admin, account, public config, media and realtime.
Existence does not mean every UI caller is injected yet.

Mobile paths already migrated behind the mode boundary include:

- auth session/auth-state/current profile and provider authentication checks;
- bootstrap, device registration, sign out and app resume;
- account status, consent, terms and queued deletion;
- maintenance/app config polling;
- centralized repository overrides for major domains;
- feed/notification/profile/post/submission realtime invalidation;
- submission appeal and visibility;
- blocked-user list, block/unblock and reporting;
- QOTD, following-active users and authoritative reroll tracking;
- onboarding, submit-proof and profile current-user reads;
- mention suggestions through Nest follow/search adapters;
- Nest comment creation without duplicate client notification fanout.

Important: the Nest social transaction creates comment-thread and mention
notifications server-side. Flutter must not also execute the legacy client
notification helpers in Nest mode.

Admin already has backend-aware bootstrap, composition, session refresh,
router/login, role/config support and a broad `ApiAdminRepository`. Most admin
feature pages/providers still query Supabase directly and are the largest
remaining client cutover block.

## Last verified checkpoint

Before the newest mention/comment/report/block edits, the following passed:

- backend build and lint;
- backend suite: 9 files, 40 tests;
- full backend smoke and clean-database Telegram smoke;
- shared repository strict analysis and 22 tests;
- mobile analysis with zero issues and 33 passing tests, plus one screenshot
  suite skipped because Supabase compile-time values were absent;
- admin analysis with zero issues and 1 passing test;
- mobile and admin Nest-mode Flutter web builds.

Do not repeat those as current without rerunning checks after new edits.

Known web-build warnings are upstream wasm dry-run warnings from
`socket_io_common`; mobile also has an existing Mixpanel wasm warning. JS web
artifacts still build. Investigate any different/new error.

Flutter SDK on this machine:

```text
/Users/razanhasbini/Downloads/flutter/bin/flutter
/Users/razanhasbini/Downloads/flutter/bin/dart
Flutter 3.44.4 / Dart 3.12.2
```

The SDK cache may require sandbox permission. Format exact edited Dart files,
never the whole copied app.

## Verification commands

```bash
cd backend
npm run build
npm run lint
npm test
npm run test:e2e
npm run db:migrate:check
```

```bash
docker compose up --build
# proxy API: http://localhost:8080/api/v1
# Swagger: http://localhost:8080/docs
```

Inspect smoke scripts and use a disposable database:

```bash
cd backend
npm run test:smoke
npm run test:auth-confirmation
npm run test:realtime
npm run test:telegram
```

For each Dart package/app:

```bash
/Users/razanhasbini/Downloads/flutter/bin/dart format <only-edited-files>
/Users/razanhasbini/Downloads/flutter/bin/flutter analyze
/Users/razanhasbini/Downloads/flutter/bin/flutter test
```

Nest-mode web build:

```bash
/Users/razanhasbini/Downloads/flutter/bin/flutter build web \
  --dart-define=BACKEND_MODE=nest \
  --dart-define=NEST_API_URL=https://api.example.test/api/v1
```

Snapshot guard:

```bash
cd "/Users/razanhasbini/Desktop/bsheel2/new bsheel"
./scripts/verify-legacy-snapshot.sh
```

## Evidence rules

`IMPLEMENTED` means code exists. `VERIFIED` requires:

1. database/API integration evidence for output and side effects;
2. Flutter wire fixture for path, request, envelope and model mapping;
3. relevant UI/provider journey running in Nest mode;
4. parity for errors, permissions, idempotency and side effects.

Flutter fixtures live mainly in
`packages/app_repositories/test/api_repository_contract_test.dart`, with auth,
transport, config and realtime tests beside it. Assert exact paths, queries,
bodies, scalar types, nested model mapping and validation failures.

## Workflow for each remaining slice

1. Identify the journey and every caller/provider.
2. Read all legacy SQL definitions chronologically, canonical SQL, edge
   functions, repositories, models, constants, UI/error branches and tests.
3. Record input/output, ordering, pagination, authorization, transactions,
   side effects, idempotency and failures.
4. Confirm DB constraints/indexes; add a forward migration if required.
5. Implement/repair DTO, thin controller, service and repository. Queue slow work.
6. Add integration evidence, including retry/duplicate and unauthorized cases.
7. Add/extend `Api*Repository` and map to existing Flutter models.
8. Add a Dart wire-contract test.
9. Inject centrally or use one explicit mode branch at a necessary boundary.
10. Preserve the complete legacy branch.
11. Add the exact tracked file path to the allowlist.
12. Format only edited files; analyze/test; run snapshot guard.
13. Update `PARITY_LEDGER.md` honestly.

Prefer repository interfaces over raw HTTP in UI. Do not create another
service locator.

## Priority remaining work

### 1. Verify the current mobile comment batch

Format/analyze/test `mention_controller.dart`,
`feed_post_details_page.dart`, and `comments_sheet.dart`. Confirm Nest comments
never access Supabase notification fanout and legacy behavior remains. Run the
snapshot verifier.

### 2. Audit remaining mobile Supabase reachability

```bash
rg -n "Supabase\\.instance|supabaseClientProvider|\\.rpc\\(|\\.from\\(|\\.channel\\(" \
  apps/mobile_app/lib -g '*.dart'
```

Results include safe legacy branches/provider factories, so inspect control
flow rather than deleting matches. Known areas requiring review:

- `shared/navigation/bottom_nav_shell.dart` broad legacy realtime channel;
- `reset_password_page.dart` recovery/deep-link flow (needs the real Nest
  one-time action-token journey, not a shortcut);
- `social_sign_in_buttons.dart` post-login singleton reads;
- residual mobile admin/debug behavior;
- comment/reels widgets doing raw work after repository commands.

### 3. Cut over admin Flutter feature pages

Audit all direct Supabase calls under `apps/admin_web/lib/features` and convert
them to `ApiAdminRepository`/domain adapters without losing filters, counts,
dialogs, notes, pagination, copy, permissions or refresh behavior. High-risk
flows: review/history/appeals; users/status/roles/XP; quest CRUD/import/injection/
QOTD; announcements/templates; reports/feed management; waitlist/suggestions;
app config/dashboard counts. Add missing adapter methods and fixtures first.

### 4. Strengthen contract/live integration evidence

Every ledger row still IMPLEMENTED needs its missing DB integration and Flutter
fixture. Prioritize auth confirmation/recovery/OAuth, profile media, picker
injections, active/history/expiry, rerolls/QOTD, submissions, comments/mentions,
blocks/reports, saved posts, search, leaderboard, collab, notifications/admin.

Real staging fixtures remain for Firebase, R2, email, Google/Apple and Telegram.
Never put provider secrets in Flutter, fixtures, logs, docs or Git.

### 5. Build/rehearse production data migration

The target schema exists, but production cutover still needs a repeatable,
restartable, idempotent source-to-target migration that preserves IDs,
timestamps, statuses, deletions, XP and media keys. Explicitly handle auth
identity/password limitations. Reconcile table counts, sums, null distributions
and deterministic checksums on a production-shaped sanitized snapshot. Re-run
the import to prove idempotency and document rollback.

Then shadow-read/differential-test feeds, profiles, quests, leaderboards,
notifications and admin counts.

### 6. Operational completion

Production still needs real IaC/secret management, backup restore testing,
observability export/dashboards/alerts, CDN/R2 policies, autoscaling,
deployment health gates, canary/blue-green automation and separate environments.
Read replicas, sharding and multi-region are measured future decisions.

### 7. Final cutover

Only after required journeys are VERIFIED: canary Nest builds with monitoring
and rollback, observe metrics/business transitions, then switch default. Keep a
rollback window. Remove Supabase runtime/dependencies only in a dedicated
reviewed cleanup after acceptance.

## High-risk invariants

- One active/pending quest and timing rules remain server-enforced.
- Rerolls are five per rolling 24 hours and server-authoritative in Nest mode.
- Appeals are one-time and forbidden for deleted submissions.
- Approval awards XP once; reversal/deletion revokes correctly; retries cannot
  duplicate XP or notifications.
- Follow/reaction/save uniqueness/idempotency is DB-enforced.
- Blocks affect relationships and feed visibility exactly as legacy.
- Comment mention/reply recipients exclude self/duplicates correctly.
- Device tokens are encrypted at rest and invalid tokens cleaned up.
- Media bytes never enter PostgreSQL; private media uses signed URLs.
- Admin authentication and authorization remain separate; sensitive actions
  are auditable.
- State change and outbox insert share a transaction; consumers are idempotent.
- Lists are bounded/paginated and hot queries have indexes.
- External calls have timeouts/bounded backoff; API replicas stay stateless.

## Prohibited shortcuts

- Do not rewrite Flutter or redesign product behavior.
- Do not add premature microservices.
- Do not leave critical notification/XP logic only in Flutter.
- Do not call Supabase from a Nest-mode reachable path.
- Do not create raw HTTP clients in screens.
- Do not store tokens in plain preferences or expose server secrets.
- Do not store media in PostgreSQL or do heavy work in HTTP handlers.
- Do not edit applied migrations or mark parity VERIFIED without evidence.
- Do not remove legacy references/change default backend prematurely.
- Do not broadly format copied trees or mass-allowlist drift.
- Do not use destructive Git/filesystem commands; there is no Git safety net.

## Definition of done

The migration is complete only when:

- every parity-ledger row is VERIFIED with evidence;
- no Supabase runtime call is reachable from mobile/admin in Nest mode;
- all user/admin journeys pass against a clean Nest stack;
- confirmation, recovery, Google/Apple and external-provider staging tests pass;
- realtime works through the proxy across multiple replicas;
- migrations replay from zero and upgrade the previous release;
- data migration is repeatable and reconciliation passes;
- unit/integration/E2E/contract/Flutter/load tests pass in CI;
- security/RBAC/audit/sensitive-data handling is reviewed;
- backup restoration and DR are actually tested;
- dashboards/alerts/graceful shutdown/canary rollback are proven;
- accessibility/offline/error/retry/responsive behavior has not regressed;
- product owner accepts differential results and monitored canary;
- Supabase is disabled only after an observation/rollback window.

Until then, state exactly what is implemented and verified. Never call the app
“fully migrated” based on code volume.

## Immediate continuation point

At creation, the active batch changed:

- `apps/mobile_app/lib/features/comments/application/mention_controller.dart`
- `apps/mobile_app/lib/features/feed/presentation/pages/feed_post_details_page.dart`
- `apps/mobile_app/lib/features/feed/presentation/widgets/comments_sheet.dart`
- `scripts/legacy-migration-allowlist.txt`

Mention suggestions now use Nest follow/search adapters in Nest mode. Comment
surfaces skip legacy notification resolution in Nest mode. Post-detail reporting
and blocking call the Nest account adapter in Nest mode. Legacy paths remain.

This batch and the immediately following realtime/OAuth/recovery batch were
formatted and verified: mobile analysis reported zero issues and all 33 normal
tests passed; shared repositories reported zero issues and 22 tests passed;
backend build/lint and all 40 tests passed; the screenshot suite was
intentionally skipped without Supabase compile-time values; and the legacy
byte-snapshot guard passed. The shell now consumes typed Nest domain events,
quests emit durable assignment/expiry events, social OAuth avoids Nest-mode
Supabase access, and `/reset-password?token=...` consumes the Nest action token.
Next, finish other mobile callers and begin the admin feature-page cutover.
