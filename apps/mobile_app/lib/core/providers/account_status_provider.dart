import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_session_provider.dart';
import '../backend/app_backend.dart';

/// Checks the user's account status (active, suspended, banned).
/// Returns null if not logged in, the status string otherwise.
final accountStatusProvider = FutureProvider<String?>((ref) async {
  final user = ref.watch(authSessionProvider);
  if (user == null) return null;

  try {
    return await AppBackend.repositories.account.accountStatus();
  } catch (_) {
    // Treat an unreadable status as active rather than locking the user out
    // of the app on a transient failure.
    return 'active';
  }
});
