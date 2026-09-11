import 'package:app_repositories/app_repositories.dart';

import 'backend_config.dart';

/// Owns this app's single API transport and repository graph.
///
/// The token namespace is `bsheel.business`, and that is load-bearing.
/// This app is served from the same origin as the admin console
/// (`/business` under it), so the two share the browser's storage — a
/// shared namespace would have one app's session overwrite the other's,
/// and an admin and a business owner using the same browser would
/// silently evict each other.
abstract final class AppBackend {
  static ApiRepositoryBundle? _bundle;

  static ApiRepositoryBundle get repositories =>
      _bundle ?? (throw StateError('AppBackend.initialize() was not called.'));

  static Future<void> initialize() async {
    if (_bundle != null) return;
    BackendConfig.validate();

    final bundle = ApiRepositoryBundle(
      baseUrl: BackendConfig.apiUri,
      tokenStore: const SecureApiTokenStore(namespace: 'bsheel.business'),
    );
    await bundle.initialize();
    _bundle = bundle;
  }

  static void close() {
    _bundle?.close();
    _bundle = null;
  }
}
