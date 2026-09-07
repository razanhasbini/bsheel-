# Bsheel

> **Backend migration in progress:** this standalone workspace preserves the existing Flutter applications byte-for-byte while their Supabase backend is replaced by the production NestJS modular monolith in `backend/`. The retained `supabase/` and `cloudflare/` trees are parity references and are not the destination stack. See [`docs/migration/PARITY_LEDGER.md`](docs/migration/PARITY_LEDGER.md) before changing or removing a legacy path.

Backend quick start:

```bash
cp backend/.env.example backend/.env
docker compose up --build
# API: http://localhost:8080/api/v1
# OpenAPI: http://localhost:8080/docs
```

The existing product documentation follows so behavior does not disappear during the rewrite.

# Legacy product reference

A gamified quest app where users complete real-world challenges, submit proof, earn XP, level up, and compete on leaderboards. Built with Flutter, Supabase, and Firebase.

**Admin Dashboard:** https://admin.bsheel.app
## Features

- **Quest System** — AI-generated quests across 5 categories (fitness, creativity, social, learning, adventure). Users pick from 3 options, complete within a per-quest timer set by admin, submit photo/video proof
- **XP & Leveling** — earn XP per quest, level up with class progression (Scout → Warrior → Mage → Champion → Legend)
- **Social Feed** — Instagram-style feed of completed quests with upvote/downvote voting
- **Comments & Follows** — comment on posts, follow other users
- **Leaderboard** — global ranking by XP
- **Push Notifications** — real-time FCM push via Supabase Edge Functions
- **Admin Dashboard** — web panel for moderating submissions, managing quests/users, sending announcements
- **Localization** — English + Lebanese Arabizi (internet language)
- **Onboarding** — 4-page walkthrough for new users
- **Badges** — 7 achievement badges with real unlock logic
- **Level Up Celebration** — pixel confetti animation overlay

## Tech Stack

| Layer | Tech |
|-------|------|
| Mobile App | Flutter (iOS) |
| Admin Dashboard | Flutter Web |
| Backend | Supabase (Postgres, Auth, Storage, Edge Functions) |
| Push Notifications | Firebase Cloud Messaging (FCM v1 API) |
| State Management | Riverpod |
| Routing | GoRouter |
| Media Storage | Cloudflare R2 via Workers |

## Monorepo Structure

```
4hoursonly/
├── apps/
│   ├── mobile_app/          # User-facing iOS app (Flutter)
│   └── admin_web/           # Admin dashboard (Flutter web, served at admin.bsheel.app)
├── packages/
│   ├── app_core/            # Design tokens (QuestColors/Spacing/Typography), utils, logger
│   ├── app_models/          # Data models (Profile, Quest, Submission, Comment, ...)
│   ├── app_repositories/    # Repository interfaces + Supabase implementations
│   ├── shared_ui/           # Reusable widgets (Arcade primitives, PixelAvatar, states)
│   └── supabase_contracts/  # DB table names, columns, statuses, RPC names
├── supabase/
│   ├── migrations/          # SQL migrations — see migrations/README.md for the index
│   ├── functions/           # 10 edge functions (send-push, telegram-*, admin_manage_user, ...)
│   ├── functions_canonical/ # Canonical bodies of frequently-redefined RPCs
│   ├── seed/                # Quest content + demo seeds
│   └── tests/               # SQL smoke tests (RLS, XP idempotency, pentest lockdown)
├── docs/
│   ├── architecture.md      # Clean-architecture dependency graph
│   ├── database_contract.md # Rules for schema changes
│   ├── api/                 # Postman collection + auth test matrix
│   ├── security/            # Rotation runbook + audit reports
│   └── deep_links/          # AASA / assetlinks setup guide
├── scripts/                 # bootstrap, analyze/test (melos), schema drift checks, server deploy
├── cloudflare/              # R2 media upload/cleanup workers
└── .github/workflows/       # CI (analyze+test), format, deploy-server
```

## Database Schema

| Table | Purpose |
|-------|---------|
| profiles | User accounts (username, XP, level, avatar) |
| quests | Quest library (title, description, category, difficulty, XP reward, duration_hours) |
| user_quests | Quest assignments (status, expires_at, completed_at) |
| submissions | Proof submissions (media, caption, review status) |
| reactions | Post votes (upvote/downvote) |
| notifications | In-app notifications |
| admins | Admin role assignments (super_admin, moderator) |
| comments | Post comments |
| follows | Social graph (follower/following) |

