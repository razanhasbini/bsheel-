# CLAUDE.md — Bsheel

## What this app is

Bsheel is a gamified quest app. Users get 3 random real-world challenges, pick
one, complete it inside a per-quest timer set by an admin, submit photo/video
proof, and earn XP. A moderator approves or rejects. Around that sits a social
layer: feed with up/downvotes, comments with replies and mentions, follows,
blocks, saved posts, collab groups with public voting, and leaderboards.

English + Lebanese Arabizi. iOS-first, with an Android build and a Flutter-web
admin dashboard.

## Architecture

One backend, one client stack. No Supabase.

```text
apps/mobile_app  (Flutter, iOS + Android)
apps/admin_web   (Flutter web dashboard)
        |
        |  HTTPS  /api/v1
        |  WebSocket /realtime
        v
backend/         NestJS 11 modular monolith
        |
   +----+-----------+-----------+
   |                |           |
PostgreSQL 17    Redis 7.4   R2 / S3
(authoritative)  (queues,    (private media,
                  locks)      signed URLs)
```

The backend is a modular monolith with one API process (`src/main.ts`) and one
independently scalable worker process (`src/main.worker.ts`) from the same
codebase. Do not split it into microservices without a measured reason.

Per domain the layering is strict:

```text
presentation/  controller + validated DTO   (HTTP only, thin)
application/   service                      (orchestration)
domain/        types and rules
infrastructure/repository                   (parameterised SQL, transactions)
```

Cross-domain side effects go through the transactional outbox
(`outbox_events`) and are consumed by idempotent BullMQ workers — never
inline in an HTTP handler.

## Repository layout

```text
apps/
  mobile_app/          user-facing app
  admin_web/           admin dashboard
packages/
  app_core/            design tokens (QuestColors/Spacing/Typography), logger, utils
  app_models/          shared data models
  app_repositories/    repository contracts + their HTTP implementations
  shared_ui/           reusable widgets
  app_contracts/       domain value constants + API field names
backend/
  src/modules/         auth, profiles, quests, submissions, feed, social,
                       collab, notifications, media, admin, account,
                       public-intake, search, leaderboard, health
  src/integrations/    telegram
  migrations/          forward-only, checksummed SQL
  test/                unit (*.spec.ts) + integration (*.e2e-spec.ts)
infra/nginx/           reverse proxy config
docs/                  architecture, security, deployment, API
```

## Client rules

- **One backend, resolved once.** `AppBackend` (in each app's
  `lib/core/backend/`) owns the single `ApiRepositoryBundle` — one HTTP client
  and one rotating secure token store per app. Repository providers return
  instances from that bundle. Never construct an `ApiClient`, a token store,
  or a repository inside a screen.
- **Configuration** is `BackendConfig` — `API_URL` supplied at build time,
  validated at startup. Debug builds fall back to `http://127.0.0.1:3010/api/v1`;
  release builds have no fallback and require HTTPS.
- **Features depend on the contract, not the implementation.** Import the
  abstract repository from `app_repositories`; the concrete `Api*Repository` is
  wired only in the composition root.
- **Never hardcode domain strings.** Statuses, categories, difficulties and
  roles come from `packages/app_contracts/lib/statuses.dart`.
- **Models live in** `packages/app_models/lib/`.
- **Use `withAlpha()`, not `withOpacity()`** — the latter is deprecated.
- **Never hardcode colours.** Mobile: everything comes from `QuestColors`
  (+ `QuestSpacing`, `QuestTypography`) in `packages/app_core/lib/theme/` — the
  single source of truth; reskin by editing those three files only. Admin web:
  `BsheelColors`/`BsheelType`/`BsheelRadii` from
  `apps/admin_web/lib/core/theme/bsheel_design.dart`. A genuinely one-off
  decorative colour is allowed only as a private `static const` in its own file
  with a `// Screen-specific colour — not a theme token.` comment.
