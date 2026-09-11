# Bsheel

A gamified quest app. Users get 3 random real-world challenges, pick one,
complete it inside a per-quest timer, submit photo or video proof, and earn XP
once a moderator approves it. Around that sits a social layer: feed, votes,
comments, follows, blocks, collab groups and leaderboards.

Flutter clients, a self-hosted NestJS API, PostgreSQL, Redis and S3-compatible
object storage.

## Quick start

```bash
# Whole backend stack: Postgres, Redis, migrations, API, worker, proxy
docker compose up --build
# API:     http://localhost:8080/api/v1
# OpenAPI: http://localhost:8080/docs
```

```bash
# Flutter monorepo
./scripts/bootstrap.sh          # installs melos, pub get everywhere
cd apps/mobile_app   && flutter run
cd apps/admin_web    && flutter run -d chrome
cd apps/business_web && flutter run -d chrome
```

Debug builds default to `http://127.0.0.1:3010/api/v1`, so a local backend
needs no extra flags.

## Features

- **Quest system** — quests across 5 categories (fitness, creativity, social,
  learning, adventure). Users pick from 3 options and complete within a timer
  the admin sets per quest.
- **XP and leveling** — XP per approved quest, with class progression
  (Scout → Warrior → Mage → Champion → Legend).
- **Social feed** — completed quests with up/downvotes and hot-score ordering.
- **Comments, mentions and follows** — threaded replies, @mentions, a follow
  graph, blocks and reporting.
- **Collab groups** — join by code, complete together or head-to-head, with
  public voting.
- **Leaderboards** — global and following-only, by XP.
- **Push notifications** — Firebase Cloud Messaging, fanned out by a durable
  queue rather than from the client.
- **Admin dashboard** — moderation queue with reviewer context, appeals, users,
  quests, injections, Quest of the Day, announcements, reports, waitlist and an
  XP reconciliation audit.
- **Quest of the Day** — a scheduled featured quest with a bonus.
- **Localization** — English and Lebanese Arabizi.
- **Onboarding, badges and level-up celebration.**

## Stack

| Layer | Technology |
|---|---|
| Mobile | Flutter (iOS, Android) |
| Admin dashboard | Flutter web |
| API | NestJS 11 modular monolith, Node 24 |
| Database | PostgreSQL 17 |
| Queues, locks, cache | Redis 7.4 + BullMQ |
| Object storage | S3-compatible (Cloudflare R2 in production) |
| Realtime | Socket.IO with Redis pub/sub fanout |
| Push | Firebase Cloud Messaging v1 |
| Client state | Riverpod |
| Client routing | GoRouter |

## Repository layout

```text
apps/
  mobile_app/            user-facing Flutter app
  admin_web/             admin dashboard (Flutter web)
  business_web/          partner dashboard (Flutter web), served at
                         admin.bsheel.app/business
packages/
  app_core/              design tokens, logger, utils
  app_models/            shared data models
  app_repositories/      repository contracts + HTTP implementations
  shared_ui/             reusable widgets
  app_contracts/         domain value constants + API field names
backend/
  src/modules/           one folder per domain
  src/integrations/      telegram
  migrations/            forward-only, checksummed SQL
  test/                  unit + integration suites
  PERFORMANCE.md         index and scalability audit
infra/nginx/             reverse proxy config
docs/                    architecture, deployment, security, API
scripts/                 bootstrap, analyze/test, iOS release
```

## Architecture in one picture

```text
Flutter mobile        Flutter admin
        \                  /
         HTTPS /api/v1 + WebSocket /realtime
                  |
             nginx proxy
                  |
        stateless NestJS API replicas ── BullMQ worker
          |            |          |
     PostgreSQL      Redis     R2 / S3
```

Each domain is layered presentation → application → domain → infrastructure.
Controllers only validate and translate HTTP; repositories own parameterised
SQL and transactions. Slow or cross-domain effects are written to a
transactional outbox in the same transaction as the state change, then consumed
by idempotent workers.

See [`docs/architecture.md`](docs/architecture.md).

## Database

| Table | Purpose |
|---|---|
| users | credentials, account status, token version |
| profiles | username, display name, avatar, XP, level, consent |
| auth_identities | password and OAuth identities |
| quests | quest bank |
| user_quests | assignments, status, timers |
| submissions | proof, review state, appeal state, visibility |
| reactions | post votes |
| comments | threaded comments and mentions |
| follows / blocked_users | social graph |
| collab_groups / _members / _votes | collab lifecycle |
| notifications | in-app inbox |
| admins / admin_audit_log | roles and an immutable audit trail |
| outbox_events / processed_messages | durable events and consumer idempotency |
| app_config / feature_flags | runtime configuration |
| quest_of_the_day, quest_suggestions, waitlist | content and intake |

Schema lives in `backend/migrations/`, forward-only and checksummed. Never edit
an applied migration — add the next number.

## Submission review flow

> Keep this section and the matching one in `CLAUDE.md` in sync.

### Statuses

