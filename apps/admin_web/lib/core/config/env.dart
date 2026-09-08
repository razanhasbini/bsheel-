/// Client-safe build-time values only.
///
/// The API base URL lives in [BackendConfig], which validates it at
/// startup. Nothing secret belongs in a web bundle.
abstract final class Env {
  static const String mixpanelToken = String.fromEnvironment(
    'MIXPANEL_TOKEN',
    defaultValue: '',
  );
}
