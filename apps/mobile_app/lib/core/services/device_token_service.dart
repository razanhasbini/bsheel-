import 'package:flutter/foundation.dart';

import '../backend/app_backend.dart';

/// Persists push tokens without exposing transport details to auth or
/// bootstrap code. Tokens are encrypted at rest by the API.
abstract final class DeviceTokenService {
  static Future<void> register(String token) async {
    await AppBackend.repositories.account.registerDeviceToken(
      token,
      _platform,
    );
  }

  static String get _platform {
    return switch (defaultTargetPlatform) {
      TargetPlatform.iOS => 'ios',
      TargetPlatform.android => 'android',
      _ => 'web',
    };
  }
}
