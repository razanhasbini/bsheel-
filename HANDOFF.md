# Bsheel — handoff

**Written 2026-09-08.** For whoever picks this up next, Claude or Codex. It
assumes no memory of previous sessions. Read this before touching anything.

Everything below is either **verified** (I ran it and saw the result) or
explicitly marked **unverified**. Do not treat an unverified claim as done.

---

## 1. What this repo is

A gamified quest app. Users get 3 real-world challenges, pick one, complete it
inside a timer, submit photo/video proof, a moderator approves it, they earn
XP. Plus a social layer: feed, votes, comments, follows, blocks, collab groups,
leaderboards.

```text
apps/mobile_app   Flutter (iOS + Android)
apps/admin_web    Flutter web admin dashboard
        |  HTTPS /api/v1  +  WebSocket /realtime
backend/          NestJS 11 modular monolith, Node 24, raw `pg` (no ORM)
        |
PostgreSQL 17 (authoritative) · Redis 7.4 (BullMQ, locks) · S3/R2 (private media)
```

**This is not the production repo.** Production is a different repository
running the legacy Supabase stack. This one is a clean rebuild. There is no
deployment pipeline here and nothing here can affect production.

**Supabase is completely gone from this repo.** If you find a reference,
it is a bug.

---

## 2. Run it locally (verified working)

Four processes. All commands from the repo root unless stated.

### 2.1 Prerequisites on this machine

| Tool | Location / note |
|---|---|
| Node 24 | `export PATH="/opt/homebrew/opt/node@24/bin:$PATH"` — **required**, system node is 20 and the backend will not run on it |
| Flutter 3.38.5 | `/Users/tayseerlaz/development/flutter/bin` — matches CI exactly |
| melos | `~/.pub-cache/bin` |
| PostgreSQL 16 | already running on `127.0.0.1:5432`, user `bsheel`, password `bsheel` |
| Redis | running on `127.0.0.1:63799`, **no auth**. Do NOT use 6379 — it is password-protected |
| MinIO | installed via brew, stands in for R2 locally |
| Docker | **not running on this machine.** `docker compose up` will not work. Run the pieces natively as below |

### 2.2 Start object storage (MinIO)

```bash
mkdir -p /tmp/bsheel-minio
MINIO_ROOT_USER=bsheeldev MINIO_ROOT_PASSWORD=bsheeldevsecret \
  /opt/homebrew/opt/minio/bin/minio server \
  --address 127.0.0.1:9000 --console-address 127.0.0.1:9001 \
  /tmp/bsheel-minio &
```

Create the bucket once (uses the AWS SDK already in `backend/node_modules`):

```bash
cd backend && node -e "
const {S3Client,CreateBucketCommand}=require('@aws-sdk/client-s3');
new S3Client({endpoint:'http://127.0.0.1:9000',region:'us-east-1',forcePathStyle:true,
  credentials:{accessKeyId:'bsheeldev',secretAccessKey:'bsheeldevsecret'}})
  .send(new CreateBucketCommand({Bucket:'bsheel-dev'})).then(()=>console.log('ok'));"
```

`backend/.env` is already pointed at MinIO with `S3_FORCE_PATH_STYLE=true`
(MinIO needs path-style addressing; R2 accepts either).

### 2.3 Start the API

```bash
export PATH="/opt/homebrew/opt/node@24/bin:$PATH"
cd backend
set -a && . ./.env && set +a
npm run db:migrate          # replays 0001..0016 from empty
npm run build
node dist/main.js &
```

> **The API takes ~60 seconds to become ready.** `NestFactory.create` alone
> takes ~52s on this machine. Do **not** conclude it is hung before 2 minutes.
> `nest start --watch` is even slower and appeared to hang for 10+ minutes —
> use the compiled `node dist/main.js` instead. Reducing this startup time is
> an open task.

Wait for it properly:

```bash
until curl -sf http://127.0.0.1:3010/api/v1/health/live >/dev/null; do sleep 3; done
curl -s http://127.0.0.1:3010/api/v1/health/ready
```

