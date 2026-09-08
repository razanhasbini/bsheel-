# app_repositories

The boundary between the applications and the Bsheel API: one abstract contract
per domain, and one HTTP implementation of each.

## Structure

```text
<domain>/
  <domain>_repository.dart       abstract contract — what features depend on
  api_<domain>_repository.dart   HTTP implementation
api/
  api_client.dart                transport: envelope, timeouts, refresh rotation
  api_repository_bundle.dart     one bundle: one client, one token store
  secure_api_token_store.dart    atomic secure access/refresh storage
auth/
  auth_models.dart               AuthUser, AuthSession, AuthState, AuthResult
media/                           signed-URL helper and uploader
realtime/                        authenticated Socket.IO client
```

## Rules

- **Features depend on the abstract contract**, never on `Api*Repository`. The
  concrete type is wired only in each app's `AppBackend` composition root.
- **One bundle per app.** `ApiRepositoryBundle` owns a single `ApiClient` and a
  single token store. Two clients means two token stores racing to spend the
  same single-use refresh token — never construct one in a screen.
- **Contracts are plain Dart.** No type from a networking library may appear in
  an abstract repository's signature. The auth contract used to be typed in a
  vendor's session objects, which made the vendor impossible to remove; the
  types in `auth_models.dart` exist so that cannot happen again.
- **Adapters own response mapping**, including signing private media URLs, so
  a screen never sees a raw object key.
- **Every adapter method has a wire test** in
  `test/api_repository_contract_test.dart` asserting the exact path, query,
  body, envelope handling and model mapping — without a network.

## Testing

```bash
cd packages/app_repositories && flutter test
```

These are the Flutter-side contract tests. They must run in CI: they are the
only thing that catches a client and server disagreeing about a path or a
field name.
