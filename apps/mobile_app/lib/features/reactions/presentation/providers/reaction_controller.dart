import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app_core/app_core.dart' show AppLogger;
import 'package:app_models/app_models.dart';
import 'package:app_repositories/app_repositories.dart';
import 'package:supabase_contracts/supabase_contracts.dart';
import '../../../../core/providers/supabase_provider.dart';
import '../../../../core/services/analytics_service.dart';
import '../../../../core/utils/account_lock_guard.dart';
import '../../../feed/presentation/providers/feed_provider.dart' show feedProvider;
import '../../../feed/presentation/providers/feed_post_details_provider.dart'
    show feedPostDetailsProvider;

final reactionsRepositoryProvider = Provider<ReactionsRepository>((ref) {
  return SupabaseReactionsRepository(ref.watch(supabaseClientProvider));
});

final savedPostsRepositoryProvider = Provider<SavedPostsRepository>((ref) {
  return SupabaseSavedPostsRepository(ref.watch(supabaseClientProvider));
});

// ── Optimistic state overrides ──────────────────────────────────────────────
// When non-null these take priority over server data.

final _optimisticVoteType = StateProvider.autoDispose
    .family<String?, String>((ref, submissionId) => null);

final _optimisticVoteCounts = StateProvider.autoDispose
    .family<Map<String, int>?, String>((ref, submissionId) => null);

final _optimisticSaved = StateProvider.autoDispose
    .family<bool?, ({String submissionId, String userId})>((ref, key) => null);

/// The current user's vote on a submission (null = no vote).
final myVoteProvider = FutureProvider.autoDispose
    .family<ReactionModel?, ({String submissionId, String userId})>(
  (ref, args) {
    return ref
        .watch(reactionsRepositoryProvider)
        .getMyVote(args.submissionId, args.userId);
  },
);

/// Whether the current user has saved (bsheeel'd) a submission.
final isPostSavedProvider = FutureProvider.autoDispose
    .family<bool, ({String submissionId, String userId})>(
  (ref, args) {
    return ref
        .watch(savedPostsRepositoryProvider)
        .isPostSaved(args.submissionId, args.userId);
  },
);

// ── Public getters that merge optimistic state with server state ─────────

String? getEffectiveVoteType(WidgetRef ref, String submissionId, String userId) {
  final optimistic = ref.watch(_optimisticVoteType(submissionId));
  if (optimistic != null) return optimistic == 'none' ? null : optimistic;
  return ref
      .watch(myVoteProvider((submissionId: submissionId, userId: userId)))
      .valueOrNull
      ?.type;
}

Map<String, int> getEffectiveVoteCounts(
    WidgetRef ref, String submissionId, FeedPostModel post) {
  final optimistic = ref.watch(_optimisticVoteCounts(submissionId));
  if (optimistic != null) return optimistic;
  return {
    ReactionType.upvote: post.upvoteCount,
    ReactionType.downvote: post.downvoteCount,
  };
}

bool getEffectiveSaved(WidgetRef ref, String submissionId, String userId) {
  final key = (submissionId: submissionId, userId: userId);
  final optimistic = ref.watch(_optimisticSaved(key));
  if (optimistic != null) return optimistic;
  return ref.watch(isPostSavedProvider(key)).valueOrNull ?? false;
}

// ── Serialized server-sync queue (per submissionId) ─────────────────────────
//
// Every tap updates the optimistic state INSTANTLY so the UI is always snappy.
// Server calls are serialized per-submission: one in flight at a time. If the
// user taps again while a request is running we just remember their LATEST
// desired state; after the current call finishes we fire one more call to
// reconcile. Intermediate taps collapse harmlessly — the server always ends
// up matching what the UI is already showing.
//
// Treats "upvote → downvote" as a natural switch: the optimistic update
// decrements up and increments down in one step (reset + new), and the server
// upsert (UNIQUE(submission_id, user_id)) replaces the row in a single call.

final Map<String, _VoteJob> _voteJobs = <String, _VoteJob>{};

