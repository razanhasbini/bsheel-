import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app_models/app_models.dart';
import 'package:app_repositories/app_repositories.dart';
import 'package:flutter/foundation.dart';
import '../../../../core/providers/auth_session_provider.dart';
import '../../../../core/backend/app_backend.dart';

final feedRepositoryProvider = Provider<FeedRepository>((ref) {
  return AppBackend.repositories.feed;
});

/// Current feed sort mode, changed by the filter tabs.
final feedSortProvider = StateProvider<String>((ref) => 'recent');

/// Set to `true` while the feed has pushed a sub-route on top of itself
/// (user profile, post detail, etc). Reels video items watch this and pause
/// playback while it's true so audio doesn't keep going behind the new
/// screen, then resume automatically when it flips back to false.
final feedVideosPausedProvider = StateProvider<bool>((ref) => false);

/// Persistent mute state for all reels videos. Defaults to **sound on**
/// per product request — players want audio leading the experience. The
/// volume icon flips it for all subsequent cards so the user never has to
/// re-mute / re-unmute per post.
final feedVideoMutedProvider = StateProvider<bool>((ref) => false);

/// Last viewed page index in the vertical feed. Survives bottom-nav tab
/// switches (the FeedPage widget itself gets disposed, but Riverpod state
/// outlives it) so the user lands back on the post they were watching.
final feedLastIndexProvider = StateProvider<int>((ref) => 0);

/// Bumped by the bottom-nav FEED button to ask the feed to reset to the
/// top + refresh. The FeedPage listens to changes here and animates back
/// to page 0; the BottomNavShell increments and invalidates feedProvider
/// on the same tap.
final feedScrollResetTickProvider = StateProvider<int>((ref) => 0);

/// Current feed scope — 'global' (everyone) or 'following' (only users
/// the current user follows).
final feedScopeProvider = StateProvider<String>((ref) => 'global');

const feedScopeGlobal = 'global';
const feedScopeFollowing = 'following';

class FeedState {
  const FeedState({
    required this.posts,
    this.hasMore = true,
    this.isLoadingMore = false,
  });

  final List<FeedPostModel> posts;
  final bool hasMore;
  final bool isLoadingMore;

  FeedState copyWith({
    List<FeedPostModel>? posts,
    bool? hasMore,
    bool? isLoadingMore,
  }) {
    return FeedState(
      posts: posts ?? this.posts,
      hasMore: hasMore ?? this.hasMore,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    );
  }
}

// SWR cache so a transient feed fetch failure preserves the last loaded
// posts on screen instead of flashing "no reels".
FeedState? _lastGoodFeed;

/// Drops the module-scoped SWR cache. Call on sign-out so the next user
/// on the same device can't see the previous user's reels briefly.
void resetFeedCache() {
  _lastGoodFeed = null;
}

class FeedNotifier extends AsyncNotifier<FeedState> {
  static const int _pageSize = 20;
  // Monotonic token used by changeSort/changeScope so an older imperative
  // fetch can't overwrite a newer one (e.g. fast double-tap on sort tabs
  // or a sort+scope swap in flight when the user taps again).
  int _requestToken = 0;

  @override
  Future<FeedState> build() async {
    final user = ref.watch(authSessionProvider);
    if (user == null) {
      _lastGoodFeed = null;
      return const FeedState(posts: [], hasMore: false);
    }
    final sort = ref.watch(feedSortProvider);
    final scope = ref.watch(feedScopeProvider);
    try {
      final raw = await ref
          .watch(feedRepositoryProvider)
          .getFeed(
            limit: _pageSize,
            offset: 0,
            sort: sort,
            scope: _toFeedScope(scope),
          )
          .timeout(const Duration(seconds: 10));
      if (kDebugMode) {
        debugPrint(
            '[Feed] Loaded ${raw.length} posts (sort=$sort, scope=$scope)');
      }
      final fresh = FeedState(posts: raw, hasMore: raw.length >= _pageSize);
      _lastGoodFeed = fresh;
      return fresh;
    } catch (e, st) {
      if (kDebugMode) debugPrint('[Feed] ERROR loading feed: $e');
      if (kDebugMode) debugPrint('[Feed] Stack: $st');
      if (_lastGoodFeed != null && _lastGoodFeed!.posts.isNotEmpty) {
        if (kDebugMode) {
          debugPrint(
              '[Feed] Serving cached ${_lastGoodFeed!.posts.length} posts');
        }
        return _lastGoodFeed!;
      }
      // Cold-start failure with no cache: surface the error so the
      // _ErrorState in feed_page.dart fires with a real retry CTA.
      // Previously this returned an empty-but-data state, which looked
      // identical to "feed is genuinely empty" and gave the user no
      // recovery path beyond pull-to-refresh on an invisible scroll view.
      Error.throwWithStackTrace(e, st);
    }
  }