- **Theme:** Light Arcade Pop only (`QuestTheme.light`, wired in `app.dart`).
  Cream background (#FFF9EE), ink outlines and chunky drop shadows (#1A1330),
  accents violet (#6B3BFF), coral (#FF5A6E), gold (#FFC224), green (#17C27B),
  sky (#4CC9F0). The app forces `ThemeMode.light`; there is no dark theme. The
  dark-looking `QuestColors.dark*` / `textPrimary` tokens are "ink panel"
  colours used *inside* the light design — not a dark mode.
- **Prefer the context helpers** `QuestColors.bg/cardBg/text/textDim(context)`
  in widgets, so a future multi-theme setup needs no call-site changes.
- **ALL CAPS** for labels and headers, normal case for body text.
- `dart format` owns formatting. The `require_trailing_commas` lint is
  deliberately disabled because it contradicts the formatter — see
  `analysis_options.yaml`.

## Backend rules

- **PostgreSQL is authoritative** and its constraints are the final guard for
  uniqueness and legal values. Keep them there; do not move a uniqueness rule
  into application code.
- **Critical state transitions lock their aggregate and run in one
  transaction** — quest assignment, moderation and appeals, XP, reactions,
  follows, quest deletion.
- **A transaction that changes state and emits an event inserts both the row
  and its `outbox_events` row atomically.** Consumers are idempotent via
  `processed_messages`.
- **Migrations are forward-only, checksummed and immutable once applied.**
  `backend/scripts/migrate.mjs` rejects a modified applied migration. To fix
  something, add the next numbered migration. Wrap DDL in `BEGIN; … COMMIT;`
  (except `CREATE INDEX CONCURRENTLY`, which cannot run in a transaction).
- **SQL is parameterised.** Interpolate only from a closed set the DTO has
  already validated, and say so in a comment where you do.
- **Media bytes never enter PostgreSQL.** Private objects are served through
  short-lived signed URLs; thumbnails and variants are jobs.
- **Authentication establishes identity; guards authorise the action.** They
  are separate concerns. Sensitive admin actions append an immutable audit
  record.
- **Lists are bounded and paginated**, and hot queries have indexes. See
  `backend/PERFORMANCE.md`.

## Submission review flow

> Keep this section and the matching one in `README.md` in sync.

### State machine

```text
SUBMITTED → PENDING REVIEW
  ├── APPROVED → XP awarded (once)
  └── REJECTED → user may appeal exactly once
        ├── APPROVED on re-review
        └── RE-REJECTED → final, no further appeals
```

Server-enforced guards on appeal: caller owns the submission, status is
`rejected`, `appealed` is false, and the submission is not soft-deleted.
Their error codes are `NOT_SUBMISSION_OWNER`, `SUBMISSION_NOT_REJECTED`,
`ALREADY_APPEALED` and `DELETED_SUBMISSION`.

### Where it surfaces

**Home** renders, in order: name + bell → headline → two all-time stat tiles →
Quest-of-the-Day ticket → hero zone → RECENT QUESTS → weekly XP meter → friend
activity → streak card. Only the hero zone is status-driven:

| Condition | Widget |
|---|---|
| account suspended/banned | `_LockedCard` (QOTD ticket hidden entirely) |
| any `user_quest.status == submitted` | `_PendingReviewCard`, above whatever follows — and the hero below it still renders, so a waiting user can roll again |
| active quest, `assigned`, before `expires_at` | `_ActiveQuestHero` with live countdown |
| active quest past `expires_at` | `_TimeOverCard` |
| no active quest | `_SlotMachineZone` (GENERATE A QUEST) |

There are **no** IN REVIEW / REJECTED / ACCEPTED QUESTS / COMPLETED TODAY /
EXPIRED sections — the Arcade Pop rebuild removed them, along with the
`rejectedQuests` / `reRejectedQuests` / `appealedQuests` / `submittedQuests`
filter variables. Don't go looking for them.

**RECENT QUESTS** lists the 5 most recent quests with a status badge, display
only. SEE MORE opens `quest_history_page.dart` (grouped COMPLETED / REJECTED /
EXPIRED / IN REVIEW), whose rows open the **quest detail** page.

### Reaching the appeal flow

`submission_status_page.dart` owns the whole rejection/appeal UX. Four things
route to it:

1. The APPEAL button on a rejected row in `quest_history_page.dart` — the
   **durable** route, and the one to protect. It is server-gated on
   `appealAvailable`, so the button is a promise the API will keep.
2. Tapping a notification (`submission_approved`, `submission_rejected`,
   `new_submission`, `appeal_submitted`).
3. The Quest-of-the-Day ticket stub, when that attempt was a first-time
   rejection (`home_extras.dart` — `canAppeal`).
4. Immediately after submitting proof (`submit_proof_page.dart`).

Routes 2-4 are all transient: a notification can be missed, and the stub and
the redirect are gone once the screen changes. History is the one place a
rejected user can go back and find. So **breaking push delivery no longer
hides the appeal flow** — an earlier version of this file said it did, which
is no longer true. Removing the APPEAL button from history would.

### Files to change together

- `submission_status_page.dart` — detail view, appeal button, re-rejection copy
- `home_page.dart` — hero zone + RECENT QUESTS
- `quest_history_page.dart` — history grouping
- `notifications_page.dart` — the routing that makes the appeal reachable
- `backend/src/modules/submissions/` — the server-side state machine
- `statuses.dart` — status constants
- **this file + README.md**

## AI proof verification (#47)

A cascade, not a single call. Provenance before content, cheap models
before expensive ones, and one place that decides what the agent may
conclude.

| Stage | What runs | When |
|---|---|---|
| 0 forensics | EXIF window, exact-byte dup, dHash near-dup, screen dimensions, generated-content markers | every submission, no model, ~free |
| 1 triage | cheapest model, `detail: low` | only if the quest's contract says content can decide |
| 2 deep | better model, `detail: high` | only where triage could not tell |
| 3 reject_review | most capable model | **required before any rejection** |

The rungs differ ~50x in price, so the cascade is the dominant cost
decision. The asymmetry is deliberate: the cheapest model may clear a
clean submission, but only the most capable one may conclude that proof
is fake. `decide()` refuses to reject on a triage or deep verdict
however confident it is.

**Not every quest can be judged from a photograph**, and this is the
thing to understand before changing anything here. "Spend an hour with
no phone" cannot be verified — the phone took the photograph. Roughly a
third of the catalogue is like that. So a quest carries a *verification
contract* (`quest_verification_defaults` + nullable overrides on
`quests`, resolved by the `quest_verification_contract` view):

- `content` — the image can show the task; content decides.
- `provenance_only` — it cannot; judge authenticity, never fail for
  lacking proof a photograph cannot carry.
- `none` — nothing about the image bears on the task; trust unless
  provenance actively contradicts.

For `provenance_only` and `none`, **no vision call is made at all**.

**Shadow mode is the default** (`AI_VERIFICATION_SHADOW_MODE=true`): the
agent decides and acts on nothing, and `acted = false` marks those rows
as the honest eval slice. `npm run proof:eval` scores them against the
human decisions that followed. `may_auto_reject` is seeded false for
every category — authority is earned from a precision number, not
asserted in a migration.

When it does act, it calls the *same* `approve`/`reject` a moderator's
click uses with a null actor, so the XP-awarded-once invariant, the
notification, the audit row and the collab fan-out cannot drift between
a human decision and an automated one.

Escalations surface at `/moderation/unclear` with a sidebar badge, and
deciding there clears the escalation in the same transaction.

Two traps worth knowing. EXIF `DateTimeOriginal` is local wall-clock
with **no timezone**, so the capture-window check is widened by the
maximum UTC offset unless EXIF carries one — without that it accuses
honest players in other timezones. And `etag` is not a usable content
hash: it is a hash of part hashes for multipart uploads, which is why
`media_objects.content_md5` exists.

Location works the other way round from how it first shipped. A
destination quest is started like any other; the assignment agent then
opens a CAMARA geofence for the quest window (`geofencing_subscriptions`)
and the agent weighs `network_evidence` + geofence events when the proof
comes in. There is **no** pre-assignment location gate — migration 0035
removed it, and `map_location_evidence` is a legacy cache nothing writes.

The map is the game board: every published place is a pin; a `hidden`
place is a *locked* pin (name withheld, position blurred to ~1 km) until
the player has an **approved** quest at any place within 10 km, after
which it and its quests open. One rule, `map-visibility.sql.ts`, decides
both what the map shows and what `assertDestinationAccess` lets a player
start, so a visible pin can never offer a quest the API refuses. Device
GPS moves the player's avatar on the map and nothing else — it is never
evidence.

## High-risk invariants

These are covered by integration tests in `backend/test/`. If you change one,
change its test deliberately — never to make a failure go away.

- One **active** (`assigned`) quest per user, database-enforced by
  `user_quests_one_assigned_idx`. Submissions awaiting review do **not**
  block a new roll — migration 0021 narrowed the old
  `assigned`-or-`submitted` index deliberately, because review latency is
  not something a user can clear and it left them with nothing to do. The
  five-rerolls-per-24h cap is now the real limit on quest intake. Timing
  rules stay server-enforced.
- Rerolls are five per rolling 24 hours, server-authoritative.
- Appeals are one-time and forbidden on a deleted submission.
- Approval awards XP once; reversal and deletion revoke it correctly; retries
  cannot duplicate XP or notifications.
- Follow, reaction and save uniqueness is database-enforced and idempotent.
- Blocks affect relationships and feed visibility in both directions.
- Comment mention/reply recipients exclude self and duplicates.
- Device tokens are encrypted at rest and invalid tokens are cleaned up.
- State change and outbox insert share one transaction.

## Running it

```bash
# Backend + Postgres + Redis + worker + proxy (local, dev secrets)
docker compose up --build
# API:      http://localhost:8080/api/v1
# OpenAPI:  http://localhost:8080/docs

# Backend directly
cd backend
npm ci
npm run db:migrate
npm run start:dev        # API
npm run start:worker     # worker

# Flutter monorepo
./scripts/bootstrap.sh   # melos + pub get everywhere
melos run analyze
melos run test

cd apps/mobile_app && flutter run --dart-define=API_URL=http://127.0.0.1:3010/api/v1
cd apps/admin_web  && flutter run -d chrome --dart-define=API_URL=http://127.0.0.1:3010/api/v1
```

Debug builds default to `http://127.0.0.1:3010/api/v1`, so a plain
`flutter run` works with a local backend and no flags.

## Verification

```bash
cd backend
npm run lint
npm test                 # unit
npm run db:migrate       # replay from empty
npm run db:migrate:check # checksum ledger
npm run db:types:check   # generated types still match the schema
npm run test:e2e         # integration, needs Postgres + Redis
npm run build
```

```bash
melos run analyze        # all 7 packages, must be zero issues
melos run test
dart format --set-exit-if-changed .
```

Point integration tests at a disposable database. Never at production.

## Release

Release builds compile `apps/mobile_app/dart_defines.release.json`, which is
the single source of truth for build-time values. `scripts/ios_release.sh`
refuses to run without it, because a build made without it signs and installs
perfectly and cannot reach the API.

```bash
cd apps/mobile_app && flutter build ipa \
  --obfuscate --split-debug-info=build/app/outputs/app-symbols/release \
  --dart-define-from-file=dart_defines.release.json
```

`--obfuscate` is required for anything shipped, so the compiled Dart in the IPA
isn't trivially readable. Keep the symbol map for crash deobfuscation; do not
ship it.

Two skills run the whole job: say "push to testflight"
(`.claude/skills/ship-testflight`) or "deploy live" / "push to the store"
(`.claude/skills/ship-appstore`). Both build on this Mac. `docs/PUBLISHING.md`
has the full story.

## Inherited security facts

This codebase descends from a repository whose git history contains two live
credentials. They are **not** in this repository's history, but they remain
valid against the legacy production system until rotated:

- a `service_role` JWT (exp 2036), and
- the App Store Connect key `AuthKey_V5L2554CT7.p8`.

Removing a file from a tip is not rotation. See
`docs/security/SECRET_ROTATION_RUNBOOK.md`.

**Never commit** `ios/Runner/GoogleService-Info.plist`, `ios/AuthKey_*.p8`,
`android/key.properties`, the release keystore, or any service-account JSON.
All are gitignored.

## Sensitive files (not in git)

| File | What it is | Needed for |
|---|---|---|
| `apps/mobile_app/ios/Runner/GoogleService-Info.plist` | Firebase iOS config | push notifications |
| `apps/mobile_app/ios/AuthKey_*.p8` | APNs auth key | FCM push on iOS |
| `apps/mobile_app/android/key.properties` | keystore passwords | release builds |
| `apps/mobile_app/android/app/bitsheel-release.jks` | Android signing key | release builds |
| `backend/.env` | runtime secrets | running the API |

If these are lost the app cannot ship. Back them up outside the repo.