## Submission Review Flow & Quest Lifecycle

> **IMPORTANT:** If any future changes affect submission statuses, appeal logic, or home page sections, update this section and the matching section in `CLAUDE.md`.

### Statuses

| Entity | Status | Meaning |
|--------|--------|---------|
| `user_quests` | `assigned` | Quest active, timer running |
| `user_quests` | `submitted` | Proof submitted, awaiting review |
| `user_quests` | `approved` | Admin approved, XP awarded |
| `user_quests` | `rejected` | Admin rejected |
| `user_quests` | `expired` | Timer ran out |
| `submissions` | `pending` | Awaiting moderator decision |
| `submissions` | `approved` | Moderator approved |
| `submissions` | `rejected` | Moderator rejected |
| `submissions` | `appealed` (bool) | User has used their one appeal |

### State Machine

```
User submits proof
    ↓
user_quest.status = submitted
submission.status = pending
submission.appealed = false
    ↓
┌─── Admin reviews ───┐
│                      │
▼                      ▼
APPROVED              REJECTED
user_quest = approved  user_quest = rejected
submission = approved  submission = rejected
XP awarded             Notification sent
    │                      │
    │              User taps APPEAL
    │              (only if appealed = false)
    │                      │
    │                      ▼
    │              appeal_submission RPC:
    │                submission.status = pending
    │                submission.appealed = true
    │                user_quest.status = submitted
    │                review fields cleared
    │                Admin notified
    │                      │
    │              ┌── Admin re-reviews ──┐
    │              │                      │
    │              ▼                      ▼
    │          APPROVED              RE-REJECTED
    │          (same as above)       user_quest = rejected
    │                                submission = rejected
    │                                submission.appealed = true (already)
    │                                Notification sent
    │                                NO MORE APPEALS
    ▼
Shows in ACCEPTED QUESTS section
```

### Where this surfaces in the app

> The "Arcade Pop" rebuild removed the old sectioned home page. There are no
> ACTIVE QUEST / COMPLETED TODAY / IN REVIEW / REJECTED / ACCEPTED QUESTS /
> EXPIRED QUESTS sections, and the filter variables that used to drive them
> no longer exist in the codebase.

**Home** renders: name + bell → headline → all-time stat tiles → Quest of the
Day → hero zone → RECENT QUESTS → weekly XP meter → friend activity → streak
card. Only the hero zone is status-driven:

| Condition | What renders |
|---|---|
| Account suspended/banned | Locked card; the Quest-of-the-Day ticket is hidden |
| Any `user_quest.status == submitted` | Pending-review card, above whatever follows |
| Active quest, `assigned`, before `expires_at` | Active-quest hero with live countdown |
| Active quest past `expires_at` | "TIME OVER" card |
| No active quest | Slot machine / GENERATE A QUEST |

**RECENT QUESTS** shows the 5 most recent quests with an ACCEPTED / REJECTED /
TIMED OUT / PENDING / ACTIVE badge, display-only. SEE MORE opens the quest
history page (grouped COMPLETED / REJECTED / EXPIRED / IN REVIEW), whose rows
open the **quest detail** page.

### Reaching the appeal flow

The rejection + appeal UI lives entirely on the submission status page. It is
reachable from exactly three places:

| Entry point | When |
|---|---|
| Tapping a notification | `submission_approved`, `submission_rejected`, `new_submission`, `appeal_submitted` — the primary path |
| Quest-of-the-Day ticket stub | That attempt was a first-time rejection |
| Right after submitting proof | Redirect from the submit page |

Because the notification is the main route in, breaking push delivery
effectively hides the appeal flow.

### Edge Cases

| Case | Behavior |
|------|----------|
| Rejected, not yet appealed | Rejection reasons (up to 3, parsed from `review_note`) + REQUEST REVALIDATION button |
| Appeal submitted, pending re-review | Violet "APPEAL SUBMITTED" panel showing the appeal note |
| Re-rejected after appeal | "You already appealed this submission. No further appeals allowed." Reasons + appeal button hidden |
| Appeal on a soft-deleted submission | Rejected server-side since `0140` ("Cannot appeal a deleted submission") |
| Double-tap on send | Guarded client-side by `_appealing` (ARC-003) |

