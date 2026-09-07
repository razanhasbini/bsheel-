import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:app_core/app_core.dart' show AppLogger;
import 'package:app_repositories/app_repositories.dart';

/// Notifies [GoRouter] when the selected auth session changes so redirects re-run.
/// Handles auth errors gracefully without crashing.
final class AuthRefreshNotifier extends ChangeNotifier {
  AuthRefreshNotifier(AuthRepository repository) {
    _sub = repository.authStateChanges.listen(
      (_) {
        notifyListeners();
      },
      onError: (error) {
        // Suppress initialization auth errors
        final errorMsg = error.toString().toLowerCase();
        if (errorMsg.contains('session expired') ||
            errorMsg.contains('refresh token') ||
            errorMsg.contains('auth session')) {
          AppLogger.info('[AuthRefresh] Suppressed init auth error: $error');
        } else {
          AppLogger.error('[AuthRefresh] Auth stream error', error);
        }
        // Still notify listeners so UI can update
        notifyListeners();
      },
    );
  }

  late final StreamSubscription<dynamic> _sub;

  /// Public hook so other providers (e.g. admin role resolution) can ask
  /// GoRouter to re-evaluate its redirects without subclassing.
  void poke() => notifyListeners();

  @override
  void dispose() {
    unawaited(_sub.cancel());
    super.dispose();
  }
}
