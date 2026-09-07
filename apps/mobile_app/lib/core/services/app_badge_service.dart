import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:app_core/app_core.dart' show AppLogger;

/// Clears the app icon badge + any delivered system notifications.
///
/// iOS: calls into a native method channel (see AppDelegate.swift) that
/// sets `applicationIconBadgeNumber = 0` and removes all delivered
/// notifications from the notification center.
///
/// Android: cancels all posted notifications via the flutter_local_notifications
/// plugin, which clears the launcher unread badge on most launchers.
///
/// Web / unsupported platforms: no-op.
class AppBadgeService {
  AppBadgeService._();

  static const MethodChannel _iosChannel = MethodChannel('app/badge');

  static Future<void> clear() async {
    if (kIsWeb) return;
    try {
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        await _iosChannel.invokeMethod<void>('clear');
      } else if (defaultTargetPlatform == TargetPlatform.android) {
        await FlutterLocalNotificationsPlugin().cancelAll();
      }
    } catch (e) {
      AppLogger.info('[AppBadge] Failed to clear: $e');
    }
  }
}
