# mobile_app

The user-facing Bsheel app: iOS and Android.

## Run it

```bash
flutter run
```

Debug builds default to `http://127.0.0.1:3010/api/v1`, so a local backend
(`docker compose up` from the repo root) needs no extra flags. To point
somewhere else:

```bash
flutter run --dart-define=API_URL=https://api.bsheel.app/api/v1
```

## Structure

```text
lib/
  main.dart              entry point; applies locale, runs the app
  bootstrap.dart         critical init (backend, splash flag) + deferred services
  app.dart               MaterialApp, theme, router
  core/
    backend/             AppBackend + BackendConfig — the composition root
    providers/           app-wide providers (auth session, profile, config)
    router/              GoRouter routes and guards
    services/            analytics, device tokens, sign-out, live activity
    security/            EXIF stripping, screenshot protection
  features/<feature>/
    data/                providers and datasources
    domain/              entities and use cases
    presentation/        pages, widgets, controllers
  shared/navigation/     BottomNavShell (HOME / FEED / COLLAB / RANK / YOU)
  l10n/                  English + Lebanese Arabizi
```

## Conventions

- One backend, resolved through `AppBackend`. Never build an HTTP client or a
  repository in a screen.
- Features depend on abstract repository contracts from `app_repositories`.
- A feature must not import another feature's `presentation/`.
- Colours, spacing and typography come from `QuestColors` / `QuestSpacing` /
  `QuestTypography` in `app_core`. Never hardcode a colour.
- Realtime events are an invalidation signal, not data: an event invalidates a
  provider, which refetches over HTTP.

## Test

```bash
flutter analyze     # must be zero issues
flutter test
```

The screenshot gallery is a dev utility and is skipped by default:

```bash
flutter test --dart-define=SCREENSHOTS=true
```

## Release

See `docs/PUBLISHING.md`. Release builds must pass
`--dart-define-from-file=dart_defines.release.json` and `--obfuscate`.
