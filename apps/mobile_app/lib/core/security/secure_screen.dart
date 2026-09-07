import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

// H9 (2026-05-17): screenshot / screen-recording protection for screens
// that show credentials or one-time tokens. Apply by mixing into a
// State<T>: `class _ResetPasswordState extends State<...> with SecureScreenMixin`.
//
// Android (implemented): FLAG_SECURE blocks screenshots, screen recording,
// and recent-apps preview rendering.
//
// iOS (best-effort): there is no public API for FLAG_SECURE equivalent.
// We blur the window snapshot on app-resign via a notification observer
// in AppDelegate.swift; this mixin handles the Android side only and
// is a no-op on iOS. Apple's own password fields are already snapshot-
// suppressed by UIKit when the field is the first responder.

const _channel = MethodChannel('bsheel/secure_screen');

mixin SecureScreenMixin<T extends StatefulWidget> on State<T> {
  bool _secureApplied = false;

  @override
  void initState() {
    super.initState();
    _enable();
  }

  @override
  void dispose() {
    _disable();
    super.dispose();
  }

  Future<void> _enable() async {
    if (!_isAndroid) return;
    try {
      await _channel.invokeMethod('setSecure', {'enable': true});
      _secureApplied = true;
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('[SecureScreen] enable failed: $e');
      }
    }
  }

  Future<void> _disable() async {
    if (!_isAndroid || !_secureApplied) return;
    try {
      await _channel.invokeMethod('setSecure', {'enable': false});
    } catch (_) {
      // best-effort; if the channel is gone the screen is gone too.
    }
  }

  bool get _isAndroid {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android;
  }
}