| Entity | Status | Meaning |
|---|---|---|
| `user_quests` | `assigned` | active, timer running |
| `user_quests` | `submitted` | proof submitted, awaiting review |
| `user_quests` | `approved` | approved, XP awarded |
| `user_quests` | `rejected` | rejected |
| `user_quests` | `expired` | timer ran out |
| `submissions` | `pending` | awaiting a moderator |
| `submissions` | `approved` / `rejected` | decided |
| `submissions` | `appealed` (bool) | the user's one appeal is spent |

### State machine

```text
User submits proof
  user_quest.status = submitted
  submission.status = pending, appealed = false
        |
   moderator reviews
        |
   +----+----------------------------+
   |                                 |
APPROVED                          REJECTED
XP awarded once                   notification sent
                                     |
                              user may appeal ONCE
                                     |
                          status back to pending,
                          appealed = true,
                          review fields cleared,
                          admins notified
                                     |
                          +----------+-----------+
                          |                      |
                      APPROVED             RE-REJECTED
                                           final, no more appeals
```

Appeal guards are server-side: ownership, `status == 'rejected'`,
`appealed == false`, and not soft-deleted.

### Where it surfaces

Only the home hero zone is status-driven:

| Condition | What renders |
|---|---|
| account suspended/banned | locked card; QOTD ticket hidden |
| any `user_quest.status == submitted` | pending-review card, above whatever follows — the hero below it still renders, so a waiting user can roll again |
| active quest, `assigned`, before `expires_at` | active-quest hero with live countdown |
| active quest past `expires_at` | "TIME OVER" card |
| no active quest | slot machine / GENERATE A QUEST |

The rejection and appeal UI lives on the submission status page, reachable from
four places: the APPEAL button on a rejected row in quest history, a
notification tap, the QOTD ticket stub after a first-time rejection, and the
redirect straight after submitting. The last three are transient; history is
the durable one, so it is the route to protect.

## Verification

```bash
cd backend
npm run lint
npm test                  # unit
npm run db:migrate        # replays from an empty database
npm run db:migrate:check  # checksum ledger
npm run test:e2e          # integration; needs Postgres + Redis
npm run build
```

```bash
melos run analyze         # all 7 packages
melos run test
dart format --set-exit-if-changed .
```

CI runs the backend job (with Postgres and Redis service containers, migration
replay and the integration suite) plus analyze, test and a format check for the
Flutter side.

## Build and release

### App identifiers

| Platform | Field | Value |
|---|---|---|
| iOS | Bundle ID | `com.questapp.mobileApp` |
| iOS | Team ID | `JMDKX9TYX6` |
| iOS | Display name | `BSHEEL` |
| Android | Package | `com.questapp.mobile_app` |
| Both | Version | `apps/mobile_app/pubspec.yaml` — bump the `+build` on every store upload |

### Build-time values

`apps/mobile_app/dart_defines.release.json` is the single source of truth.
Release builds must pass `--dart-define-from-file=dart_defines.release.json`;
`scripts/ios_release.sh` refuses to run without it.

```bash
# iOS (App Store / TestFlight)
cd apps/mobile_app && flutter build ipa \
  --obfuscate --split-debug-info=build/app/outputs/app-symbols/release \
  --dart-define-from-file=dart_defines.release.json

# Android App Bundle
cd apps/mobile_app && flutter build appbundle --release \
  --obfuscate --split-debug-info=build/app/outputs/app-symbols/release \
  --dart-define-from-file=dart_defines.release.json

# Admin web
cd apps/admin_web && flutter build web \
  --dart-define=API_URL=https://api.bsheel.app/api/v1

# Business dashboard — served under the admin origin, so --base-href is
# required; without it every asset resolves against `/` and the page is
# blank with no error worth reading.
cd apps/business_web && flutter build web \
  --base-href=/business/ \
  --dart-define=API_URL=https://api.bsheel.app/api/v1
```

`--obfuscate` is required for anything shipped. Keep the symbol map for crash
deobfuscation; never ship it.

See [`docs/PUBLISHING.md`](docs/PUBLISHING.md) for the release runbook and
[`docs/DEPLOYMENT.md`](docs/DEPLOYMENT.md) for the backend.

### Android signing

| Field | Value |
|---|---|
| Keystore | `apps/mobile_app/android/app/bitsheel-release.jks` (not in git) |
| Alias | `bitsheel` |
| Config | `apps/mobile_app/android/key.properties` (not in git) |
| SHA-256 | `BF:50:D4:7F:4E:D3:1D:83:1A:B0:31:E5:79:89:4D:04:B0:3B:6A:34:C2:CB:32:0A:71:76:2C:7F:32:BC:C5:A2` |

## Security notes

Client tokens compiled into the binary (`API_URL`, Mixpanel token, Google
OAuth client IDs) are public by design. The security boundary is the API:
authentication, RBAC guards, signed media URLs and server-only secrets.

This codebase descends from a repository whose history contains two live
credentials — a `service_role` JWT and an App Store Connect key. They are not
in this repository's history but remain valid against the legacy system until
rotated. See [`docs/security/SECRET_ROTATION_RUNBOOK.md`](docs/security/SECRET_ROTATION_RUNBOOK.md).
