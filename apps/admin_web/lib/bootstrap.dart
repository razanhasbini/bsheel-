import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:app_core/app_core.dart' show AppLogger;
import 'core/config/env.dart';
import 'core/backend/backend_config.dart';
import 'core/backend/admin_nest_backend.dart';

Future<void> bootstrap() async {
  if (BackendConfig.usesNest) {
    await AdminNestBackend.initialize();
    AppLogger.info('[Bootstrap] Nest backend initialized successfully');
    return;
  }

  Env.assertConfigured();
  try {
    await Supabase.initialize(
      url: Env.supabaseUrl,
      anonKey: Env.supabaseAnonKey,
      authOptions: FlutterAuthClientOptions(
        autoRefreshToken: true,
        localStorage: kIsWeb
            ? SharedPreferencesLocalStorage(
                persistSessionKey: 'sb-4hoursonly-admin-web-auth-v2',
              )
            : null,
      ),
    );
    AppLogger.info('[Bootstrap] Supabase initialized successfully');
  } on AuthException catch (e) {
    // AuthException may be thrown during init when restoring an expired session.
    // This is expected — the auth state stream will handle the signed-out state.
    AppLogger.info('[Bootstrap] Auth session restore event: ${e.message}');
  }

  // Let auth state listeners handle session state through the normal stream
}
