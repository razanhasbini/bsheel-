import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app_repositories/app_repositories.dart';

import '../../../core/providers/supabase_provider.dart';

final followsRepositoryProvider = Provider<FollowsRepository>((ref) {
  return SupabaseFollowsRepository(ref.watch(supabaseClientProvider));
});

/// Follower + following counts for a given user. Family-keyed so the
/// profile page can watch the viewed user's counts and pull-to-refresh
/// invalidation flushes the right entry.
final followCountsProvider = FutureProvider.autoDispose
    .family<FollowCounts, String>((ref, userId) async {
  return ref.watch(followsRepositoryProvider).getFollowCounts(userId);
});

/// Whether the current user is following [targetUserId]. Replaces the
/// previous local `_isFollowing` state in FollowButton so the shell-level
/// follows realtime channel can invalidate it and every visible follow
/// button updates without a manual re-check.
final isFollowingProvider = FutureProvider.autoDispose
    .family<bool, String>((ref, targetUserId) async {
  return ref.watch(followsRepositoryProvider).isFollowing(targetUserId);
});
