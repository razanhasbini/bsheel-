import 'package:app_contracts/app_contracts.dart';
import 'package:app_core/app_core.dart';
import 'package:app_models/app_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/providers/auth_session_provider.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/services/analytics_reporter.dart';
import '../../../../core/services/analytics_service.dart';
import '../../../../core/services/impression_tracker.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../comments/presentation/widgets/comments_section.dart';
import '../../../reactions/presentation/providers/reaction_controller.dart';
import '../../../reactions/presentation/widgets/bsheeel_dialog.dart';
import '../providers/feed_comment_count_provider.dart';
import '../providers/feed_provider.dart';
import '../providers/post_realtime_provider.dart';
import '../widgets/comments_sheet.dart';
import '../widgets/feed_filter_sheet.dart'
    show feedSortLabel, feedSortRecent, showFeedFilterSheet;
import '../widgets/post_actions_sheet.dart';
import '../widgets/reels_card.dart';

/// Vertical full-screen Reels-style feed — the feed as the legacy Bsheel app
/// shipped it.
///
/// Each post is a full-screen page in a vertical [PageView]. The header
/// (Following / For You, filter, search) is overlaid on top of the media so
/// the post itself takes the entire viewport. Video autoplays on the active
/// page only and pauses whenever a route is pushed over the feed.
///
/// Everything behind the presentation is the current stack: the same
/// providers, the same sort/scope handling, the same pull-to-refresh, the
/// same optimistic vote logic seeded from the feed row.
class FeedPage extends ConsumerStatefulWidget {
  const FeedPage({super.key});

  @override
  ConsumerState<FeedPage> createState() => _FeedPageState();
}

class _FeedPageState extends ConsumerState<FeedPage> {
  // Initial page comes from the persisted index so a tab-switch returns to
  // the post the user was watching. Riverpod state outlives the widget,
  // unlike the PageController itself.
  late final PageController _pageController;
  late int _currentPage;
  bool _feedViewTracked = false;

  /// #81 §28. One post fills the viewport here, so the settled page is the
  /// card being looked at — [ImpressionTracker] turns that plus a dwell into
  /// an impression. The list surfaces use `QuestImpression` instead.
  late final ImpressionTracker _impressions;

  @override
  void initState() {
    super.initState();
    _currentPage = ref.read(feedLastIndexProvider);
    _pageController = PageController(initialPage: _currentPage);
    _pageController.addListener(_onScroll);
    _impressions = ImpressionTracker(
      // The post is the source: its author is credited with the exposure.
      onImpression: (questId, sourceSubmissionId) =>
          ref.read(analyticsReporterProvider).impression(
                questId: questId,
                surface: AnalyticsSurfaces.feed,
                sourceSubmissionId: sourceSubmissionId,
              ),
      isForeground: () =>
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed,
    );
  }

  @override
  void deactivate() {
    // A route pushed over the feed, or the tab left. The card is no longer
    // being looked at, so a dwell in progress must not be credited.
    _impressions.onHidden();
    super.deactivate();
  }

  @override
  void dispose() {
    _impressions.dispose();
    _pageController.removeListener(_onScroll);
    _pageController.dispose();
    super.dispose();
  }

  /// Reports the post at [index] as seen, once it has been there long enough.
  void _markVisible(int index) {
    final posts = ref.read(feedProvider).valueOrNull?.posts;
    if (posts == null || index < 0 || index >= posts.length) return;
    _impressions.onVisible(posts[index].questId,
        sourceSubmissionId: posts[index].id);
  }

  void _onScroll() {
    final feedState = ref.read(feedProvider).valueOrNull;
    if (feedState == null) return;
    if (!_pageController.hasClients) return;
    final page = _pageController.page ?? 0;
    // Pre-fetch when within 3 cards of the end.
    if (feedState.hasMore &&
        !feedState.isLoadingMore &&
        page >= feedState.posts.length - 3) {
      ref.read(feedProvider.notifier).loadMore();
    }
  }

  void _onPageChanged(int index) {
    setState(() => _currentPage = index);
    _markVisible(index);
    // Persist so the next FeedPage mount returns to this post.
    ref.read(feedLastIndexProvider.notifier).state = index;
    // Track scroll milestone every 5 cards.
    if (index > 0 && index % 5 == 0) {
      ref.read(analyticsProvider).feedScrolled(index);
    }
    // Pre-warm comments for the post that just came into view, so when
    // the user taps the comment button the data is already in flight.
    final state = ref.read(feedProvider).valueOrNull;
    if (state != null && index < state.posts.length) {
      ref.read(commentsProvider(state.posts[index].id).future).ignore();
    }
  }

