# admin_web

The Bsheel admin dashboard: a Flutter web app for moderation and operations.

## Run it

```bash
flutter run -d chrome
```

Debug builds default to `http://127.0.0.1:3010/api/v1`. To point elsewhere:

```bash
flutter run -d chrome --dart-define=API_URL=https://api.bsheel.app/api/v1
```

Access requires an account with a row in `admins`. The API asserts the role on
every admin route; the dashboard only decides what to render.

## Surfaces

| Feature | What it does |
|---|---|
| `dashboard` | seven headline counters from one `/admin/stats` call |
| `moderation` | review queue with reviewer context, review detail, decision history |
| `appeals` | submissions pending a second review after an appeal |
| `users` | search, edit profile, XP, role, status, password reset, quest assignment, delete, export |
| `xp_management` | XP reconciliation — stored totals against what approved quests imply |
| `quest_management` | quest bank CRUD, bulk import, delete-all |
| `quest_injection` | bespoke quest for one user, plus targeted notifications |
| `quest_of_day` | schedule the featured quest and its bonus |
| `announcements` | broadcast to every active user |
| `auto_notifications` | what the system has been sending, and the rules that send it |
| `feed_management` | approved posts, comment threads, remove from feed |
| `reports` | abuse reports and the resulting actions |
| `web_signups` / `web_quest_suggestions` | marketing-site intake |
| `settings` | runtime app config and feature flags |

## Conventions

- One backend, resolved through `AppBackend` in `lib/core/backend/`. Never
  build an HTTP client or a repository in a page.
- Admin reads and writes go through `ApiAdminRepository` and the domain
  adapters, not raw HTTP.
- Colours, type and radii come from `BsheelColors` / `BsheelType` /
  `BsheelRadii` in `lib/core/theme/bsheel_design.dart`.
- Destructive actions confirm first, and the API records them in
  `admin_audit_log` with the actor and the previous value.

## Test

```bash
flutter analyze     # must be zero issues
flutter test
```

## Build

```bash
flutter build web --dart-define=API_URL=https://api.bsheel.app/api/v1
# → build/web
```

The bundle is public, so it must carry no secrets. Put an outer access control
layer in front of it anyway — see `docs/DEPLOYMENT.md`.
