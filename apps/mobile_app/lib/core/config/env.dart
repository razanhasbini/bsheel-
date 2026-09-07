import 'package:app_core/app_core.dart';

/// Environment configuration for client-safe values only.
/// This app intentionally reads only public Supabase settings.
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
  /// F-010 (pentest 2026-05-20): two Mixpanel tokens were observed in
  /// the AOT snapshot. The orphan token is a default embedded by the
  /// `mixpanel_flutter` plugin's example — NOT one our code uses.
  /// This constant is the only path through which our app initializes
  /// Mixpanel, and it must be sourced from the build command:
  ///   --dart-define=MIXPANEL_TOKEN=<prod_token>
  /// See CLAUDE.md → "Build IPA" for the production command. Builds
  /// without this define get an empty string and AnalyticsService
  /// skips Mixpanel init entirely. Combined with the M18-LOW consent
  /// gate (Mixpanel only initializes after a non-null
  /// profiles.analytics_consent_at), the event-poisoning vector
  /// described in F-010 is closed for our codepath even though the
  /// plugin's default token is still in the binary.
  static const String mixpanelToken = String.fromEnvironment(
    'MIXPANEL_TOKEN',
    defaultValue: '',
  );
  static const String googleIosClientId = String.fromEnvironment(
    'GOOGLE_IOS_CLIENT_ID',
    defaultValue: '',
  );
  static const String googleWebClientId = String.fromEnvironment(
    'GOOGLE_WEB_CLIENT_ID',
    defaultValue: '',
  );

  /// Call once at app startup to assert required env vars are set.
  static void assertConfigured() {
    if (supabaseUrl.isEmpty) {
      AppLogger.warning(
        '[Env] SUPABASE_URL is not set. '
        'Pass --dart-define=SUPABASE_URL=<url> at build time.',
      );
      assert(false, 'SUPABASE_URL must be provided via --dart-define');
    }
    if (supabaseAnonKey.isEmpty) {
      AppLogger.warning(
        '[Env] SUPABASE_ANON_KEY is not set. '
        'Pass --dart-define=SUPABASE_ANON_KEY=<key> at build time.',
      );
      assert(false, 'SUPABASE_ANON_KEY must be provided via --dart-define');
    }
  }
}