API on `http://127.0.0.1:3010/api/v1`, OpenAPI at `/docs`.

### 2.4 Seed data

```bash
cd backend && set -a && . ./.env && set +a
node scripts/seed-local.mjs --reset
```

Creates 8 users, 15 quests, 13 submissions covering every review state
(approved, rejected, pending, appealed-and-pending, re-rejected,
soft-deleted, expired), a duplicate-caption case that triggers the review
queue's DUPLICATE badge, follows, votes, comments, one block, one open
report, a Quest of the Day, a waitlist entry and a quest suggestion.

**All accounts use password `Str0ng-Passphrase-9`:**

| Email | Role |
|---|---|
| `admin@bsheel.test` | super_admin |
| `mod@bsheel.test` | moderator |
| `layla@` `omar@` `rana@` `sami@` `nour@` `ziad@bsheel.test` | user |

`--reset` makes it idempotent. The script validates its own plan against the
one-active-quest index before inserting, so a bad edit fails with a readable
message instead of a `23505`.

### 2.5 Run the clients

```bash
cd apps/admin_web  && flutter run -d chrome     # admin dashboard
cd apps/mobile_app && flutter run               # simulator, or -d chrome
```

Debug builds default to `http://127.0.0.1:3010/api/v1`, so no flags needed.

---

## 3. What is done

### 3.1 Supabase removal — complete and verified

- 61 files that reached Supabase directly were ported to the API.
- 60 `BackendConfig.usesNest` dual-mode branches across 36 files removed.
- 16 `Supabase*Repository` implementations deleted (1,634 lines), plus both
  `supabase_provider.dart`, the override lists, and the legacy client-side
  notification fan-out.
- `supabase_flutter` removed from all three pubspecs.
- Legacy trees deleted: `supabase/` and `cloudflare/` — **20,067 lines across
  185 files**, plus `check_schema_drift.sh` and `validate_contract.sh`.
- `AppBackend` is now the single composition root per app: one HTTP client,
  one rotating token store, one instance of each repository.

**The hard part was auth.** `AuthRepository` — the *interface* — was typed
entirely in Supabase types, so `ApiAuthRepository` fabricated Supabase session
objects out of our own JSON to satisfy it. That is why the dependency could
not simply be dropped. It is now a plain Dart model (`AuthUser`,
`AuthSession`, `AuthState`, `AuthResult`, `AuthException`) in
`packages/app_repositories/lib/auth/auth_models.dart`.

### 3.2 Package rename

`supabase_contracts` → `app_contracts`. Dead constants deleted (all had zero
live references): `RpcNames`, `EdgeFunctionNames`, `StoragePaths`,
`StorageBuckets`, `XpStatsRpcColumns`, `WorkerUrls`, `WorkerMediaTypes` and
all eleven `*Params` classes. `Tables` became `EmbedKeys` and shrank 19 → 3
entries, because its only surviving use was supplying JSON keys for objects
the API *nests* in a response — never table names.

### 3.3 New backend endpoints

Added so no admin surface lost capability during the port:

| Endpoint | Purpose |
|---|---|
| `GET /profiles/by-username/:username` | exact @mention lookup (search is fuzzy and must not decide navigation) |
| `GET /submissions/admin` | filterable admin list: `status`, `appealed`, `visibility`, `order`, pagination |
| `GET /submissions/admin/review-queue` | moderation queue **with server-computed** per-user approved/rejected counts and `is_duplicate` |
| `GET /submissions/admin/:id` | review detail incl. `is_retake` and collab context |
| `GET /admin/notifications` | recent automatic notifications |
| `GET /admin/xp-audit` | stored vs expected XP, one aggregate |
| `PATCH /admin/users/:id/profile` | audited profile edit, one transaction |
| `POST /quests/admin/assign` | admin override, displaces the in-flight quest |

The review queue and XP audit compute aggregates in SQL. The admin pages used
to fetch every submission for every queued user, and every profile plus every
approved user_quest, to derive them in the browser.

### 3.4 Migrations added