/// Drops every queued vote + save sync. Call when the auth user changes
/// (sign-out, switch account) so a job created by user A can never
/// fire against user B's session. Wired from app-level auth listeners.
/// ARC-005.
void resetReactionState() {
  _voteJobs.clear();
  _saveJobs.clear();
}

class _VoteJob {
  _VoteJob(this.target);
  String target; // 'upvote' | 'downvote' | 'none'
  String? pending; // the latest desired state while `target` is syncing
}

/// Toggle a vote with optimistic UI + serialized server syncs.
///
/// Rules:
/// - Same type tapped twice → "none" (removed)
/// - Different type tapped → switch directly (no un-press needed first).
/// - Tapping while a request is in flight is always honored optimistically;
///   the server sync runs after the current one completes.
Future<String?> toggleVote({
  required WidgetRef ref,
  required String submissionId,
  required String userId,
  required String voteType,
  required Map<String, int> baseCounts,
}) async {
  // Locked accounts: server RLS rejects the write anyway, but skipping
  // the optimistic flip avoids the misleading "tap took effect" UX.
  // Return the current effective state so the caller's UI doesn't update.
  if (isAccountLocked(ref)) {
    final currentType = ref.read(_optimisticVoteType(submissionId)) ??
        ref
            .read(myVoteProvider((submissionId: submissionId, userId: userId)))
            .valueOrNull
            ?.type;
    return currentType == 'none' ? null : currentType;
  }
  // 1. Read the user's CURRENT effective state (optimistic wins).
  final currentType = ref.read(_optimisticVoteType(submissionId)) ??
      ref
          .read(myVoteProvider((submissionId: submissionId, userId: userId)))
          .valueOrNull
          ?.type;
  final normalized = currentType == 'none' ? null : currentType;

  // 2. Compute the next desired state.
  final String nextTarget; // 'upvote' | 'downvote' | 'none'
  if (normalized == voteType) {
    // Toggle off
    nextTarget = 'none';
  } else {
    // Switch or fresh vote
    nextTarget = voteType;
  }

  // 3. Apply optimistic update (instant UI feedback, no blocking).
  _applyOptimistic(
    ref: ref,
    submissionId: submissionId,
    previousType: normalized,
    nextTarget: nextTarget,
    baseCounts: baseCounts,
  );
  HapticFeedback.selectionClick();

  // 4. Schedule a server sync. If one's already running, queue the latest
  //    intent and bail — the running job will pick it up.
  final existing = _voteJobs[submissionId];
  if (existing != null) {
    existing.pending = nextTarget;
    return nextTarget == 'none' ? null : nextTarget;
  }
  _voteJobs[submissionId] = _VoteJob(nextTarget);
  // fire-and-forget; this method returns immediately
  // so the UI stays responsive.
  // ignore: unawaited_futures
  _runVote(ref: ref, submissionId: submissionId, userId: userId);

  return nextTarget == 'none' ? null : nextTarget;
}

/// Apply the next optimistic state: decrement the previous type's counter
/// (if any), increment the new type's counter (unless switching to 'none').
void _applyOptimistic({
  required WidgetRef ref,
  required String submissionId,
  required String? previousType,
  required String nextTarget,
  required Map<String, int> baseCounts,
}) {
  final currentCounts = ref.read(_optimisticVoteCounts(submissionId)) ??
      baseCounts;
  final newCounts = Map<String, int>.from(currentCounts);

  if (previousType != null && previousType != 'none') {
    newCounts[previousType] =
        ((newCounts[previousType] ?? 1) - 1).clamp(0, 1 << 30);
  }
  if (nextTarget != 'none') {
    newCounts[nextTarget] = (newCounts[nextTarget] ?? 0) + 1;
  }

  ref.read(_optimisticVoteCounts(submissionId).notifier).state = newCounts;
  ref.read(_optimisticVoteType(submissionId).notifier).state = nextTarget;
}