  Future<void> _refresh() {
    // Re-run the current sort, which the notifier resolves against the
    // current scope.
    return ref
        .read(feedProvider.notifier)
        .changeSort(ref.read(feedSortProvider));
  }

  @override
  Widget build(BuildContext context) {
    // Realtime: new approved submissions and reaction/save edits flow in
    // without pull-to-refresh. autoDispose ensures the channel closes when
    // the user leaves the FEED tab.
    ref.watch(feedRealtimeProvider);

    // Listen for nav-bar FEED button taps. The shell increments the tick;
    // we animate the live PageController back to 0 so the user sees the
    // top of the feed instead of staying on whichever post they were on.
    ref.listen<int>(feedScrollResetTickProvider, (prev, next) {
      if (prev == null || prev == next) return;
      if (!_pageController.hasClients) return;
      _pageController.animateToPage(
        0,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    });

    final feedAsync = ref.watch(feedProvider);
    final feedHasPosts = feedAsync.valueOrNull?.posts.isNotEmpty ?? false;
    // Only fire `feedViewed` once the user has actually seen posts — firing
    // on first hasValue counted phantom views of an empty list.
    if (!_feedViewTracked && feedAsync.hasValue && feedHasPosts) {
      _feedViewTracked = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(analyticsProvider).feedViewed();
        // Pre-warm comments for the very first post too. _onPageChanged
        // never fires for index 0, so without this the comment button on
        // the first card pays the full network round-trip.
        final state = ref.read(feedProvider).valueOrNull;
        if (state != null && state.posts.isNotEmpty) {
          ref.read(commentsProvider(state.posts.first.id).future).ignore();
        }
        // And for the same reason, the post the feed opens on would never
        // be counted as seen — including the one a returning user is put
        // back on, which is the most-looked-at card in the app.
        _markVisible(_currentPage);
      });
    }

    return Scaffold(
      backgroundColor: QuestColors.pureBlack,
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          // ── Feed body ─────────────────────────────────────────────────
          Positioned.fill(
            child: feedAsync.when(
              loading: () => const _LoadingView(),
              error: (e, _) => _ErrorState(
                onRetry: () => ref.invalidate(feedProvider),
              ),
              data: (feedState) {
                final posts = feedState.posts;
                if (posts.isEmpty) {
                  final l = AppLocalizations.of(context)!;
                  return _EmptyState(
                    title: l.noPostsYet,
                    subtitle: l.completeToAppear,
                    onRefresh: _refresh,
                  );
                }
                return RefreshIndicator(
                  color: QuestColors.softRed,
                  backgroundColor: QuestColors.osCard,
                  onRefresh: _refresh,
                  child: PageView.builder(
                    controller: _pageController,
                    scrollDirection: Axis.vertical,
                    onPageChanged: _onPageChanged,
                    itemCount: posts.length,
                    itemBuilder: (context, index) {
                      final post = posts[index];
                      return _ReelsPostHost(
                        key: ValueKey(post.id),
                        post: post,
                        isActive: index == _currentPage,
                      );
                    },
                  ),
                );
              },
            ),
          ),

          // ── Top overlay: header + scope ───────────────────────────────
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: _TopOverlay(),
            ),
          ),

          // ── Loading-more spinner at bottom of feed ────────────────────
          if (feedAsync.valueOrNull?.isLoadingMore ?? false)
            Positioned(
              bottom: 24,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: QuestColors.pureBlack.withAlpha(140),
                    shape: BoxShape.circle,
                  ),
                  child: const Padding(
                    padding: EdgeInsets.all(10),
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                          QuestColors.textPrimary),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Reels post host: wires providers → ReelsCard ─────────────────────────────

/// Reads the reaction state for one post and hands the card plain values.
///
/// The optimistic vote / save logic is seeded from the row: the feed carries
/// the viewer's vote, saved state and comment count, so none of the three
/// needs a per-card request.
class _ReelsPostHost extends ConsumerWidget {
  const _ReelsPostHost({
    super.key,
    required this.post,
    required this.isActive,
  });

  final FeedPostModel post;
  final bool isActive;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUser = ref.watch(authSessionProvider);
    final myVoteType = currentUser == null
        ? null
        : getEffectiveVoteType(ref, post.id, currentUser.id,
            seeded: post.viewerVote, hasSeed: true);
    final counts = getEffectiveVoteCounts(ref, post.id, post);
    final upvotes = counts[ReactionType.upvote] ?? 0;
    final downvotes = counts[ReactionType.downvote] ?? 0;
    final isSaved = currentUser == null
        ? false
        : getEffectiveSaved(ref, post.id, currentUser.id,
            seeded: post.viewerSaved);

