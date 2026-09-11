import 'package:flutter/foundation.dart';

/// Where this build talks to the API.
///
/// Same contract as the other two apps: supplied at build time, validated
/// at startup so a misconfigured bundle fails with a readable message
/// instead of on the first network call.
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

  static void validate() => apiUri;
}