/// Drains the server queue for [submissionId]. Runs the current target, then
/// any pending target that accumulated while the request was in flight.
Future<void> _runVote({
  required WidgetRef ref,
  required String submissionId,
  required String userId,
}) async {
  final repo = ref.read(reactionsRepositoryProvider);
  while (true) {
    final job = _voteJobs[submissionId];
    if (job == null) return;
    final target = job.target;
    try {
      if (target == 'none') {
        await repo.removeVote(submissionId, userId);
      } else {
        await repo.vote(submissionId, userId, target);
        ref.read(analyticsProvider).reactionAdded(submissionId, target);
      }
    } catch (e) {
      AppLogger.error('[Vote] Sync failed for $submissionId → $target', e);
      // On failure, drop the queue + surface server truth so the UI recovers.
      // We also have to invalidate the feed providers — without this, the
      // displayed count comes from the cached FeedPostModel snapshot, so
      // clearing only the optimistic overlay leaves the UI showing the
      // would-have-been count rather than the actual current count.
      _voteJobs.remove(submissionId);
      ref.read(_optimisticVoteType(submissionId).notifier).state = null;
      ref.read(_optimisticVoteCounts(submissionId).notifier).state = null;
      ref.invalidate(
          myVoteProvider((submissionId: submissionId, userId: userId)));
      ref.invalidate(feedPostDetailsProvider(submissionId));
      ref.invalidate(feedProvider);
      return;
    }

    // If the user tapped again during the request, drain the pending target.
    final pending = _voteJobs[submissionId]?.pending;
    if (pending != null && pending != target) {
      _voteJobs[submissionId] = _VoteJob(pending);
      continue; // run another pass
    }

    // Queue is empty — background-refresh server providers so the next
    // cold read is current.
    _voteJobs.remove(submissionId);
    ref.invalidate(
        myVoteProvider((submissionId: submissionId, userId: userId)));
    return;
  }
}

// ── Saved / Bsheeel ─────────────────────────────────────────────────────────

final Map<String, _SaveJob> _saveJobs = <String, _SaveJob>{};

class _SaveJob {
  _SaveJob(this.target);
  bool target;
  bool? pending;
}

Future<bool> toggleSavePost({
  required WidgetRef ref,
  required String submissionId,
  required String userId,
}) async {
  final key = (submissionId: submissionId, userId: userId);
  final wasSaved = ref.read(_optimisticSaved(key)) ??
      ref.read(isPostSavedProvider(key)).valueOrNull ??
      false;
  // Locked accounts: RLS rejects anyway — skip the optimistic flip.
  if (isAccountLocked(ref)) return wasSaved;
  final target = !wasSaved;

  // Optimistic flip
  ref.read(_optimisticSaved(key).notifier).state = target;
  HapticFeedback.selectionClick();

  final existing = _saveJobs[submissionId];
  if (existing != null) {
    existing.pending = target;
    return target;
  }
  _saveJobs[submissionId] = _SaveJob(target);
  // ignore: unawaited_futures
  _runSave(ref: ref, submissionId: submissionId, userId: userId, key: key);
  return target;
}

Future<void> _runSave({
  required WidgetRef ref,
  required String submissionId,
  required String userId,
  required ({String submissionId, String userId}) key,
}) async {
  final repo = ref.read(savedPostsRepositoryProvider);
  while (true) {
    final job = _saveJobs[submissionId];
    if (job == null) return;
    final target = job.target;
    try {
      if (target) {
        await repo.savePost(submissionId, userId);
      } else {
        await repo.unsavePost(submissionId, userId);
      }
    } catch (e) {
      AppLogger.error('[Save] Sync failed for $submissionId → $target', e);
      _saveJobs.remove(submissionId);
      ref.read(_optimisticSaved(key).notifier).state = null;
      ref.invalidate(isPostSavedProvider(key));
      return;
    }

    final pending = _saveJobs[submissionId]?.pending;
    if (pending != null && pending != target) {
      _saveJobs[submissionId] = _SaveJob(pending);
      continue;
    }

    _saveJobs.remove(submissionId);
    ref.invalidate(isPostSavedProvider(key));
    return;
  }
}