    // The row's count is the seed; once the comments themselves have been
    // fetched (pre-warmed on page change) the live total wins, so a comment
    // posted from the sheet shows up in the bubble immediately.
    final liveCommentCount = ref.watch(feedCommentCountProvider(post.id));
    final commentCount =
        liveCommentCount > 0 ? liveCommentCount : post.commentCount;

    // Only a collab with at least two members who actually joined is a
    // collab; a 1-of-N versus with nobody else is just a solo post. The DB
    // stores coop as `with`, surfaced as the friendlier "COOP".
    String? modeBadge;
    if (post.isCollab && post.collabMemberCount >= 2) {
      final label = switch (post.collabMode ?? '') {
        CollabMode.versus => 'VERSUS',
        CollabMode.with_ => 'COOP',
        '' => 'COLLAB',
        final other => other.toUpperCase(),
      };
      modeBadge = '$label · ${post.collabMemberCount}';
    }

    return ReelsCard(
      submissionId: post.id,
      username: post.username,
      displayName: post.displayName,
      avatarUrl: post.avatarUrl,
      questTitle: post.questTitle,
      xpReward: post.xpReward,
      caption: post.caption,
      mediaUrls: post.mediaUrls.where((u) => u.isNotEmpty).toList(),
      mediaType: post.mediaType,
      journeyStops: post.journeyStops,
      journeyTitle: post.journeyTitle,
      collabGroupId: post.collabGroupId,
      collabMode: post.collabMode,
      collabMembers: post.collabMembers,
      expiresAt: post.expiresAt,
      upvoteCount: upvotes,
      downvoteCount: downvotes,
      commentCount: commentCount,
      myVoteType: myVoteType,
      isSaved: isSaved,
      timeAgo: timeAgo(post.submittedAt),
      isActive: isActive,
      modeBadge: modeBadge,
      // Tap on the media surface is a no-op — the feed is consumption-only.
      // Comments, profile, save and report are reachable via the action
      // rail / username row (tap = pause/play on video; never navigate
      // away). The post-detail screen stays reachable from the profile grid.
      onTap: null,
      onUserTap: post.userId.isNotEmpty
          ? () async {
              ref.read(feedVideosPausedProvider.notifier).state = true;
              await context.pushNamed(
                RouteNames.userProfile,
                pathParameters: {'userId': post.userId},
              );
              ref.read(feedVideosPausedProvider.notifier).state = false;
            }
          : null,
      onUpvote: currentUser == null
          ? null
          : () => toggleVote(
                ref: ref,
                submissionId: post.id,
                userId: currentUser.id,
                voteType: ReactionType.upvote,
                baseCounts: counts,
              ),
      // Double-tap = additive only. If the user already upvoted, this is
      // a no-op so rapid double-taps never accidentally remove the vote.
      // Removal must be done by tapping the upvote button itself.
      onDoubleTapUpvote: currentUser == null
          ? null
          : () {
              if (myVoteType == ReactionType.upvote) return;
              toggleVote(
                ref: ref,
                submissionId: post.id,
                userId: currentUser.id,
                voteType: ReactionType.upvote,
                baseCounts: counts,
              );
            },
      onDownvote: currentUser == null
          ? null
          : () => toggleVote(
                ref: ref,
                submissionId: post.id,
                userId: currentUser.id,
                voteType: ReactionType.downvote,
                baseCounts: counts,
              ),
      onSave: currentUser == null
          ? null
          : () => showBsheeelDialog(
                context: context,
                ref: ref,
                submissionId: post.id,
                questId: post.questId,
                questTitle: post.questTitle,
                userId: currentUser.id,
              ),
      onCommentTap: () {
        HapticFeedback.lightImpact();
        // Re-warm in case prefetch missed (cold tap, fast scroll, etc.).
        ref.read(commentsProvider(post.id).future).ignore();
        showCommentsSheet(context, submissionId: post.id);
      },
      onMoreTap: () {
        HapticFeedback.lightImpact();
        showPostActionsSheet(
          context,
          ref: ref,
          postId: post.id,
          postUsername: post.username,
          postUserId: post.userId,
          questTitle: post.questTitle,
          questCountryName: post.questCountryName,
          caption: post.caption,
          // Already signed by the feed read, so SAVE fetches the same bytes
          // the card is showing rather than signing a second time.
          mediaUrl:
              post.mediaUrls.firstWhere((u) => u.isNotEmpty, orElse: () => ''),
          mediaType: post.mediaType,
        );
      },
    );
  }
}

