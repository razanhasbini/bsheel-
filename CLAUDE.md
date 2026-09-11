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
  business_web/        partner dashboard (#50), served at admin.bsheel.app/business
packages/
  app_core/            design tokens (QuestColors/Spacing/Typography), logger, utils
  app_models/          shared data models
  app_repositories/    repository contracts + their HTTP implementations
  shared_ui/           reusable widgets
  app_contracts/       domain value constants + API field names
backend/
  src/modules/         auth, profiles, quests, submissions, feed, social,
                       collab, notifications, media, admin, account,
                       public-intake, search, leaderboard, business, health
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
decision. Each vision rung returns a verdict *and* two measurements of
the media — a `relevance` score and a typed observation list, absences
included — which is what the agent reads back as its CV evidence. The asymmetry is deliberate: the cheapest model may clear a
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
asserted in a migration, and `finalizeDecision` enforces that against
the agent path too, not only against this cascade.

When it does act, it calls the *same* `approve`/`reject` a moderator's
click uses with a null actor, so the XP-awarded-once invariant, the
notification, the audit row and the collab fan-out cannot drift between
a human decision and an automated one.

### Two verifiers, one decider, one vision pass

`submission.created` starts both verifiers, and they answer different
questions: this cascade asks whether the *media* is authentic and shows
the task; the agent (`modules/agent`, #53) asks whether the *device* was
where the quest required. Exactly one of them may act, and it is the
better-informed one — when `AGENT_SUBMISSION_VERIFICATION_ENABLED` is
true this cascade records its verdict and steps aside
(`willActOnDecisions`), because the agent weighs the CAMARA evidence
*and* this pass's findings.

It sees those findings because `CV_PROVIDER=local` (the default) binds
`LocalCvEvidenceProvider`, which **reads** the row this cascade already
wrote rather than running a second vision call on the same bytes. The
consumer awaits the cascade before enqueueing the agent job, so the
finding is always there — that ordering is load-bearing and
`domain-events.processor.spec.ts` fails if it is reordered. With
`CV_PROVIDER=none` the agent is blind and escalates everything, which is
what every deployment did before the binding existed.

`relevance` (0..1, on `submission_verifications`) is how much the media
has to do with the quest, and is **not** confidence — a model can be
certain a cat photo is irrelevant to "watch the sunrise". It can stop an
automated approval below `AI_VERIFICATION_MIN_RELEVANCE` and can never
cause a rejection, and it is admissible only where the contract says
`content`: for a quest no photograph can show, low relevance is what
honest proof looks like.

Escalations surface at `/moderation/unclear` with a sidebar badge, and
deciding there clears the escalation in the same transaction. The review
screen carries an **Agent's read** panel — verdict, verdict confidence, media
relevance, and the typed observations with absences — because a shadow-mode
verdict is only worth recording if a person can see it while deciding
independently.

Turning any of this on is a sequence, and the order matters:
`docs/PROOF_VERIFICATION_RUNBOOK.md`. For someone testing it rather than
operating it, `docs/TESTING_THE_AI_REVIEWER.md` is the shorter read. Note in particular that
`AGENT_SUBMISSION_VERIFICATION_ENABLED=true` is necessary and **not
sufficient** — the agent pipeline also checks an `app_config` row seeded
`false` by migration 0026, toggled at Settings → AI SUBMISSION VERIFICATION.

Three traps worth knowing. EXIF `DateTimeOriginal` is local wall-clock
with **no timezone**, so the capture-window check is widened by the
maximum UTC offset unless EXIF carries one — without that it accuses
honest players in other timezones. `etag` is not a usable content
hash: it is a hash of part hashes for multipart uploads, which is why
`media_objects.content_md5` exists. And a dHash of 64 identical bits
distinguishes nothing — every flat frame *and* every smooth
one-directional gradient produces it, so two unrelated blank-ish photos
sat at Hamming distance 0 and read as each other's stolen proof.
`differenceHash` returns null for those, `perceptual_hash` is nullable,
and null means "cannot be fingerprinted" rather than "matches
everything".

Both claims — the vision pass's and the agent run's — are **leases**,
not labels. A worker killed holding one used to make the submission
permanently unprocessable, silently; an expired claim is now taken. The
vision pass's lease is also what stops the inline consumer and the
catch-up sweep paying for the same vision call twice.

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

## Business / destination accounts (#14)

A business is an **ordinary player with extra rights over its own places**.
Not an admin, not a tier of user, not a variant account: its members roll
quests, post to the feed and appear on the leaderboard like anyone else,
and additionally may read the dashboard for the places they speak for.

The thing to not get wrong: **`business` is not a system role.**
`systemRoles` (`user`, `moderator`, `super_admin`) is the admin ladder —
every member means "authority over the whole platform", it is carried in
the access token, and `RolesGuard` reads it as "at least this much". A
business has no authority over the platform at all. Putting it in that enum
would force every `@Roles` site and the admin dashboard's route gating to
reason about a role with no ordering against the others, and would change
what an already-issued token's `role` claim means. `business.spec.ts` fails
if someone adds it.

So authority is **membership, not rank**, in three tables:
`businesses`, `business_places` (which real places it speaks for), and
`business_members` (who may act for it, `owner` or `manager`, scoped to
that one business). `BusinessAccessGuard` resolves it **per request from
the database, never from the token** — access is granted and revoked by a
person, and a token issued before a revocation would otherwise keep working
until it expired.

Four rules worth knowing before changing anything here:

- **A non-member gets 404, not 403.** A 403 confirms the business exists,
  which turns walking the id space into a directory of who is on the
  platform. A super_admin is *also* a non-member and gets the same 404 on
  the member routes — managing businesses happens through the audited admin
  routes, which is what stops "can moderate the platform" from quietly
  becoming "can read every business's visitors".
- **A place has at most one owner**, enforced by a UNIQUE constraint on
  `business_places.place_id` alone. Without it two businesses could both
  claim a landmark and both read its visitors, which is a leak between
  competitors dressed up as a modelling mistake.
- **Claiming a place is super_admin-only and deliberately not self-serve.**
  A place is a real location whose visitor data the owner gets to read, and
  there is no ownership proof in the system to check a claim against.
  Appointing *members*, by contrast, is the owner's own business.
- **Suspension revokes reads but keeps the place links.** Losing them would
  destroy the record of what was claimed, which is exactly what a dispute
  needs. And a business must keep at least one owner: appointing members is
  owner-only, so removing the last one would leave it manageable by nobody
  but an admin.

### The dashboard (#50)

Five read-only endpoints under `businesses/:businessId/analytics` —
`summary`, `daily`, `quests`, `places`, `proof`. **There is no place-id
parameter anywhere in them**, and that is the design: the place set is
derived from membership, so no request can widen its own scope. Keep it
that way.

- **Aggregates are counts of people, never lists of them.** A business
  learns that eleven people completed a quest at its address, not who.
  Cohorts below `MIN_REPORTABLE_COHORT` (5) come back flagged
  `cohortSuppressed`, because "1 visitor" plus one public feed post at the
  same place is two facts that together name somebody. Zero is *not*
  suppressed — it identifies nobody.
- **`proof` returns only what the author published**, on the feed's exact
  predicate: approved, `show_in_feed`, `visibility = 'visible'`, not
  deleted, not moderator-removed. It has to be exact, because `media_url`
  is an object key and `POST /media/sign` does **not** re-check who may see
  the submission — so the key *is* the access, and a looser predicate here
  hands over the bytes of proof its author kept private, with their name
  attached. Everything this endpoint returns is already visible to every
  signed-in user on the feed, which is the only reason it is defensible.
- **Starts come from `user_quests`, not submissions.** Someone who took a
  quest and never submitted is the whole signal; counting submissions would
  report perfect follow-through by hiding everyone who gave up.
  `completionRate` is **null, not zero**, when nobody has started — 0%
  would rank an untested quest as the worst performer.
- **`daily` fills empty days with `generate_series`.** Grouping the
  submissions alone omits quiet days, and a chart drawn from that connects
  last Tuesday to this Friday with a line that reads as steady traffic.
- Totals exclude anything the product treats as gone (deleted, `visibility
  = 'deleted'`, moderator-removed), so the dashboard cannot drift from the
  feed.

**Analytics is a separate entitlement from standing.** `businesses.status`
is a *moderation* state; `businesses.analytics_subscribed_at` is #50's
whitelist, NULL by default and never granted by merely existing.
`BusinessAnalyticsGuard` runs after `BusinessAccessGuard` (it reads the
membership that guard resolved, so it costs no extra query) and refuses with
**403 `ANALYTICS_NOT_SUBSCRIBED`** — 403 and not 404 here, the opposite of
the non-member case, because a member knows the business exists and hiding
the reason leaves an owner staring at an empty dashboard. The subscription
gates *only* the analytics routes: an unsubscribed member must still reach
`/businesses/me` and their own account. Suspending a business does not
cancel its subscription, and re-granting does not move
`analytics_subscribed_at`, so a billing period's start survives it.

**Where visitors come from** (`analytics/countries`) is self-declared
`profiles.country_code` — ISO 3166-1 alpha-2, optional, uppercase by CHECK,
set through `PATCH /profiles/me`. Deliberately **not** an FK to
`map_countries` (that is the game board — currently two rows — and a player
can be from anywhere), and deliberately **not** derived from CAMARA, which
would be inferring someone's residence from telecom data they gave us to
verify one quest. A visitor reaches a country bucket only with a declared
country **and** `analytics_consent_at`: completing a quest at a place is not
consent to be counted by its owner. The response carries `visitors`,
`disclosed` and `undisclosed` separately, and sub-threshold buckets collapse
into `suppressedCountries`/`suppressedVisitors` rather than vanishing —
because "Lebanon 100%" over five disclosed visitors when forty came would be
read as all of the traffic instead of an eighth of it.

The join path (`business_places` → `quest_destinations.place_id` →
`user_quests.quest_id` → `submissions.user_quest_id`) is already covered by
existing indexes; no new ones were added, and none are needed.

### The two client surfaces

**In the app**, a business is an ordinary player. The only difference is a
card on their *own* profile (`business_card.dart`) naming the business and
linking to the dashboard — nothing for anyone else, nothing on another
person's profile, and nothing while the read is loading or failed, because
the card is an addition to somebody's page rather than the page.

**The dashboard is `apps/business_web`**, a separate Flutter web app served
at `admin.bsheel.app/business`. It is *not* a route inside `admin_web`, and
that is deliberate: `SEC-027` in `admin_router.dart` bounces every signed-in
non-admin to the login gate, and a business member is an ordinary user with
no admin role — so putting it there would mean carving an exception into
that control. Same origin means no `CORS_ORIGINS` change is needed (an
origin is scheme + host + port), and the token namespace is
`bsheel.business` so an admin and a business owner in one browser cannot
evict each other's session. `docs/DEPLOYMENT.md` has the build and serving
requirements.

The dashboard is not an authority boundary — the API refuses a non-member
with a 404 whatever the client does — so its job is to *explain*: a
suspension, an unsubscribed account and a missing `DASHBOARD_URL` are three
separate messages because each has a different fix, and every section loads
and fails on its own so one endpoint cannot blank the other five.

Three client rules worth keeping. The proof wall **accumulates pages**
through the keyset cursor and says "that is all N posts" when the cursor
comes back null — a single-page read hid a business's own content behind
nothing. The quest filter runs on the client over rows already fetched,
which is only honest because the fetch asks for the server's cap of 100
*and* the section says so when it hit it; a client-side filter over a
partial list would answer "no quests match" about quests it never received.
(The places filter needs no such warning — that endpoint returns every
place the business owns.)

And the chart draws **explicit pixel heights measured from its own box**,
never `FractionallySizedBox`. A Row does not constrain its children on the
cross axis, so a fractional box inside one is handed an infinite height and
throws — which crashed the chart for any business that actually had data,
while every test passed empty point lists and the web bundle compiled
happily. `daily` also returns the **window it drew** alongside the points;
the chart labels those dates rather than deriving "today" itself, which
disagrees by a day for anyone west of UTC.

**Setting one up:** `npm run business:provision` (in `backend/`) does all
four steps through the audited admin endpoints — create, claim places, add
the owner, grant the subscription. Dry run by default. The fourth step is
the one people forget, and without it the owner signs in to
`ANALYTICS_NOT_SUBSCRIBED` with nothing pointing at the cause.

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
