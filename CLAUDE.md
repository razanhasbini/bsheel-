# CLAUDE.md — Bit Sheel? App Context

> **Migration continuation:** Before doing any work, read
> [`CLAUDE_MIGRATION_MASTER.md`](CLAUDE_MIGRATION_MASTER.md) completely. It is
> the authoritative status, architecture, verification, remaining-work, and
> completion guide for the Supabase-to-NestJS migration. The legacy product
> rules below remain required behavior, but the migration master takes
> precedence for current implementation status and workflow.

## What This App Is

Bit Sheel? is a gamified quest app. Users get 3 random real-world challenges, pick one, complete it within a quest-specific timer set by admin, submit photo/video proof, earn XP, level up. Social feed, reactions, comments, follows, leaderboard.

## Architecture

- **Monorepo:** `apps/mobile_app` (Flutter iOS) + `apps/admin_web` (Flutter web dashboard)
- **Shared packages:** `app_core`, `app_models`, `app_repositories`, `shared_ui`, `supabase_contracts`
- **Backend:** Supabase (Postgres + Auth + Storage + Edge Functions)
- **Push:** Firebase Cloud Messaging v1 API via `supabase/functions/send-push/`
- **Media:** Cloudflare R2 via worker

## Policy

> Confirmed by Layth on 2026-09-01. The machine-level source of truth is
> `~\.claude\memory\policies.md`; this copy travels with the code.

- **Branch:** commit straight to `main`, or branch — your call. No branch protection.
- **Push:** allowed, anywhere, including `main`. **Never force-push** — the history carries a
  leaked credential (below) and a rewrite breaks every clone mid-rotation.
- **`publish-test` and `publish-store` are release levers, not working branches.** A push to
  `publish-test` ships to TestFlight; a push to `publish-store` submits to Apple for public
  review. Never push to either as a shortcut. Note that BOTH a GitHub workflow and
  `scripts/hooks/pre-push` are wired to those branches — if the hook is installed
  (`git config core.hooksPath scripts/hooks`) and Actions has minutes, one push ships twice
  and the two runs collide on the build number. Pick one mechanism.
- **Deploy:** `.github/workflows/deploy-server.yml`, automatically on push to `main`. It rsyncs
  `supabase/functions/`, applies any migration not already recorded in
  `public._applied_migrations`, and rebuilds the admin SPA. This is the only automated path
  backend code reaches production.
- **Server:** you may ssh in and work directly (alias `contabo`, keyed). Anything applied by hand
  must also be recorded in `public._applied_migrations` **by filename**, or the next CI deploy
  re-applies it.
- **Who runs it:** Claude ssh's in and does it. Don't hand Layth a command to paste.
- **Blast radius — this repo does NOT own the box.** `contabo` (169.58.16.247) hosts five other
  things behind ONE shared Caddy (`supabase-caddy`, owns :80/:443) on ONE docker network:
  `almokhtar.info` + `*.almokhtar.info`, `hood-api` (almokhtar's API **and the on-demand-TLS
  gatekeeper for the whole machine**), `opera.169-58-16-247.sslip.io` (Lancaster PMS demo) and
  `169-58-16-247.sslip.io` (youthelets). Ours are `api.bsheel.app` and `admin.bsheel.app`.
  - **Never `caddy reload`** — it breaks admin basic-auth. Commit `d98a91f` exists only to stop
    the deploy workflow doing it.
  - **`supabase-db` is shared** — almokhtar's production `hood` database is in the same Postgres.
    Always name the target database; never run a bare `psql` and assume.
  - After any server-side change, verify all six hostnames, not just bsheel's two.
- **Known compromised:** the live `service_role` JWT (exp 2036) was committed in `6520808` and
  removed from the tip on 2026-09-01. **It is still in git history — treat it as compromised
  until `JWT_SECRET` is rotated.** See `docs/security/SECRET_ROTATION_RUNBOOK.md`.

## Key Rules

