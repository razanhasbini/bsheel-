import 'package:app_repositories/nest_api_repositories.dart';

import '../config/env.dart';
import 'backend_config.dart';

/// Owns the mobile app's single Nest transport, token store, and repositories.
///
/// The explicit lifecycle prevents feature providers from creating their own
/// HTTP clients or racing refresh-token rotation.
abstract final class MobileNestBackend {
  static NestRepositoryBundle? _bundle;

  static NestRepositoryBundle get repositories =>
      _bundle ??
      (throw StateError('MobileNestBackend.initialize() was not called.'));

  static Future<void> initialize() async {
    BackendConfig.validate();
    if (!BackendConfig.usesNest || _bundle != null) return;

    final bundle = NestRepositoryBundle(
      baseUrl: BackendConfig.nestApiUri,
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
