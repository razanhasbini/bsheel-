import 'package:flutter/foundation.dart';

/// Compile-time API configuration.
///
/// The application talks to exactly one backend: the self-hosted Bsheel API.
/// Supply its base URL at build time:
///
/// ```text
/// --dart-define=API_URL=https://api.bsheel.app/api/v1
/// ```
///
/// Debug builds fall back to a local API so `flutter run` works with no
/// extra flags. Release builds have no fallback on purpose — shipping a
/// binary that points at a developer machine is worse than failing to build.
abstract final class BackendConfig {
  static const String apiUrl = String.fromEnvironment(
    'API_URL',
    defaultValue: '',
  );

  /// Used only by debug builds when `API_URL` is not supplied.
  static const String _debugFallback = 'http://127.0.0.1:3010/api/v1';

  static Uri get apiUri {
    final raw = apiUrl.trim().isNotEmpty
        ? apiUrl.trim()
        : (kReleaseMode ? '' : _debugFallback);

    if (raw.isEmpty) {
      throw StateError(
        'API_URL is required. Build with '
        '--dart-define=API_URL=https://api.bsheel.app/api/v1',
      );
    }

    final uri = Uri.tryParse(raw);
    if (uri == null ||
        !uri.hasScheme ||
        !uri.hasAuthority ||
        (uri.scheme != 'https' && uri.scheme != 'http')) {
      throw StateError('API_URL must be an absolute HTTP(S) URL. Got "$raw".');
    }
    if (kReleaseMode && uri.scheme != 'https') {
      throw StateError('API_URL must use HTTPS in a release build.');
    }
    return uri;
  }

  /// Where the business analytics dashboard is served (#14's "link to the
  /// dashboard on their account").
  ///
  /// Supplied at build time and **not derived from [apiUrl]**. Guessing a
  /// host — swapping `api.` for `admin.`, say — produces a link that looks
  /// right, ships, and 404s for every business owner who taps it, with
  /// nothing in the build to show it was ever a guess.
  static const String dashboardUrl = String.fromEnvironment(
    'DASHBOARD_URL',
    defaultValue: '',
  );

  /// The dashboard link, or null when this build was not told where the
  /// dashboard lives. Null means the profile shows the business without
  /// offering a link, rather than offering one that goes nowhere.
  static Uri? get dashboardUri {
    final raw = dashboardUrl.trim();
    if (raw.isEmpty) return null;
    final uri = Uri.tryParse(raw);
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) return null;
    // A dashboard carries an authenticated session; http would put it on the
    // wire in the clear.
    if (kReleaseMode && uri.scheme != 'https') return null;
    return uri;
  }

  /// Resolved at startup so a misconfigured build fails immediately with a
  /// readable message rather than on the first network call.
  static void validate() => apiUri;
}
