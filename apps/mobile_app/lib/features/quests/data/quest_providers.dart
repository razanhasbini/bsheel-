import 'package:app_core/app_core.dart' show AppLogger;
import 'package:app_models/app_models.dart';
import 'package:app_repositories/app_repositories.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/auth_session_provider.dart';
import '../../../core/backend/app_backend.dart';

// Stale-while-revalidate caches. A transient network failure on a refetch
// keeps the last good data on screen instead of rendering an empty state.
// Cleared when the session is gone.
UserQuestModel? _lastGoodActiveQuest;
List<UserQuestModel>? _lastGoodQuestHistory;

/// Drops the module-scoped SWR caches. Call on sign-out so the next user
/// on the same device can't see the previous user's quests briefly.
void resetQuestCaches() {
  _lastGoodActiveQuest = null;
  _lastGoodQuestHistory = null;
}

final questsRepositoryProvider = Provider<QuestsRepository>((ref) {
  return AppBackend.repositories.quests;
});

/// Per-user wishlist of quests they've BSHEEEL'd from search / discover.
/// Mirrors `savedPostsRepositoryProvider`.
final savedQuestsRepositoryProvider = Provider<SavedQuestsRepository>((ref) {
  return AppBackend.repositories.savedQuests;
});

/// Whether the current user has BSHEEEL'd a quest. Used by the search
/// quest tile to show filled vs outlined bookmark.
final isQuestSavedProvider =
    FutureProvider.autoDispose.family<bool, ({String questId, String userId})>(
  (ref, args) {
    return ref
        .watch(savedQuestsRepositoryProvider)
        .isQuestSaved(args.questId, args.userId);
  },
);

final activeQuestProvider = FutureProvider<UserQuestModel?>((ref) async {
  // Keep dependency so auth changes re-evaluate this provider.
  final user = ref.watch(authSessionProvider);
  if (user == null) {
    _lastGoodActiveQuest = null;
    return null;
  }

  final repository = ref.watch(questsRepositoryProvider);
  try {
    final fresh = await repository
        .getActiveUserQuest(user.id)
        .timeout(const Duration(seconds: 8));
    _lastGoodActiveQuest = fresh;
    return fresh;
  } catch (e) {
    if (_lastGoodActiveQuest != null) {
      AppLogger.warning('[ActiveQuest] Fetch failed, serving cached: $e');
      return _lastGoodActiveQuest;
    }
    rethrow;
  }
});

final questHistoryProvider = FutureProvider<List<UserQuestModel>>((ref) async {
  // Keep dependency so auth changes re-evaluate this provider.
  final user = ref.watch(authSessionProvider);
  if (user == null) {
    _lastGoodQuestHistory = null;
    return const [];
  }

  final repository = ref.watch(questsRepositoryProvider);
  try {
    final fresh = await repository
        .getUserQuestHistory(user.id)
        .timeout(const Duration(seconds: 8));
    _lastGoodQuestHistory = fresh;
    return fresh;
  } catch (e) {
    if (_lastGoodQuestHistory != null) {
      AppLogger.warning('[QuestHistory] Fetch failed, serving cached: $e');
      return _lastGoodQuestHistory!;
    }
    rethrow;
  }
});

/// Quest history for a specific user (used when viewing another profile).
final questHistoryByUserProvider = FutureProvider.autoDispose
    .family<List<UserQuestModel>, String>((ref, userId) async {
  final repository = ref.watch(questsRepositoryProvider);
  return repository.getUserQuestHistory(userId);
});

final questDetailsProvider =
    FutureProvider.autoDispose.family<QuestModel, String>((
  ref,
  questId,
) async {
  final repository = ref.watch(questsRepositoryProvider);
  return repository.getQuest(questId);
});
