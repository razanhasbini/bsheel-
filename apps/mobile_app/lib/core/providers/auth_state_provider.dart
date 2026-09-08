import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app_repositories/app_repositories.dart';
import 'package:app_core/app_core.dart' show AppLogger;
import '../services/sign_out_service.dart' show resetAllModuleCaches;
import '../services/device_token_service.dart';
import 'auth_repository_provider.dart';
import 'auth_session_provider.dart';

/// Tracks whether a passwordRecovery deep link was received.
final passwordRecoveryProvider = StateProvider<bool>((ref) => false);

/// A [ChangeNotifier] that listens to the selected auth repository and
/// notifies GoRouter to re-evaluate guards on every change.
///
/// This is the SINGLE auth stream listener for the app. It also:
/// - Syncs [authSessionProvider] with the compatible authenticated user
/// - Detects passwordRecovery deep links
/// - Saves FCM tokens on sign-in
class AuthNotifier extends ChangeNotifier {
  AuthNotifier(AuthRepository authRepository, Ref ref) {
    _subscription = authRepository.authStateChanges.listen(
      (state) {
        AppLogger.info(
            '[AuthState] event=${state.event} hasSession=${state.session != null}');

        // Detect password recovery deep links
        if (state.event == AuthChangeEvent.passwordRecovery) {
          ref.read(passwordRecoveryProvider.notifier).state = true;
        }

        // ARC-005 + audit-2026-05: drop queued vote/save syncs AND every
        // module-level SWR cache on sign-out / user switch so user A's
        // pending intent / cached data can't leak into user B's session.
        // Defensive — `signOutAndCleanup()` already clears these on
        // user-triggered logout; this catches silent token expiry too.
        if (state.event == AuthChangeEvent.signedOut ||
            state.event == AuthChangeEvent.userUpdated) {
          resetAllModuleCaches();
        }

        // Sync session state
        _syncSessionState(ref, state.session?.user);

        // Save FCM token only on a fresh sign-in (user logged in from the
        // signed-out state). `initialSession` and `tokenRefreshed` are handled
        // by bootstrap's `initDeferredServices()` / `onTokenRefresh` listener,
        // which run AFTER Firebase is initialized. Firing here on startup
        // raced the deferred Firebase init and stalled the UI thread.
        if (state.event == AuthChangeEvent.signedIn &&
            state.session?.user != null) {
          _saveFcmToken();
        }

        notifyListeners();
      },
      onError: (error) {
        final errorMsg = error.toString().toLowerCase();
        if (errorMsg.contains('session expired') ||
            errorMsg.contains('refresh token') ||
            errorMsg.contains('auth session')) {
          AppLogger.info('[AuthNotifier] Suppressed init auth error: $error');
          ref.read(authSessionProvider.notifier).state = null;
        } else {
          AppLogger.error('[AuthNotifier] Auth error', error);
        }
        notifyListeners();
      },
    );

    // Sync after provider build completes (deferred to avoid modifying
    // another provider during initialization).
    Future.microtask(() => _syncSessionState(ref, authRepository.currentUser));
  }

  late final StreamSubscription<AuthState> _subscription;

  void _syncSessionState(Ref ref, AuthUser? nextUser) {
    final currentUser = ref.read(authSessionProvider);
    if (currentUser?.id != nextUser?.id) {
      ref.read(authSessionProvider.notifier).state = nextUser;
    }
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}

final authNotifierProvider = ChangeNotifierProvider<AuthNotifier>((ref) {
  return AuthNotifier(ref.watch(authRepositoryProvider), ref);
});

/// Save FCM token to profile_tokens after a fresh sign-in. Guarded on
/// `Firebase.apps.isNotEmpty` so we never call the Firebase plugin before
/// `initDeferredServices()` has initialized it (that race previously
/// stalled the main isolate and made the home screen sit on its 'Agent'
/// placeholder for ~1 minute on app open).
Future<void> _saveFcmToken() async {
  try {
    if (kIsWeb) return;
    if (Firebase.apps.isEmpty) {
      AppLogger.info('[FCM] Skipping save — Firebase not initialized yet.');
      return;
    }
    final token = await FirebaseMessaging.instance.getToken();
    if (token == null) return;
    await DeviceTokenService.register(token);
    // SEC-032: don't log the user UUID — crash reports / MDM exfil etc.
    AppLogger.info('[FCM] Token saved');
  } catch (e) {
    AppLogger.error('[FCM] Failed to save token', e);
  }
}