// ── Top overlay (scope tabs + filter + search) ───────────────────────────────

class _TopOverlay extends ConsumerWidget {
  const _TopOverlay();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scope = ref.watch(feedScopeProvider);
    final activeSort = ref.watch(feedSortProvider);
    final filterActive = activeSort != feedSortRecent;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              // Tabs anchored to the left edge — the search + filter actions
              // sit on the right and the remaining space is left empty so the
              // bar doesn't crowd the active video underneath it.
              Expanded(
                child: _FeedScopeTabs(
                  value: scope,
                  onChange: (s) =>
                      ref.read(feedProvider.notifier).changeScope(s),
                ),
              ),
              // Right: filter + search, small and translucent. The filter dot
              // lights up whenever a sort other than the default is applied.
              _IconAction(
                icon: Icons.filter_list_rounded,
                semanticLabel: 'Sort and filter',
                badge: filterActive,
                onTap: () {
                  HapticFeedback.lightImpact();
                  showFeedFilterSheet(context, ref: ref);
                },
              ),
              const SizedBox(width: 8),
              _IconAction(
                icon: Icons.search,
                semanticLabel: 'Search',
                onTap: () {
                  HapticFeedback.lightImpact();
                  context.pushNamed(RouteNames.search);
                },
              ),
            ],
          ),
          // The sheet is the only way to reach most-upvoted, least-upvoted
          // and graveyard, and a dot alone does not say *which* of them is
          // on. So once the feed is re-ordered a pill names the ordering and
          // clears it in one tap; on the default sort it is not there at all,
          // and the overlay is exactly the legacy one.
          if (filterActive) ...[
            const SizedBox(height: 6),
            _SortChip(
              label: feedSortLabel(activeSort),
              onClear: () {
                HapticFeedback.selectionClick();
                ref.read(feedProvider.notifier).changeSort(feedSortRecent);
              },
            ),
          ],
        ],
      ),
    );
  }
}

/// Translucent pill naming the active non-default sort, with a clear glyph.
class _SortChip extends StatelessWidget {
  const _SortChip({required this.label, required this.onClear});

  final String label;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Clear sort',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onClear,
        child: Container(
          constraints:
              const BoxConstraints(minHeight: QuestSpacing.minTouchTarget),
          padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
          decoration: BoxDecoration(
            color: QuestColors.pureBlack.withAlpha(140),
            borderRadius: BorderRadius.circular(QuestSpacing.radiusFull),
            border: Border.all(
                color: QuestColors.pureWhite.withAlpha(90), width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'SORTED BY $label',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: QuestColors.textPrimary,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.9,
                  height: 1,
                ),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.close_rounded,
                  size: 14, color: QuestColors.textPrimary),
            ],
          ),
        ),
      ),
    );
  }
}

/// IG-style segmented tabs — text only, active tab has a short underline
/// indicator and full-white text; inactive is ~60% white.
class _FeedScopeTabs extends StatelessWidget {
  const _FeedScopeTabs({required this.value, required this.onChange});

  final String value;
  final ValueChanged<String> onChange;

