import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app_core/app_core.dart' show AppLogger;
import 'package:app_models/app_models.dart';
import 'package:app_repositories/app_repositories.dart';
import '../../../../core/providers/auth_session_provider.dart';
import '../../../../core/backend/app_backend.dart';

final leaderboardRepositoryProvider = Provider<LeaderboardRepository>((ref) {
  return AppBackend.repositories.leaderboard;
});

// Stale-while-revalidate caches. A transient refetch failure keeps the
// previously rendered leaderboard on screen instead of flashing empty.
List<LeaderboardUserModel>? _lastGoodLeaderboard;
List<LeaderboardUserModel>? _lastGoodFollowingLeaderboard;

/// Drops the module-scoped SWR caches. Call on sign-out so the next user
/// on the same device can't see the previous user's "following" board.
void resetLeaderboardCaches() {
  _lastGoodLeaderboard = null;
  _lastGoodFollowingLeaderboard = null;
}

final leaderboardProvider =
    FutureProvider<List<LeaderboardUserModel>>((ref) async {
  final user = ref.watch(authSessionProvider);
  if (user == null) {
    _lastGoodLeaderboard = null;
    return const [];
  }
  try {
    final fresh = await ref
        .watch(leaderboardRepositoryProvider)
        .getLeaderboard()
        .timeout(const Duration(seconds: 8));
    _lastGoodLeaderboard = fresh;
    return fresh;
  } catch (e) {
    if (_lastGoodLeaderboard != null) {
      AppLogger.warning('[Leaderboard] Fetch failed, serving cached: $e');
      return _lastGoodLeaderboard!;
    }
    rethrow;
  }
});

final followingLeaderboardProvider =
    FutureProvider<List<LeaderboardUserModel>>((ref) async {
  final user = ref.watch(authSessionProvider);
  if (user == null) {
    _lastGoodFollowingLeaderboard = null;
    return const [];
  }
  try {
    final fresh = await ref
        .watch(leaderboardRepositoryProvider)
        .getFollowingLeaderboard()
        .timeout(const Duration(seconds: 8));
    _lastGoodFollowingLeaderboard = fresh;
    return fresh;
  } catch (e) {
    if (_lastGoodFollowingLeaderboard != null) {
      AppLogger.warning(
          '[Leaderboard:following] Fetch failed, serving cached: $e');
      return _lastGoodFollowingLeaderboard!;
    }
    rethrow;
  }
});

/// Page-scoped realtime for the leaderboard. Fires whenever any
/// `profiles` row changes. Reordering is rare (XP-only updates), so we
/// throttle invalidation to at most one call per second to avoid
/// re-fetching the whole board for every approval-burst on a busy day.
///
/// The shell-level XP channels already cover the *current* user's
/// changes; this one is what makes the rows of *other* users move.
final leaderboardRealtimeProvider = Provider.autoDispose<void>((ref) {
  Timer? throttle;

  void scheduleInvalidate() {
    throttle?.cancel();
    throttle = Timer(const Duration(milliseconds: 800), () {
      ref.invalidate(leaderboardProvider);
      ref.invalidate(followingLeaderboardProvider);
    });
  }

  final realtime = AppBackend.repositories.realtime;
  final subscription = realtime.events.where((event) {
    return event.type == 'profile.updated' ||
        event.type == 'social.follow.changed';
  }).listen((_) => scheduleInvalidate());
  unawaited(() async {
    try {
      await realtime.connect();
    } catch (error) {
      AppLogger.warning('[Realtime] Leaderboard connection failed: $error');
    }
  }());
  ref.onDispose(() {
    throttle?.cancel();
    unawaited(subscription.cancel());
  });
});
