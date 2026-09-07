import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app_core/app_core.dart' show AppLogger;
import 'package:app_models/app_models.dart';
import 'auth_session_provider.dart';
import 'profile_repository_provider.dart';

// Stale-while-revalidate cache. Lives at module scope so a transient network
// failure on a refetch keeps the last good profile on screen instead of
// flashing "no profile exists". Cleared on logout (session-expired branch).
ProfileModel? _lastGoodProfile;

final currentProfileProvider = FutureProvider<ProfileModel?>((ref) async {
  // Keep dependency so auth changes re-evaluate this provider.
  final user = ref.watch(authSessionProvider);
  if (user == null) {
    _lastGoodProfile = null;
    return null;
  }
  try {
    final fresh = await ref
        .watch(profileRepositoryProvider)
        .getProfile(user.id)
        .timeout(const Duration(seconds: 8));
    _lastGoodProfile = fresh;
    return fresh;
  } catch (e) {
    final msg = e.toString().toLowerCase();
    // Session expired mid-request — surface null so UI routes to sign-in.
    if (msg.contains('session expired') ||
        msg.contains('jwt expired') ||
        msg.contains('refresh token') ||
        msg.contains('401')) {
      AppLogger.info('[Profile] Session expired during fetch — returning null');
      _lastGoodProfile = null;
      return null;
    }
    // Transient error (timeout, DNS, network drop, RLS hiccup): keep the
    // last-known profile on screen rather than rendering a "no profile" empty
    // state. The next realtime event or pull-to-refresh will retry.
    if (_lastGoodProfile != null) {
      AppLogger.warning('[Profile] Fetch failed, serving cached value: $e');
      return _lastGoodProfile;
    }
    AppLogger.warning('[Profile] First fetch failed with no cache: $e');
    rethrow;
  }
});

/// Drops the module-scoped SWR cache. Call on sign-out so the next user
/// on the same device can't see the previous user's profile briefly.
void resetProfileCache() {
  _lastGoodProfile = null;
}