| Migration | What |
|---|---|
| `0014_seed_public_app_config.sql` | seeds the 6 public `app_config` keys |
| `0015_performance_indexes.sql` | 22 indexes, each justified by a measured EXPLAIN |
| `0016_media_quota_and_reclaim.sql` | indexes for per-user media quota + orphan reclaim |
| `0017_media_submission_ownership.sql` | explicit submission-to-media ownership for safe reclaim |

### 3.5 Bugs found and fixed

| Bug | Why it mattered |
|---|---|
| `test:e2e` could not run at all — `vitest.config.e2e.ts` imported `vite-tsconfig-paths`, declared nowhere | CI never ran it, and the suite was still Nest's scaffold expecting `GET / → "Hello World!"` |
| Env schema rejected an empty optional var | the documented `cp backend/.env.example backend/.env` produced a config the app refused to boot with |
| `admin_web` did not compile (`repositories.profile` vs `profiles`) | `main` was broken; the last recorded checkpoint claimed otherwise |
| Registration returned one `ACCOUNT_CONFLICT` for both cases | the signup form could not tell the user which field to change. Now `EMAIL_TAKEN` / `USERNAME_TAKEN` |
| `app_config` never seeded | force-update gate had no row to read, and the social-login kill switch **defaulted to ON when absent** — a kill switch that fails open is not a kill switch. Now fails closed |
| 109 of 258 Dart files not `dart format` clean | `format_and_analyze.yml` could not have passed. Also `require_trailing_commas` **contradicts** the formatter CI enforces — no tree could satisfy both. Lint removed; formatter owns commas |
| `FeedPostModel.copyWith` silently dropped `expiresAt` | it is called on every feed post during media signing, so every post lost the timestamp the collab "WAITING FOR → DIDN'T POST" flip depends on |
| 10 further model defects | see §3.6 |
| `.git/index` was corrupt (I/O timeout) | no `git status`, `diff` or commit was possible. Rebuilt out-of-place and moved in; objects and HEAD were never at risk |

### 3.6 Model hardening

`packages/app_models` went from **0 tests to 319**. All coercion logic is now
one shared implementation in `lib/src/json_coercions.dart` instead of nine
slightly-different private copies. Fixed: `level` defaulting to 1 on profile
but 0 on leaderboard; lossy `toJson` dropping takedown state; a missing
timestamp throwing and killing a whole list parse (now degrades to epoch, and
optional timestamps become null rather than `now()`); two fail-open boolean
coercions (`show_in_feed` now fails **closed**); `mediaUrls` returning `['']`;
inconsistent int coercion and join tolerance; `duration_hours` clamping;
`effectiveMediaType` contradicting its own doc. Value equality added to 17
classes (deliberately not to `CommentModel` — recursive reply tree).

### 3.7 Docs rewritten to match reality

`CLAUDE.md`, `README.md`, `docs/architecture.md`, `docs/DEPLOYMENT.md`,
`docs/database_contract.md`, `docs/api/auth_test_matrix.md`,
`docs/PRIVACY_POLICY.md` (was factually wrong — claimed data lives in
Supabase), plus real READMEs for all 5 packages and both apps (they were
unmodified Flutter templates). `FIXLOG.md` has an entry for this work.

Deleted: `CLAUDE_MIGRATION_MASTER.md`, `docs/migration/`, and
`.github/workflows/deploy-server.yml` — that workflow rsynced the **legacy
Supabase stack** to a shared production host on every push to `main`, which
no longer matches what the apps talk to.

### 3.8 CI fixed

`ci.yml` now runs what it claimed to: PostgreSQL 17 + Redis 7.4 service
containers, a migration replay from empty, the checksum ledger check, and the
integration suite. `melos.yaml`'s `test` script no longer excludes
`app_repositories`, whose 24 wire-contract tests had **never run in CI**.

CI test count went from **54 to 454**.

---

## 4. Testing: what exists and what is proven

### 4.1 Dart — all verified passing

```bash
melos run analyze     # all 7 packages: "No issues found!"
melos run test        # 454 tests
dart format --set-exit-if-changed .   # exit 0
```

