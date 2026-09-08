import 'package:app_repositories/app_repositories.dart';

import 'backend_config.dart';

/// Owns the admin app's single API transport and repository graph.
abstract final class AppBackend {
  static ApiRepositoryBundle? _bundle;

  static ApiRepositoryBundle get repositories =>
      _bundle ?? (throw StateError('AppBackend.initialize() was not called.'));

  static Future<void> initialize() async {
    if (_bundle != null) return;
    BackendConfig.validate();

    final bundle = ApiRepositoryBundle(
      baseUrl: BackendConfig.apiUri,
      tokenStore: const SecureApiTokenStore(namespace: 'bsheel.admin'),
    );
    await bundle.initialize();
    _bundle = bundle;
  }

  static void close() {
    _bundle?.close();
    _bundle = null;
  }
}
