import 'package:app_repositories/app_repositories.dart';

import '../config/env.dart';
import 'backend_config.dart';

/// Owns the mobile app's single API transport, token store, and repositories.
///
/// The explicit lifecycle prevents feature providers from creating their own
/// HTTP clients or racing refresh-token rotation. Every repository provider
/// resolves through [repositories] so there is exactly one client per app.
abstract final class AppBackend {
  static ApiRepositoryBundle? _bundle;

  static ApiRepositoryBundle get repositories =>
      _bundle ?? (throw StateError('AppBackend.initialize() was not called.'));

  static Future<void> initialize() async {
    if (_bundle != null) return;
    BackendConfig.validate();

    final bundle = ApiRepositoryBundle(
      baseUrl: BackendConfig.apiUri,
      tokenStore: const SecureApiTokenStore(namespace: 'bsheel.mobile'),
      googleIosClientId: Env.googleIosClientId,
      googleWebClientId: Env.googleWebClientId,
    );
    await bundle.initialize();
    _bundle = bundle;
  }

  static void close() {
    _bundle?.close();
    _bundle = null;
  }
}