### Key Files

| File | Role |
|------|------|
| `apps/mobile_app/lib/features/submissions/presentation/pages/submission_status_page.dart` | Rejection reasons, appeal button, re-rejection notice |
| `apps/mobile_app/lib/features/quests/presentation/pages/home_page.dart` | Hero zone + RECENT QUESTS |
| `apps/mobile_app/lib/features/quests/presentation/pages/quest_history_page.dart` | COMPLETED / REJECTED / EXPIRED / IN REVIEW grouping |
| `apps/mobile_app/lib/features/notifications/presentation/pages/notifications_page.dart` | Routing that makes the appeal reachable |
| `supabase/functions_canonical/appeal_submission.sql` | Canonical `appeal_submission` body (live since `0149`) |
| `supabase/migrations/applied/0004_submissions.sql` | Submission triggers (auto XP, auto notifications) |
| `packages/supabase_contracts/lib/statuses.dart` | Status constants |

## Setup

```bash
# One-time: bootstrap the whole monorepo (installs melos 6.1.0 + pub get everywhere)
./scripts/bootstrap.sh

# Analyze / test every package
melos run analyze
melos run test

# Run mobile app
cd apps/mobile_app && flutter run

# Run admin web
cd apps/admin_web && flutter run -d chrome

# Build IPA (see CLAUDE.md for the full production command with --dart-define flags)
cd apps/mobile_app && flutter build ipa
```

## Environment

The app reads Supabase credentials from `lib/core/config/env.dart`. Firebase config lives in `ios/Runner/GoogleService-Info.plist` (not tracked in git).

## Edge Functions & Migrations (self-hosted)

The backend is a self-hosted Supabase stack on our own server
(`api.bsheel.app`) — there is no Supabase-cloud project. Deploys happen
automatically on push to `main` via `.github/workflows/deploy-server.yml`:
edge functions are rsynced to the box, pending migrations in
`supabase/migrations/` are applied by `scripts/server-deploy.sh` (tracked by
filename in `public._applied_migrations`), and the admin web build is
published to `admin.bsheel.app`. See `supabase/migrations/README.md` for the
migration workflow.

## Build & Release

### App identifiers

| Platform | Field | Value |
|---|---|---|
| iOS | Bundle ID | `com.questapp.mobileApp` |
| iOS | Team ID | `JMDKX9TYX6` |
| iOS | Display Name | `BSHEEL` |
| Android | Package name | `com.questapp.mobile_app` |
| Android | App name | `BSHEEL` |
| Both | Version (pubspec) | `1.1.4+44` — bump the `+build` on every store upload |

### Public tokens (safe in source)

These are client-side tokens by design. They're passed via `--dart-define` on every build and are safe to keep in README / committed scripts. **Never commit the Supabase service-role key or Mixpanel secret key — those are different.**

| Name | Value |
|---|---|
| `SUPABASE_URL` | `https://api.bsheel.app` |
| `SUPABASE_ANON_KEY` (anon JWT) | `eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJyb2xlIjoiYW5vbiIsImlzcyI6InN1cGFiYXNlIiwiaWF0IjoxNzg0MDIzMjcyLCJleHAiOjIwOTkzODMyNzJ9.0HGp8OvHc0peJcxlditiKrzFpz442iITeFQhyA_Vu7s` |
| `MIXPANEL_TOKEN` | `55b3f6acdaa760fc8a637a591692ce5c` |

Canonical references: `apps/mobile_app/.env` (tracked locally), `apps/mobile_app/lib/core/config/env.dart` (reads the dart-defines).

### Android signing

Active keystore (production):

| Field | Value |
|---|---|
| File | `apps/mobile_app/android/app/bitsheel-release.jks` |
| Alias | `bitsheel` |
| Config | `apps/mobile_app/android/key.properties` (contains passwords — **not tracked in git**) |
| SHA-1 | `E0:AE:AF:CF:EF:06:CB:E3:01:D9:AB:92:FB:44:99:2E:A7:2F:38:C4` |
| SHA-256 | `BF:50:D4:7F:4E:D3:1D:83:1A:B0:31:E5:79:89:4D:04:B0:3B:6A:34:C2:CB:32:0A:71:76:2C:7F:32:BC:C5:A2` |
| Signature algorithm | SHA256withRSA |

