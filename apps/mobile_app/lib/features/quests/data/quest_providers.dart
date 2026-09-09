import 'dart:convert';

import 'package:app_core/app_core.dart' show AppLogger;
import 'package:app_models/app_models.dart';
import 'package:app_repositories/app_repositories.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

// ── Reroll budget ──────────────────────────────────────────────────────────

/// The reroll budget: five per rolling 24 hours.
///
/// Two sources have to agree. The server is authoritative — it rejects the
/// sixth reroll whatever the client believes — but it cannot say *when* the
/// next slot frees up, and the client's own timestamps can. So the count is
/// the lower of the two and the refill clock comes from local history.
///
/// This lives here rather than inside the picker sheet because the home
/// slot machine prints `N REROLLS LEFT · RESETS IN Nh` under its GENERATE
/// button, and two copies of a rolling-window calculation is how the two
/// numbers end up disagreeing.
class RerollBudget {
  const RerollBudget({required this.remaining, required this.refillIn});

  const RerollBudget.unknown()
      : remaining = maxPerWindow,
        refillIn = null;

  final int remaining;

  /// Time until the oldest reroll in the window ages out. Null while
  /// rerolls are still available.
  final Duration? refillIn;

  static const int maxPerWindow = 5;
  static const Duration window = Duration(hours: 24);

  bool get canReroll => remaining > 0;
}

String _rerollHistoryKey(String userId) => 'quest_reroll_history_$userId';

/// Legacy single-timestamp key from before the 5-per-window budget.
/// Migrated on first read so an in-flight cooldown isn't handed back as
/// five fresh rerolls.
String _legacyRerollKey(String userId) => 'quest_last_reroll_at_$userId';

List<DateTime> _prune(List<DateTime> history) {
  final cutoff = DateTime.now().subtract(RerollBudget.window);
  return history.where((t) => t.isAfter(cutoff)).toList()..sort();
}

Future<List<DateTime>> _readHistory(String userId) async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString(_rerollHistoryKey(userId));
  final history = <DateTime>[];

  if (raw != null) {
    try {
      for (final entry in jsonDecode(raw) as List<dynamic>) {
        final ts = DateTime.tryParse(entry as String);
        if (ts != null) history.add(ts);
      }
    } catch (_) {
      // Corrupt payload — treat as empty rather than blocking the player.
    }
  } else {
    final legacyRaw = prefs.getString(_legacyRerollKey(userId));
    final legacy = legacyRaw == null ? null : DateTime.tryParse(legacyRaw);
    if (legacy != null) history.add(legacy);
    await prefs.remove(_legacyRerollKey(userId));
  }
  return _prune(history);
}

/// Records a reroll locally and against the server, then returns the fresh
/// budget. The server's response wins on the count.
Future<RerollBudget> recordReroll(String userId) async {
  final serverRemaining = await AppBackend.repositories.quests.recordReroll();
  final next = _prune([...await _readHistory(userId), DateTime.now()]);
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(
    _rerollHistoryKey(userId),
    jsonEncode(next.map((t) => t.toIso8601String()).toList()),
  );
  return _budget(next, serverRemaining);
}

RerollBudget _budget(List<DateTime> history, int? serverRemaining) {
  final local = (RerollBudget.maxPerWindow - history.length).clamp(0, 5);
  final remaining = serverRemaining == null || local < serverRemaining
      ? local
      : serverRemaining;
  Duration? refillIn;
  if (remaining <= 0 && history.isNotEmpty) {
    final unlock = history.first.add(RerollBudget.window);
    final left = unlock.difference(DateTime.now());
    refillIn = left.isNegative ? Duration.zero : left;
  }
  return RerollBudget(remaining: remaining, refillIn: refillIn);
}

final rerollBudgetProvider = FutureProvider<RerollBudget>((ref) async {
  final user = ref.watch(authSessionProvider);
  if (user == null) return const RerollBudget.unknown();

  final history = await _readHistory(user.id);
  int? serverRemaining;
  try {
    serverRemaining = await AppBackend.repositories.quests
        .getRerollsRemaining()
        .timeout(const Duration(seconds: 8));
  } on Object {
    // Preserve the local rolling-window UX while offline. The server still
    // enforces the authoritative limit when a reroll is recorded.
  }
  return _budget(history, serverRemaining);
});
