# Bsheel — handoff

**Written 2026-09-08.** For whoever picks this up next, Claude or Codex. It
assumes no memory of previous sessions. Read this before touching anything.

Everything below is either **verified** (I ran it and saw the result) or
explicitly marked **unverified**. Do not treat an unverified claim as done.

**Amended 2026-09-09.** Test and migration counts have been replaced with the
commands that produce them, because the numbers went stale within a day. The
timing warnings below were measured on the Mac this was written on and do not
hold on other hardware — they are marked as such rather than removed, since
they are still true there.

**Status as of the last session.** Backend is green and its runtime paths are
verified live: lint clean, the unit suite, every migration replaying from empty,
the type-drift gate, and the full e2e suite. API and worker start clean; every
reachable route returns 200; media presigning, the outbox, the hourly media
reclaim and the realtime gateway were each exercised against the running
stack. Both clients are at zero analyze issues and conform to the two design
specs. R3.5 (keyset pagination beyond the feed), a human render pass, and R6
(credentials and deploy decisions) are what remain.

**Two traps that cost earlier sessions real time**, both now understood:

- `nest build` and `NestFactory.create` were both very slow **on the Mac this
  was written on** — ~2m45s and ~52s — and sessions repeatedly killed them
  early and reported a stall. They are seconds-to-milliseconds on other
  hardware, so treat the numbers as that machine's, not the project's, and
  measure before concluding anything is hung.
- A failed `git status` prints nothing and exits non-zero, so piping it to
  `wc -l` reports `0` — a false clean tree. See R7.

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
| PostgreSQL 16+ | on that machine, `127.0.0.1:5432`, user `bsheel`, password `bsheel`. `docker compose up -d postgres` exposes 54329 instead |
| Redis | running on `127.0.0.1:63799`, **no auth**. Do NOT use 6379 — it is password-protected |
| MinIO | installed via brew, stands in for R2 locally |
| Docker | was not running on the machine this was written on, hence the native instructions below. Where Docker *is* available, `docker compose up -d postgres redis` is the shorter path |

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
npm run db:migrate          # replays every migration from empty
npm run build
node dist/main.js &
```

> **On the Mac this was written on, the API took ~60 seconds to become ready**
> (`NestFactory.create` alone ~52s), and `nest start --watch` appeared to hang
> for 10+ minutes. That is a property of that machine, not of the project —
> elsewhere it is near-instant. Prefer the compiled `node dist/main.js`, and
> wait on the health endpoint below rather than on a stopwatch.

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
| admin_web | 10 |
| shared_ui | 1 |

### 4.2 Backend — verified

```bash
cd backend && set -a && . ./.env && set +a
npm run lint             # clean (verified)
npm test                 # unit suite (verified)
npm run db:migrate       # replays every migration from empty (verified)
npm run db:migrate:check # passes (verified)
npm run db:types:check   # types match the schema (verified)
npm run test:e2e         # full integration suite (verified repeatedly)
npm run build            # exit 0 (verified; timing is machine-specific)
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

### R3 — Perf source fixes · **4 of 5 complete**

Measured on a seeded database (20k profiles, 40k submissions, 150k reactions,
80k comments).

1. **Outbox publisher in the wrong module** — **done.** `app.module.ts` now
   imports `MessagingQueueModule` (queue only) and `worker.module.ts` imports
   `MessagingModule` (queue + publisher). They were exactly backwards, so every
   API replica ran its own publisher loop and contended on the same
   `SKIP LOCKED` claim. With one poller, `OUTBOX_POLL_MS` dropped 1000 → 250.
   Verified live: a follow emitted `social.follow.changed` +
   `notification.created` and the worker drained both.
2. **Pool ceiling** — **done**, all three parts: API max 10,
   `DATABASE_WORKER_POOL_MAX` 12, and `DATABASE_CONNECTION_TIMEOUT_MS` 5000.
   The missing timeout was the worst of it: exhaustion queued indefinitely
   while the 15s statement timeout held slots, so it presented as a hang with
   no error.