| Package | Tests |
|---|---|
| app_models | 319 |
| app_contracts | 57 |
| mobile_app | 33 (+1 skipped: screenshot gallery, opt-in via `--dart-define=SCREENSHOTS=true`) |
| app_repositories | 24 — the wire-contract suite |
| app_core | 18 |
| admin_web | 2 |
| shared_ui | 1 |

### 4.2 Backend — verified

```bash
cd backend && set -a && . ./.env && set +a
npm run lint             # clean (verified)
npm test                 # 48 unit tests (verified)
npm run db:migrate       # applies through 0017 (verified)
npm run db:migrate:check # passes (verified)
npm run test:e2e         # 137 passed, 2 skipped (verified twice)
```

> The E2E suite is now verified. All ten spec files pass twice consecutively:
> 137 tests passed and 2 opt-in tests were skipped on each run. One logged
> integer-overflow error is an intentional negative test that expects HTTP 500.
> The old warning below is retained only as historical context.
>
> **Historical warning:** two suites were once known good —
> `app.e2e-spec.ts` (12 tests) and `auth-registration.e2e-spec.ts` (4) — I ran
> those myself. **Eight further spec files were written by an agent that was
> killed before it could run them:**
>
> `admin-surface`, `comment-notifications`, `profiles-lookup`,
> `quest-assignment`, `social-graph`, `submission-appeal`,
> `submissions-admin`, `xp-award` — plus `test/support/e2e-harness.ts`.
>
> **They have never been executed.** Expect failures, compile errors, and
> possibly half-written files. Running and fixing them is task R1 below.
>
> Budget for slowness: each app boot is ~60s. Use hook timeouts of
> **≥ 120000 ms** and prefer booting once per suite via the harness.

### 4.3 End-to-end behaviour I verified by hand against the live stack

This is the part that matters most, because none of it was provable from code
alone. All of the following was **run and observed**:

**The core user loop** — register → quest picker → accept → request upload
intent → presigned PUT straight to MinIO (HTTP 200) → server-side magic-byte
validation → complete → submit proof → moderator approves → **XP 0 → 20,
exactly once** → post appears in feed → private key exchanged via
`/media/sign` → **signed URL fetched, 77 real bytes**.

| Check | Result |
|---|---|
| XP idempotency | second approve refused with `SUBMISSION_ALREADY_REVIEWED`, XP unchanged |
| Block filtering | ziad blocked omar → omar absent from ziad's feed, everyone else present |
| Review-queue enrichment | `sami` flagged `is_duplicate=True` for reusing a rejected caption; nobody else flagged |
| XP audit | current == expected for all 8 users |
| `/admin/stats` | matches the seed exactly |
| Appeals queue | layla's appeal surfaces with its note |
| Feature flags | all 6 `app_config` rows served by `GET /config` |
| Notifications + outbox | notification created, outbox 5/5 processed |
| One-active-quest index | **enforced** — my first seed attempt violated it and was correctly rejected |

**Admin page field mappings — all 13 verified.** I wrote a script that
extracts every JSON string key each ported page reads and checks it against a
live API response. Two pages flagged; both were **false positives** on
inspection (a nested `quests` object, and a page with two data sources). **No
field-name mismatches.** The audit script is at
`/private/tmp/.../scratchpad/key_audit.py` — it is scratch, not committed;
rewrite it if you want it permanently.

### 4.4 What is NOT tested

- **No Flutter widget has ever been rendered.** I cannot see a browser. Field
  mappings, repositories and the API are verified; layout errors, null-check
  crashes in `build()`, or a provider throwing during render would **not** have
  surfaced. This is the largest residual risk.
- No load test.
- No live-provider test: Firebase, email, Google/Apple OAuth, Telegram.
- No iOS build (needs the signing identity, absent from this machine).

---

## 5. Remaining work, in the order I would do it

### R1 — Verify the 8 unrun integration specs · **complete**

They are written but never executed (§4.2). Read the implementation in
`backend/src/modules/**` before changing any assertion.

**Rule: never weaken an assertion to get green.** If real behaviour differs
from what a test expects, decide which is right — if the *source* is wrong,
mark the test `.skip` with an explanation and report the bug. A suite that
passes by asserting nothing is worse than a failing suite.

