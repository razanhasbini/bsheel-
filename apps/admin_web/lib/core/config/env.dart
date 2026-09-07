import 'package:app_core/app_core.dart';

/// Environment configuration for the admin web app.
/// Values must be injected at build time via --dart-define:
///   SUPABASE_URL=https://api.bsheel.app
///   SUPABASE_ANON_KEY=your-anon-key
abstract final class Env {
  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: '',
  );
  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: '',
  );

  /// Call once at app startup to assert required env vars are set.
  static void assertConfigured() {
    final missing = <String>[];
    if (supabaseUrl.isEmpty) {
      missing.add('SUPABASE_URL');
    }
    if (supabaseAnonKey.isEmpty) {
      missing.add('SUPABASE_ANON_KEY');
    }
    if (missing.isEmpty) {
      return;
    }

    final message =
        '[Env] Missing required --dart-define values: ${missing.join(', ')}. '
        'Pass them at build time before deploying admin_web.';
    AppLogger.warning(message);
    throw StateError(message);
  }
}
