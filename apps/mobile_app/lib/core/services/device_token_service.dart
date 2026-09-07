import 'package:flutter/foundation.dart';
import 'package:supabase_contracts/supabase_contracts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../backend/backend_config.dart';
import '../backend/mobile_nest_backend.dart';

/// Persists push tokens through the selected backend without exposing backend
/// details to auth/bootstrap code.
abstract final class DeviceTokenService {
  static Future<void> register(String token) async {
    if (BackendConfig.usesNest) {
      await MobileNestBackend.repositories.account.registerDeviceToken(
        token,
        _platform,
      );
      return;
    }
    await Supabase.instance.client.rpc(
      RpcNames.upsertFcmToken,
      params: {'p_token': token},
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
