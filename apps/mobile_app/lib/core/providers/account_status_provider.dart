import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_contracts/supabase_contracts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'auth_session_provider.dart';
import '../backend/backend_config.dart';
import '../backend/mobile_nest_backend.dart';

/// Checks the user's account status (active, suspended, banned).
/// Returns null if not logged in, the status string otherwise.
final accountStatusProvider = FutureProvider<String?>((ref) async {
  final user = ref.watch(authSessionProvider);
  if (user == null) return null;

  try {
    if (BackendConfig.usesNest) {
      return MobileNestBackend.repositories.account.accountStatus();
    }
    final result =
        await Supabase.instance.client.rpc(RpcNames.getMyAccountStatus);
    return result as String?;
  } catch (_) {
    // If the RPC doesn't exist yet (migration not applied), assume active
    return 'active';
  }
});
