import 'package:app_core/app_core.dart';

enum BackendMode { legacy, nest }

abstract final class BackendConfig {
  static const String _rawMode = String.fromEnvironment(
    'BACKEND_MODE',
    defaultValue: 'legacy',
  );

  static const String nestApiUrl = String.fromEnvironment(
    'NEST_API_URL',
    defaultValue: '',
  );

  static BackendMode get mode => switch (_rawMode.trim().toLowerCase()) {
        'legacy' => BackendMode.legacy,
        'nest' => BackendMode.nest,
        _ => throw StateError(
            'BACKEND_MODE must be either "legacy" or "nest".',
          ),
      };

  static bool get usesNest => mode == BackendMode.nest;

  static Uri get nestApiUri {
    if (!usesNest) {
      throw StateError('NEST_API_URL is only available in Nest mode.');
    }
    final uri = Uri.tryParse(nestApiUrl);
    if (uri == null ||
        !uri.hasScheme ||
        !uri.hasAuthority ||
        (uri.scheme != 'https' && uri.scheme != 'http')) {
      throw StateError(
        'NEST_API_URL must be an absolute HTTP(S) URL in Nest mode.',
      );
    }
    return uri;
  }

  static void validate() {
    if (!usesNest) return;
    final uri = nestApiUri;
    if (uri.scheme != 'https') {
      AppLogger.warning(
        '[BackendConfig] Nest API is not using HTTPS. '
        'This is acceptable only for local development.',
      );
    }
  }
}
