import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app_models/app_models.dart';

import '../../../../core/providers/current_profile_provider.dart';
import '../../../../core/providers/auth_session_provider.dart';
import '../../../../core/providers/profile_repository_provider.dart';
import '../../../../core/backend/app_backend.dart';
import '../../../leaderboard/presentation/providers/leaderboard_provider.dart';

/// Profile row for any [userId]. Used both by the profile page (when
/// viewing another user) and by the realtime provider so the channel
/// callback has a target it can invalidate without reaching into the
/// page widget. ARC-024: routes through `profileRepositoryProvider`.
final viewedProfileProvider = FutureProvider.autoDispose
    .family<ProfileModel?, String>((ref, userId) async {
  return ref.watch(profileRepositoryProvider).getProfile(userId);
});

/// Page-scoped realtime for a single profile row. Whenever the underlying
/// `profiles` row changes (XP, level, avatar, bio, badges, etc.) the
/// matching profile read is invalidated so the open profile page
/// re-renders.
///
/// Watch this from the profile page; it tears down when the page leaves.
/// Counts that come from joins (followers, posts) are handled by the
/// shell-level follows + feed channels.
final profileRealtimeProvider =
    Provider.autoDispose.family<void, String>((ref, userId) {
  final myId = ref.watch(authSessionProvider)?.id;

  void invalidateProfile() {
    if (myId == userId) {
      ref.invalidate(currentProfileProvider);
    } else {
      ref.invalidate(viewedProfileProvider(userId));
    }
    ref.invalidate(leaderboardProvider);
    ref.invalidate(followingLeaderboardProvider);
  }

  final realtime = AppBackend.repositories.realtime;
  final subscription = realtime.events.where((event) {
    return event.type == 'profile.updated' && event.data['profileId'] == userId;
  }).listen((_) => invalidateProfile());
  unawaited(() async {
    try {
      await realtime.connect();
    } catch (error) {
      if (kDebugMode) {
        debugPrint('[Realtime] Profile connection failed: $error');
      }
    }
  }());
  ref.onDispose(() => unawaited(subscription.cancel()));
});