Use a disposable database (`bsheel_agent_d` exists and is safe to reuse).
The suite now passes twice consecutively, proving cleanup.

### R2 — Finish the media quota / reclaim feature · **complete**

**Already done and building:**
- `migrations/0016_media_quota_and_reclaim.sql` — the indexes
- `src/config/environment.ts` — `MEDIA_MAX_*`, `MEDIA_RECLAIM_*` config
- `.env.example` — documented
- `media.repository.ts` — `quotaSnapshot`, `claimReclaimable`, `markReclaimed`
- `media.service.ts` — quota enforced (`MEDIA_QUOTA_EXCEEDED`), size caps now
  config-driven instead of hard-coded

The reclaim sweep is now a scheduled BullMQ job in `worker.module.ts`, with
explicit submission ownership from migration 0017 and focused tests covering
disabled operation, all three reclaim reasons, and storage-failure retry
semantics. The quota boundary and retry behavior are covered by the existing
media/E2E suites.

Why this design: the deleted Cloudflare worker enforced the quota by LISTing
the user's bucket prefix **on every upload**, and swept orphans by LISTing the
**whole bucket**. Both are O(objects) network round-trips for work the
database answers from an index.

### R3 — Perf source fixes (from `backend/PERFORMANCE.md`)

Measured on a seeded database (20k profiles, 40k submissions, 150k reactions,
80k comments). Ranked by impact:

1. **The outbox publisher is in the wrong module.** `MessagingModule` is
   imported by `app.module.ts`, not `worker.module.ts` — so the ~50 events/sec
   ceiling scales with **API** replicas and adding workers raises nothing.
   This contradicts the documented design. Move it, and consider
   `OUTBOX_POLL_MS=250` (→200/s, no code change) plus `queue.addBulk`.
2. **The pool cannot reach 3 replicas.** 20 connections per process, one pool
   each in `main.ts` and `main.worker.ts`, against `max_connections=100` →
   ceiling of 2 API + 2 worker; a third pair fails with `53300`. Worse,
   `connectionTimeoutMillis` is **unset**, so exhaustion queues *indefinitely*
   while the 15s statement timeout holds slots — a hang, not an error.
   Recommended: API max 10, worker max 12, add
   `connectionTimeoutMillis: 5000`, and raise `max_connections` or front with
   PgBouncer (safe — the one advisory lock is transaction-scoped).
3. **The feed is O(all approved submissions) per page**, for every sort mode:
   587 ms and 433k buffer hits to return 20 rows. Its `ORDER BY` opens with
   four `CASE WHEN $4 = …` arms, so even `sort=recent` cannot use the index.
   No index fixes this; `PERFORMANCE.md` has the rewrite (per-mode `ORDER BY`,
   denormalised `net_score`, rank-then-join for `hot`).
4. **`addComment` is N+1** — 2 statements per thread participant. Measured
   200 statements / 64 ms on a 100-participant thread; batched CTE is 6 ms.
   Same pattern in four other notification fan-outs.
5. **Only `notifications` uses a keyset cursor.** ~20 other lists use
   `LIMIT/OFFSET`; `listForAdmin` goes 0.93 ms @0 → **153.9 ms @39,000** with a
   disk-spilling sort.

### R4 — Render the UI and walk the journeys

The one thing no automation here has covered. Boot the stack, open the admin
dashboard in Chrome and the mobile app in a simulator, and walk every screen.
Expect widget-layer bugs (layout, null checks in `build()`, providers throwing
during render). Data-layer risk is already retired.

### R5 — Kysely + layering (largest, do last)

- Adopt **Kysely** for compile-time-checked SQL. It keeps full control of
  `FOR UPDATE`, `SKIP LOCKED` and explicit `ON CONFLICT` arbiters, which an
  ORM fights. Motivation: raw SQL strings are unchecked, and that exact class
  of bug shipped in the legacy system — a query referenced a column that did
  not exist and failed silently every hour for a day, having never once
  succeeded.