3. **Feed `ORDER BY`** — **done.** The four `CASE WHEN $4 = …` arms are gone;
   per-mode ordering is composed from booleans derived from an `@IsIn`
   validated `sort`, with all values still parameterised. Migration
   `0019_feed_ranking.sql` backs it.
4. **`addComment` N+1** — **done.** `insertNotificationBatch` replaces the
   per-participant statements.
5. **Keyset pagination** — **partial, the one item left.** `keyset-cursor.ts`
   is good work (context-bound so a feed cursor cannot be replayed on another
   list, length-capped, shape-validated, stable `INVALID_CURSOR`), but only
   the feed uses it. ~20 lists remain on `LIMIT/OFFSET`; `listForAdmin` still
   goes 0.93 ms @0 → 153.9 ms @39,000 with a disk-spilling sort.

### R4 — Design-spec conformance · **complete**; render pass still worthwhile

Both apps were brought up to `mobile-handoff/SPEC.md` and
`admin-handoff/SPEC.md`: 144 contrast fixes, 49 controls raised to a 44pt hit
area, ~100 overflow/overlap fixes, and the missing shared primitives
(`ArcadeCategoryTag`, `ArcadeStatusPill`, `ArcadeSkeleton`). Evidence is in
the commit message for `14acaa2`.

Automated rendering coverage now exists: the mobile screenshot gallery renders
~20 screens with zero `RenderFlex overflowed` and zero unbounded-flex
assertions, and an admin probe exercised the primitives at 1280/760/360px.
What is still **not** done is a human walking the app in a simulator and the
dashboard in Chrome — automation cannot judge whether a screen reads well.

Two known gaps, both deliberate:

- `BsheelColors.inkMuted` (2.9:1) is still used for ~120 non-placeholder text
  runs. The spec reserves it for placeholders and disabled state. Converting
  all of them risks flattening deliberate hierarchy, so it needs a design
  decision rather than a sweep.
- `bsheel_widgets.dart` and `admin_theme.dart` still carry the older
  black-and-white direction in their doc comments and tone mapping
  (`BsheelPillTone.gold`/`.violet` both resolve to an ink fill). The tokens
  are Arcade Pop; the primitives have not been re-skinned to match.
- 3 screens in the opt-in screenshot gallery throw
  `AppBackend.initialize() was not called` — those pages reach
  `AppBackend.repositories` at build time and the test's fakes do not cover
  it. Pre-existing, excluded from the default suite.

### R5 — Typed SQL + layering · **mostly complete**

- **Typed SQL — done, and it had already drifted.**
  `scripts/database-types.mjs` generates `database.types.ts` from the migrated
  schema and `DatabaseService` consumes it as its Kysely `Database` interface.
  No npm script invoked the generator, so its `--check` could never fire and
  the types were missing everything migrations 0017-0020 added. Now wired as
  `db:types` / `db:types:check`, regenerated, and gated in CI between the
  checksum ledger and the e2e run.
- **`admin.repository.ts` split — done**, into identity / users / moderation /
  operations over a shared base, behind a facade. Note it landed without its
  providers registered, which broke all ten e2e files at module init; a scan
  now confirms every `@Injectable` is named in some module.
- **Notification copy out of the persistence layer — still open.** Copy
  strings remain in `social.repository.ts`.

### R6 — Blocked on credentials / decisions (not startable here)

| Item | Needs |
|---|---|
| Firebase push, email delivery, Google/Apple OAuth, Telegram | real credentials |
| Deployment pipeline | a decision on where the API runs + a secret store |
| iOS build / TestFlight | the signing identity |
| **OAuth account linking** | **a product decision — see §6** |

### R7 — This machine's disk, which is actively causing failures

`.git/index` writes time out intermittently: the disk is at 97% (7.6 GiB free)
and `fileproviderd` runs hot. Writes to `/private/tmp` always succeed while
write-in-place to `.git` stalls, which is the signature.

This matters beyond inconvenience. A failed `git status` prints **nothing and
exits non-zero**, so `git status --porcelain | wc -l` reports `0` — and that
false "clean tree" is how four migrations and the media-reclaim scheduler sat
untracked across three sessions. **Check the exit code, not the line count.**

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
