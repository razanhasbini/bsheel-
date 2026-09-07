import 'package:app_repositories/nest_api_repositories.dart';

import 'backend_config.dart';

/// Owns the admin app's single Nest transport and repository graph.
abstract final class AdminNestBackend {
  static NestRepositoryBundle? _bundle;

  static NestRepositoryBundle get repositories =>
      _bundle ??
      (throw StateError('AdminNestBackend.initialize() was not called.'));

  static Future<void> initialize() async {
    BackendConfig.validate();
    if (!BackendConfig.usesNest || _bundle != null) return;

    final bundle = NestRepositoryBundle(
      baseUrl: BackendConfig.nestApiUri,
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
