import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Native-bridge wrapper that reads bundle metadata directly from
/// CFBundleVersion / VersionCode without pulling in a 3rd-party plugin.
class AppInfoService {
  static const MethodChannel _channel = MethodChannel('app/info');

  int? _cachedBuild;
  String? _cachedVersion;

  /// Numeric build (CFBundleVersion on iOS, versionCode on Android).
  /// Returns null on platforms where the channel isn't wired.
  Future<int?> buildNumber() async {
    if (_cachedBuild != null) return _cachedBuild;
    try {
      final res = await _channel.invokeMethod<dynamic>('getBuildNumber');
      if (res is int) {
        _cachedBuild = res;
      } else if (res is String) {
        _cachedBuild = int.tryParse(res);
      }
    } catch (_) {/* fall through to null */}
    return _cachedBuild;
  }

  /// Marketing version (CFBundleShortVersionString / versionName).
  Future<String?> marketingVersion() async {
    if (_cachedVersion != null) return _cachedVersion;
    try {
      final res = await _channel.invokeMethod<String>('getMarketingVersion');
      _cachedVersion = res;
    } catch (_) {/* fall through to null */}
    return _cachedVersion;
  }

  /// Async helper that returns the app's current store URL based on the
  /// platform. The actual store IDs are baked in here for now; if you
  /// switch bundle IDs / package names, update both sides.
  String storeUrl() {
    if (Platform.isIOS) {
      // Update the App Store ID once the app is live in the store.
      // Falls back to the search URL so taps don't dead-end.
      return 'https://apps.apple.com/app/id6499000000';
    }
    if (Platform.isAndroid) {
      return 'https://play.google.com/store/apps/details?id=com.questapp.mobileApp';
    }
    return 'https://bsheel.app';
  }
}

final appInfoServiceProvider = Provider<AppInfoService>((ref) {
  return AppInfoService();
});
