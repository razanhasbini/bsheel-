import 'package:app_repositories/app_repositories.dart' show StreakModel;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_session_provider.dart';
import 'profile_repository_provider.dart';

/// The signed-in user's streak, as the server computes it (#46).
///
/// Replaces `calculateCurrentStreakFromTimestamps`, which had three defects
/// that only a server figure can fix:
///
///  * it counted whatever history page happened to be loaded, so a long
///    streak was silently truncated by pagination — the same mistake #49
///    calls out for discovery percentages;
///  * it counted `rejected` alongside `approved`, so a rejected submission
///    kept a streak alive even though nothing was completed;
///  * it bucketed by *local* date while the reminder sweep runs in UTC, so
///    the number on screen could disagree with the job that warns about it.
///
/// Falls back to a real zero rather than a guess: showing an invented streak
/// is worse than showing none.
final streakProvider = FutureProvider<StreakModel>((ref) async {
  final user = ref.watch(authSessionProvider);
  if (user == null) return const StreakModel.zero();
  return ref.watch(profileRepositoryProvider).getStreak();
});

/// Another user's streak, for their profile page.
final userStreakProvider =
    FutureProvider.family<StreakModel, String>((ref, userId) async {
  return ref.watch(profileRepositoryProvider).getStreak(userId: userId);
});