  // ARC-011: scope filtering moved server-side via the new `p_scope`
  // RPC parameter. The previous client-side `_applyScope` + heuristic
  // offset is gone — pagination is now consistent regardless of how
  // dense the followed-set is in any window.
  FeedScope _toFeedScope(String raw) {
    return raw == feedScopeFollowing ? FeedScope.following : FeedScope.all;
  }

  /// Switch sort mode — keeps showing current posts while loading new ones.
  Future<void> changeSort(String sort) async {
    final current = state.valueOrNull;
    ref.read(feedSortProvider.notifier).state = sort;
    // build() will re-run because it watches feedSortProvider. The
    // imperative fetch below is what keeps the prior posts visible
    // during the swap. Token-guard it so a stale fetch can't overwrite
    // the latest user intent if they tap again before this returns.
    final token = ++_requestToken;

    if (current != null && current.posts.isNotEmpty) {
      try {
        final scope = ref.read(feedScopeProvider);
        final raw = await ref.read(feedRepositoryProvider).getFeed(
              limit: _pageSize,
              offset: 0,
              sort: sort,
              scope: _toFeedScope(scope),
            );
        if (token != _requestToken) return;
        state = AsyncData(FeedState(
          posts: raw,
          hasMore: raw.length >= _pageSize,
        ));
      } catch (e) {
        if (kDebugMode) debugPrint('[Feed] Sort change failed: $e');
      }
    }
  }

  /// Switch scope — same background-swap pattern as sort.
  Future<void> changeScope(String scope) async {
    final currentScope = ref.read(feedScopeProvider);
    if (currentScope == scope) return;
    ref.read(feedScopeProvider.notifier).state = scope;
    final token = ++_requestToken;

    final current = state.valueOrNull;
    if (current != null && current.posts.isNotEmpty) {
      try {
        final sort = ref.read(feedSortProvider);
        final raw = await ref.read(feedRepositoryProvider).getFeed(
              limit: _pageSize,
              offset: 0,
              sort: sort,
              scope: _toFeedScope(scope),
            );
        if (token != _requestToken) return;
        state = AsyncData(FeedState(
          posts: raw,
          hasMore: raw.length >= _pageSize,
        ));
      } catch (e) {
        if (kDebugMode) debugPrint('[Feed] Scope change failed: $e');
      }
    }
  }

  Future<void> loadMore() async {
    final current = state.valueOrNull;
    if (current == null || !current.hasMore || current.isLoadingMore) return;

    state = AsyncData(current.copyWith(isLoadingMore: true));
    final sort = ref.read(feedSortProvider);
    final scope = ref.read(feedScopeProvider);

    try {
      // Page by the last row's keyset cursor, not by offset.
      //
      // Offset paging re-runs the whole ORDER BY for each page, so a score
      // changing between pages shifts every row after it: the same post
      // arrives twice and another is never shown at all. The server has
      // always returned a per-row cursor for exactly this; it was discarded.
      // Offset remains the fallback for a page whose rows predate the field.
      final cursor =
          current.posts.isEmpty ? null : current.posts.last.nextCursor;
      final raw = await ref.read(feedRepositoryProvider).getFeed(
            limit: _pageSize,
            offset: cursor == null ? current.posts.length : 0,
            cursor: cursor,
            sort: sort,
            scope: _toFeedScope(scope),
          );

      // Belt and braces: a cursor should make duplicates impossible, but the
      // fallback path cannot promise that, and appending a duplicate throws
      // on a keyed list.
      final seen = current.posts.map((post) => post.id).toSet();
      final fresh = raw.where((post) => !seen.contains(post.id)).toList();
      state = AsyncData(current.copyWith(
        posts: [...current.posts, ...fresh],
        // Judge by what the server returned, not by what survived
        // de-duplication: a full page that was entirely duplicate still
        // means there is more behind it.
        hasMore: raw.length >= _pageSize,
        isLoadingMore: false,
      ));
    } catch (e) {
      // Don't rethrow — that flipped the entire feed to AsyncError and
      // wiped every loaded post. Keep the posts the user already has,
      // mark hasMore false so we stop hammering, and log. The user can
      // pull-to-refresh from page 1 if they want a clean retry.
      if (kDebugMode) debugPrint('[Feed] loadMore page failed: $e');
      state = AsyncData(current.copyWith(
        isLoadingMore: false,
        hasMore: false,
      ));
    }
  }
}

final feedProvider =
    AsyncNotifierProvider<FeedNotifier, FeedState>(FeedNotifier.new);