- Move notification copy out of `social.repository.ts` into a templates
  module. Copy strings currently live in the **persistence** layer.
- Split `admin.repository.ts` (781 lines).

Do this **after** R1, so the refactor happens behind a working test suite.

### R6 — Blocked on credentials / decisions (not startable here)

| Item | Needs |
|---|---|
| Firebase push, email delivery, Google/Apple OAuth, Telegram | real credentials |
| Deployment pipeline | a decision on where the API runs + a secret store |
| iOS build / TestFlight | the signing identity |
| **OAuth account linking** | **a product decision — see §6** |

---

## 6. Open decisions

**OAuth implicit linking changed behaviour.** Supabase auto-linked a Google
identity to an existing password account with the same verified email. The
NestJS backend matches on `(provider, provider_subject)` and does **not** link
implicitly. That is the safer default — silent linking on a matching email is
a documented takeover vector — but it means a user who signed up with a
password and later taps "Continue with Google" gets a **second account**. Needs
a product decision plus support copy. Documented in
`docs/api/auth_test_matrix.md` §3.

**Two legacy behaviours still have no equivalent** (neither was in the
capability analysis that cleared the deletion):
- Per-user object-count cap — **now implemented** (R2), was 5,000 submissions
  / 20 avatars.
- Orphan media sweep — **partially implemented** (R2). Until the scheduler
  lands, every avatar change and every abandoned upload leaks an object
  forever.

**Enforcement lost with `validate_contract.sh`.** Two of its six checks were
not Supabase-specific: cross-feature `presentation/` imports, and duplicate
model classes shadowing `app_models`. Both rules are still stated in
`CLAUDE.md` and now have no automated enforcement. Worth re-adding as a lint
or a CI step.

---

## 7. Environment gotchas that will waste your time

1. **Node 24 is mandatory.** System node is 20; the backend will not run.
2. **The API takes ~60s to boot.** Do not diagnose a hang before 2 minutes.
   Use `node dist/main.js`, not `nest start --watch`.
3. **Redis is on 63799 without auth.** Port 6379 has a `requirepass`.
4. **Docker is not running.** No `docker compose`. Run pieces natively.
5. **`.git/index` corrupted once** with an I/O timeout on this disk. If
   `git status` fails again: `GIT_INDEX_FILE=/tmp/i git read-tree HEAD` then
   `cp /tmp/i .git/index`. Objects and HEAD were never affected.
6. **`dart format` writes by default.** Use `-o none` (or
   `--output=none`) for a read-only check, especially with agents running.
7. **`outbox_events` has no FK to its aggregate**, so a `user.created` row
   survives a `users` cascade delete. Test cleanup must delete it explicitly —
   `auth-registration.e2e-spec.ts` shows how.
8. **Never point tests at production.** `seed-local.mjs` refuses a URL that
   looks like `bsheel.app`; keep that guard.

---

## 8. Git state

```text
a68c363  Rename supabase_contracts to app_contracts; drop its dead constants
9a44e40  Remove Supabase; single-stack on the self-hosted API
9737f8a  Initial project commit
```

Roughly 37 uncommitted paths at time of writing — the media quota work (R2),
the perf audit outputs, the seed script and this file. Commit per stage.

Branch: `main`. Remote: `github.com/razanhasbini/bsheel-`. **Never
force-push** — the history of the *legacy* repo carries a leaked credential
and a rewrite breaks clones mid-rotation.

---

## 9. Inherited security facts (still true)

This codebase descends from a repo whose git history contains two live
credentials. They are **not** in this repository's history, but they remain
valid against the **legacy** system until rotated:

- a `service_role` JWT (exp 2036)
- the App Store Connect key `AuthKey_V5L2554CT7.p8`

Removing a file from a tip is not rotation. See
`docs/security/SECRET_ROTATION_RUNBOOK.md`, which also contains a worked
overlap plan exploiting the fact that PostgREST validates against a
multi-key JWKS while GoTrue signs with one.

Never commit: `GoogleService-Info.plist`, `AuthKey_*.p8`, `key.properties`,
the release keystore, any service-account JSON, or `backend/.env`.
