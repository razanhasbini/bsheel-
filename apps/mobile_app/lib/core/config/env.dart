/// Client-safe build-time values only.
///
/// The API base URL lives in [BackendConfig], which validates it at
/// startup. Everything here is a third-party client token that is public
/// by design; nothing secret belongs in a Flutter binary.
abstract final class Env {
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
}
