import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:app_core/app_core.dart' show AppLogger;

import '../../../core/backend/app_backend.dart';
import '../../../core/services/device_token_service.dart';

const _pushKey = 'settings.pushNotifications';

/// The push-notifications switch drawn in `export/mobile/21-settings.jpg`.
///
/// It is a *real* preference, not a decoration:
///
/// * the choice is persisted in `SharedPreferences` under [_pushKey], so it
///   survives a restart;
/// * turning it off deletes this device's FCM token server-side, which is
///   what actually stops delivery — the API can only push to a registered
///   token;
/// * turning it on re-registers the current token.
///
/// `bootstrap.dart` registers the token on every cold start regardless of
/// this flag, so [reconcile] re-applies the preference once the user is
/// inside the app shell. Without that call the switch would read "off" and
/// push would quietly resume after the next launch. `BottomNavShell` makes
/// the call; if you move it, keep a caller.
///
/// The warning the frame prints under the switch — "Off means you won't be
/// told if a submission is rejected" — is literal: notification taps are the
/// primary route to the appeal flow (see CLAUDE.md, "Reaching the appeal
/// flow"). That is why the copy is a warning and not a hint.
class PushPreferenceNotifier extends StateNotifier<bool> {
  PushPreferenceNotifier() : super(true) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getBool(_pushKey) ?? true;
    if (stored != state) state = stored;
  }

  /// Persist [enabled] and apply it to this device's token registration.
  ///
  /// The state flips first so the switch never lags the tap; a transport
  /// failure is logged rather than thrown, because the persisted preference
  /// is still correct and [reconcile] will retry the transport next launch.
  Future<void> setEnabled(bool enabled) async {
    state = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_pushKey, enabled);
    await _apply(enabled);
  }

  /// Re-apply the stored preference to the transport.
  ///
  /// Only does work when push is switched OFF: that is the case cold-start
  /// token registration would otherwise undo.
  Future<void> reconcile() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getBool(_pushKey) ?? true;
    if (stored != state) state = stored;
    if (!stored) await _apply(false);
  }

  Future<void> _apply(bool enabled) async {
    // No FCM on web, and none before Firebase has been initialised (the
    // simulator and the widget tests both run without it).
    if (kIsWeb || Firebase.apps.isEmpty) return;
    if (AppBackend.repositories.auth.currentUser == null) return;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null) return;
      if (enabled) {
        await DeviceTokenService.register(token);
      } else {
        await AppBackend.repositories.account.deleteDeviceToken(token);
      }
    } catch (error) {
      AppLogger.warning('[Push] Could not apply push preference: $error');
    }
  }
}

final pushPreferenceProvider =
    StateNotifierProvider<PushPreferenceNotifier, bool>(
        (ref) => PushPreferenceNotifier());