  @override
  Widget build(BuildContext context) {
    // Scale down rather than overflow when the two corner actions leave the
    // tabs less room than their natural width — a 320dp phone, or a large
    // accessibility font.
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _tab(label: 'Following', key: feedScopeFollowing),
          const SizedBox(width: 16),
          Container(
            width: 0.5,
            height: 14,
            color: QuestColors.textPrimary.withAlpha(120),
          ),
          const SizedBox(width: 16),
          _tab(label: 'For You', key: feedScopeGlobal),
        ],
      ),
    );
  }

  Widget _tab({required String label, required String key}) {
    final active = value == key;
    return Semantics(
      button: true,
      selected: active,
      label: label,
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          onChange(key);
        },
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          height: QuestSpacing.minTouchTarget,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: active
                      ? QuestColors.textPrimary
                      : QuestColors.textPrimary.withAlpha(160),
                  fontSize: 15,
                  fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                  shadows: const [
                    Shadow(color: QuestColors.pureBlack, blurRadius: 6),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: active ? 18 : 0,
                height: 2.5,
                decoration: BoxDecoration(
                  color: QuestColors.textPrimary,
                  borderRadius: BorderRadius.circular(QuestSpacing.radiusPip),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tiny translucent icon button used for the filter + search corner
/// actions — the glyph floats on the media with a soft shadow.
class _IconAction extends StatelessWidget {
  const _IconAction({
    required this.icon,
    required this.semanticLabel,
    required this.onTap,
    this.badge = false,
  });

  final IconData icon;
  final String semanticLabel;
  final VoidCallback onTap;
  final bool badge;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      child: _PressableScale(
        onTap: onTap,
        child: SizedBox(
          width: QuestSpacing.minTouchTarget,
          height: QuestSpacing.minTouchTarget,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Icon(
                icon,
                color: QuestColors.textPrimary,
                size: 24,
                shadows: const [
                  Shadow(
                      color: QuestColors.pureBlack,
                      blurRadius: 8,
                      offset: Offset(0, 1)),
                ],
              ),
              if (badge)
                Positioned(
                  top: 6,
                  right: 6,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: QuestColors.softRed,
                      shape: BoxShape.circle,
                      border:
                          Border.all(color: QuestColors.pureWhite, width: 1.2),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Loading / empty / error states ──────────────────────────────────────────

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: QuestColors.pureBlack,
      child: Center(
        child: SizedBox(
          width: 36,
          height: 36,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            valueColor: AlwaysStoppedAnimation<Color>(QuestColors.textPrimary),
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.title,
    required this.subtitle,
    required this.onRefresh,
  });

  final String title;
  final String subtitle;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    // Wrapped in a scroll view so pull-to-refresh still works on an empty
    // feed — otherwise the only way back is a tab switch.
    return ColoredBox(
      color: QuestColors.pureBlack,
      child: RefreshIndicator(
        color: QuestColors.softRed,
        backgroundColor: QuestColors.osCard,
        onRefresh: onRefresh,
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(QuestSpacing.lg),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          borderRadius:
                              BorderRadius.circular(QuestSpacing.radiusCard),
                          border: Border.all(
                              color: QuestColors.pureWhite, width: 2.5),
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              QuestColors.osPrimary,
                              QuestColors.softRed
                            ],
                          ),
                        ),
                        child: const Icon(Icons.bookmark_border,
                            size: 36, color: QuestColors.osTextOnPrimary),
                      ),
                      const SizedBox(height: QuestSpacing.lg),
                      Text(
                        title,
                        textAlign: TextAlign.center,
                        style: QuestTypography.headlineSmall.copyWith(
                          color: QuestColors.textPrimary,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        subtitle,
                        textAlign: TextAlign.center,
                        style: QuestTypography.bodyMedium.copyWith(
                          color: QuestColors.textPrimary.withAlpha(170),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return ColoredBox(
      color: QuestColors.pureBlack,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(QuestSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: QuestColors.softRed,
                  shape: BoxShape.circle,
                  border: Border.all(color: QuestColors.pureWhite, width: 2.5),
                ),
                child: Icon(Icons.error_outline,
                    // Ink on coral, never white: white measures 3.03:1.
                    color: QuestColors.onAccent(QuestColors.softRed),
                    size: 36),
              ),
              const SizedBox(height: QuestSpacing.lg),
              Text(
                l.failedToLoad,
                textAlign: TextAlign.center,
                style: QuestTypography.headlineSmall.copyWith(
                  color: QuestColors.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: QuestSpacing.md),
              Semantics(
                button: true,
                child: GestureDetector(
                  onTap: onRetry,
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    constraints: const BoxConstraints(
                        minHeight: QuestSpacing.minTouchTarget),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 22, vertical: 10),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: QuestColors.accentYellow,
                      borderRadius:
                          BorderRadius.circular(QuestSpacing.radiusControl),
                      border:
                          Border.all(color: QuestColors.pureBlack, width: 2),
                    ),
                    child: Text(
                      l.retry.toUpperCase(),
                      style: TextStyle(
                        color: QuestColors.onAccent(QuestColors.accentYellow),
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Press-scale tap feedback ────────────────────────────────────────────────

class _PressableScale extends StatefulWidget {
  const _PressableScale({required this.child, this.onTap});
  final Widget child;
  final VoidCallback? onTap;

  @override
  State<_PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<_PressableScale> {
  double _scale = 1.0;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _scale = 0.92),
      onTapCancel: () => setState(() => _scale = 1.0),
      onTapUp: (_) {
        setState(() => _scale = 1.0);
        widget.onTap?.call();
      },
      child: AnimatedScale(
        scale: _scale,
        duration: const Duration(milliseconds: 90),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}