Legacy (pre-rebrand, retained for history): `apps/mobile_app/android/keystore/quest-app-release.jks`.

### Google Play package-name registration

- Registration token (ADI): `C4ZGJR5K4LP5IAAAAAAAAAAAAA`
- File location on upload: `apps/mobile_app/android/app/src/main/assets/adi-registration.properties`
- Ownership proof flow: pick the SHA-256 fingerprint above → upload a release APK built with that key → Google auto-registers.

### Build commands

```bash
# ── iOS IPA (App Store / TestFlight) ─────────────────────────────
cd apps/mobile_app && flutter build ipa \
  --dart-define=SUPABASE_URL=https://api.bsheel.app \
  "--dart-define=SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJyb2xlIjoiYW5vbiIsImlzcyI6InN1cGFiYXNlIiwiaWF0IjoxNzg0MDIzMjcyLCJleHAiOjIwOTkzODMyNzJ9.0HGp8OvHc0peJcxlditiKrzFpz442iITeFQhyA_Vu7s" \
  --dart-define=MIXPANEL_TOKEN=55b3f6acdaa760fc8a637a591692ce5c
# → build/ios/ipa/BSHEEL.ipa

# ── Android App Bundle (Google Play Production) ──────────────────
cd apps/mobile_app && flutter build appbundle --release \
  --dart-define=SUPABASE_URL=https://api.bsheel.app \
  "--dart-define=SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJyb2xlIjoiYW5vbiIsImlzcyI6InN1cGFiYXNlIiwiaWF0IjoxNzg0MDIzMjcyLCJleHAiOjIwOTkzODMyNzJ9.0HGp8OvHc0peJcxlditiKrzFpz442iITeFQhyA_Vu7s" \
  --dart-define=MIXPANEL_TOKEN=55b3f6acdaa760fc8a637a591692ce5c
# → build/app/outputs/bundle/release/app-release.aab

# ── Android APK (sideload / Play ownership proof only) ───────────
cd apps/mobile_app && flutter build apk --release \
  --dart-define=SUPABASE_URL=https://api.bsheel.app \
  "--dart-define=SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJyb2xlIjoiYW5vbiIsImlzcyI6InN1cGFiYXNlIiwiaWF0IjoxNzg0MDIzMjcyLCJleHAiOjIwOTkzODMyNzJ9.0HGp8OvHc0peJcxlditiKrzFpz442iITeFQhyA_Vu7s" \
  --dart-define=MIXPANEL_TOKEN=55b3f6acdaa760fc8a637a591692ce5c
# → build/app/outputs/flutter-apk/app-release.apk

# ── Admin web ────────────────────────────────────────────────────
cd apps/admin_web && flutter run -d chrome

# ── Deploy backend (edge functions + migrations + admin web) ─────
git push origin main   # deploy-server.yml handles the rest (self-hosted)
```

IPA upload: either drag `BSHEEL.ipa` into **Transporter.app**, or

```bash
xcrun altool --upload-app --type ios \
  -f build/ios/ipa/BSHEEL.ipa \
  --apiKey <KEY_ID> --apiIssuer <ISSUER_ID>
```

### Sensitive files (NEVER commit — all in `.gitignore`)

| File | What it is | Needed for |
|---|---|---|
| `apps/mobile_app/.env` | Supabase + Mixpanel tokens (convenience copy) | local reference |
| `apps/mobile_app/android/key.properties` | Android keystore passwords | release builds |
| `apps/mobile_app/android/app/bitsheel-release.jks` | Android signing key | release builds / Play ownership |
| `apps/mobile_app/ios/Runner/GoogleService-Info.plist` | Firebase iOS config | push notifications |
| `apps/mobile_app/ios/AuthKey_V5L2554CT7.p8` | APNs auth key | FCM push on iOS |
| Supabase **service-role** key | (stored in Supabase project settings only) | edge functions |
| Firebase service-account JSON | (stored in Supabase project secrets only) | FCM v1 API |

If any of these get lost, the app can't ship — back them up outside the repo.

### Admin dashboard

Deployed at **https://admin.bsheel.app** — gated by rows in the `admins` table.