- **Never hardcode DB strings.** Import from `packages/supabase_contracts/lib/` (Tables, Columns, Statuses, RpcNames)
- **Models live in** `packages/app_models/lib/`
- **Repositories live in** `packages/app_repositories/lib/`
- **Use `withAlpha()` not `withOpacity()`** — withOpacity is deprecated
- **Never hardcode colours.** Mobile: every colour comes from `QuestColors` (+ `QuestSpacing`, `QuestTypography`) in `packages/app_core/lib/theme/` — the single source of truth; reskin the app by editing those three files only. Admin web: use `BsheelColors`/`BsheelType`/`BsheelRadii` from `apps/admin_web/lib/core/theme/bsheel_design.dart`. A truly one-off decorative colour (pixel art, scrim gradient stops) is allowed only as a private `static const` in its own file with a `// Screen-specific colour — not a theme token.` comment.
- **Theme:** Light Arcade Pop ONLY (`QuestTheme.light`, wired directly in `app.dart`). Cream bg (#FFF9EE), ink outlines + chunky drop shadows (#1A1330), accents = violet (#6B3BFF), coral (#FF5A6E), gold (#FFC224), green (#17C27B), sky (#4CC9F0). The app forces `ThemeMode.light`; there is NO dark theme anywhere in the codebase (removed 2026-07). The dark-looking `QuestColors.dark*` / `textPrimary` tokens are "ink panel" colours used *inside* the light design (splash, video overlays, arcade cards) — not a dark mode.
- **Prefer the context helpers** `QuestColors.bg/cardBg/text/textDim(context)` etc. in widgets — they exist so a future multi-theme setup can be reintroduced without touching call sites.
- **ALL CAPS** for labels/headers, normal case for body text

## Submission Review Flow

> **IMPORTANT:** Keep this section and the matching section in `README.md` in sync when making changes.

### State Machine

```
SUBMITTED → PENDING REVIEW
  ├── APPROVED → ACCEPTED QUESTS section, XP awarded
  └── REJECTED → REJECTED section (blue "APPEAL" badge)
        ├── User appeals → IN REVIEW section (yellow "APPEALED" badge)
        │     ├── APPROVED → ACCEPTED QUESTS section
        │     └── RE-REJECTED → REJECTED section (red "REJECTED x2", final)
        └── User doesn't appeal → stays in REJECTED section
```

### Where this surfaces in the UI

> The "Arcade Pop" rebuild replaced the old sectioned home page. There are
> **no** IN REVIEW / REJECTED / ACCEPTED QUESTS / COMPLETED TODAY / EXPIRED
> sections any more, and the `rejectedQuests` / `reRejectedQuests` /
> `appealedQuests` / `submittedQuests` filter variables no longer exist
> anywhere in the codebase. Don't go looking for them.

**Home** (`home_page.dart`, `build()` ≈ lines 145-486) renders, in order:
name + bell → headline → two all-time stat tiles (from `profiles.xp` /
`profiles.quests_completed`) → Quest-of-the-Day ticket → hero zone →
RECENT QUESTS → weekly XP meter → friend activity → streak card.

The **hero zone** is the only status-driven part:

| Condition | Widget |
|---|---|
| `account_status` is suspended/banned | `_LockedCard` (and the QOTD ticket is hidden entirely) |
| any `user_quest.status == submitted` | `_PendingReviewCard` — shown *above* whatever follows; tap opens the quest, or a list dialog when there's more than one |
| active quest, `status == assigned`, not past `expires_at` | `_ActiveQuestHero` with live countdown |
| active quest past `expires_at` | `_TimeOverCard` |
| no active quest | `_SlotMachineZone` (GENERATE A QUEST) |

**RECENT QUESTS** lists the 5 most recent user_quests with a status dot and
badge — ACCEPTED / REJECTED / TIMED OUT / PENDING / ACTIVE — but the rows are
display-only. SEE MORE opens `quest_history_page.dart`, which groups by
COMPLETED / REJECTED / EXPIRED / IN REVIEW; its rows deep-link to the **quest
detail** page, not the submission.

### How a user actually reaches the appeal button

`submission_status_page.dart` owns the whole rejection/appeal UX (rejection
reasons, REQUEST REVALIDATION, the "no further appeals" notice). Only three
things route to it:

1. **Tapping a rejection/approval notification** — the primary path
   (`notifications_page.dart`, for `submission_approved`,
   `submission_rejected`, `new_submission`, `appeal_submitted`).
2. **The Quest-of-the-Day ticket stub** on home, when that attempt was a
   first-time rejection (`home_extras.dart` — `canAppeal`).
3. **Immediately after submitting proof** (`submit_proof_page.dart`).

So: if push notifications are broken, users effectively cannot find the
appeal flow. Worth remembering before removing a notification type.

### Edge cases (still true)

- Appealed and pending → violet "APPEAL SUBMITTED" panel with the note.
- Re-rejected after appeal → "You already appealed this submission. No
  further appeals allowed." The rejection-reasons block and the
  REQUEST REVALIDATION button are hidden once `appealed == true`.
- Appeal is gated server-side too: `appeal_submission` re-checks ownership,
  `status == 'rejected'`, `appealed == false`, and (since 0140) that the
  submission isn't soft-deleted.
- Double-tap on send is guarded client-side by `_appealing` (ARC-003).

### Key Files to Edit Together

- `submission_status_page.dart` — detail view, appeal button, re-rejection message
- `home_page.dart` — hero zone + RECENT QUESTS rendering
- `quest_history_page.dart` — COMPLETED / REJECTED / EXPIRED / IN REVIEW grouping
- `notifications_page.dart` — the routing that makes the appeal reachable
- `supabase/functions_canonical/appeal_submission.sql` — canonical RPC body
  (live since `0149`; the frozen `applied/0052` and `applied/0119` are history)
- `statuses.dart` — status constants
- **This file + README.md** — update docs when flow changes

## Database Tables

profiles, quests, user_quests, submissions, reactions, notifications, admins, comments, follows

## Migrations (self-hosted — NOT Supabase cloud)

Backend runs on our own server (api.bsheel.app). Migrations are applied by
`scripts/server-deploy.sh` (triggered by the "Deploy to server" workflow on
push to main), tracked **by filename** in `public._applied_migrations`.

- `supabase/migrations/` top level = pending/recent migrations only.
- `supabase/migrations/applied/` = frozen already-applied history (146
  files). NEVER rename, renumber, or re-apply anything in there.
- New migration = next number at the TOP LEVEL (`0150_...`), push to main.
- **Wrap every migration in `BEGIN; ... COMMIT;`** — the deploy runs psql
  without `--single-transaction`, so an un-wrapped failure half-applies AND
  leaves the file unrecorded, replaying it on the next deploy.
- **Reissuing an existing RPC is the most dangerous edit in this repo.**
  `CREATE OR REPLACE` happily accepts a body that has silently lost a guard
  added by a *later* migration than the one you copied from. This has caused
  three separate production outages — see the table in
  `supabase/migrations/README.md` before touching one.
- Full index + fresh-environment rebuild procedure:
  `supabase/migrations/README.md` + `scripts/dump_schema_baseline.sh`.
- Canonical bodies of frequently-redefined RPCs: `supabase/functions_canonical/`.

## State Management

Riverpod providers in each feature's `data/` folder:
- `activeQuestProvider`, `questHistoryProvider`
- `feedProvider`, `feedPostDetailsProvider`
- `currentProfileProvider`
- `notificationsProvider`, `unreadCountProvider`
- `userSubmissionsProvider`

## Routing

GoRouter with `BottomNavShell` (5 tabs: HOME / FEED / COLLAB / RANK / YOU). Routes in `core/router/route_names.dart`.

## Localization

English (en) + Lebanese Arabizi (lb). Strings in `l10n/app_localizations.dart`. Toggle via `localeProvider` in settings. (The old `l10n/quest_translations.dart` table was unused and removed 2026-07 — quest text comes from the DB.)

## Admin

- Web dashboard at `apps/admin_web/` — gated by `admins` table role check
- Mobile admin route exists but gated by `isAdminProvider`
- Only users in `admins` table can access admin features

## Sensitive Files (not in git)

- `ios/Runner/GoogleService-Info.plist` — Firebase config
- `ios/AuthKey_V5L2554CT7.p8` — APNs key
- Both in `.gitignore`

## Shipping

Two skills do the whole job. Say what you want and Claude runs the runbook:

| Say | Skill | Result |
|---|---|---|
| "push to testflight" | `.claude/skills/ship-testflight` | build → upload → TestFlight groups |
| "deploy live" / "push to the store" | `.claude/skills/ship-appstore` | build → upload → submit for Apple review |

Both build **on this Mac** — no GitHub Actions, no CI minutes. `docs/PUBLISHING.md` has the
full story, including the `publish-test` / `publish-store` branches that do the same thing in
CI when the account's Actions billing allows it.

Release builds compile in `apps/mobile_app/dart_defines.release.json`. A build made without it
signs and installs perfectly and cannot reach the API, so `scripts/ios_release.sh` refuses to
run when it is missing. That file is the single source of truth — the command below is kept in
step with it, not the other way round.

## Quick Commands

```bash
# Analyze
flutter analyze apps/mobile_app/lib

# Build IPA — release/store builds MUST include --obfuscate so the
# compiled Dart code in the IPA isn't trivially reverse-readable. The
# symbol map lands in build/app/outputs/app-symbols/release/ — keep
# it for crash deobfuscation, do NOT ship it.
# (M17, 2026-05-17 audit. Drop --obfuscate for local debug/profile.)
cd apps/mobile_app && flutter build ipa \
  --obfuscate --split-debug-info=build/app/outputs/app-symbols/release \
  --dart-define=SUPABASE_URL=https://api.bsheel.app \
  "--dart-define=SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJyb2xlIjoiYW5vbiIsImlzcyI6InN1cGFiYXNlIiwiaWF0IjoxNzg0MDIzMjcyLCJleHAiOjIwOTkzODMyNzJ9.0HGp8OvHc0peJcxlditiKrzFpz442iITeFQhyA_Vu7s" \
  --dart-define=MIXPANEL_TOKEN=55b3f6acdaa760fc8a637a591692ce5c \
  "--dart-define=GOOGLE_IOS_CLIENT_ID=854270137441-vhigjmc9rgr2jog9u0d091pb2e02ohi1.apps.googleusercontent.com" \
  "--dart-define=GOOGLE_WEB_CLIENT_ID=854270137441-t7fnj89odpeut06588o1dee181n3bdsr.apps.googleusercontent.com"

# Run admin web
cd apps/admin_web && flutter run -d chrome

# Deploy edge functions + migrations + admin web (self-hosted)
# Just push to main — .github/workflows/deploy-server.yml rsyncs
# supabase/functions/ + pending migrations to the Contabo box and
# restarts the functions runtime. No Supabase-cloud CLI deploy.

# Generate app icons
cd apps/mobile_app && dart run flutter_launcher_icons
```
