import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:app_core/app_core.dart';
import 'package:app_contracts/app_contracts.dart';
import 'package:app_models/app_models.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../../core/router/route_names.dart';
import '../../../../core/providers/auth_session_provider.dart';
import '../../../../core/services/analytics_service.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../comments/presentation/pages/comments_page.dart';
import '../../../reactions/presentation/providers/reaction_controller.dart';
import '../../../reactions/presentation/widgets/bsheeel_dialog.dart';
import '../providers/feed_provider.dart';
import '../providers/post_realtime_provider.dart';
// Imported for the sort keys. The render's header carries HOT / NEW /
// FOLLOWING and no filter button, so the sheet's own three extra sorts
// (most-upvoted, least-upvoted, graveyard) have no affordance here any
// more — see the audit note; the sheet itself is left intact.
import '../widgets/feed_filter_sheet.dart' show feedSortHot, feedSortRecent;
import '../widgets/feed_post_card.dart';
import '../widgets/post_actions_sheet.dart';

/// The feed: an inline header over a scrolling list of bordered post cards.
///
/// `export/mobile/09-feed.jpg` shows several posts per screen, each a white
/// `r16` card with a category-coloured shadow — not the full-screen vertical
/// `PageView` this page used to be. The reels player, its `PageController`,
/// the page-index state and the per-page autoplay plumbing are all gone;
/// nothing here plays video, so the list can never have four players
/// competing for the audio session (and the web build never reaches
/// `video_compress`). A video post shows a tap-to-play face and hands
/// playback to the post-detail screen, which owns a real player.
///
/// Everything behind the presentation is unchanged: the same providers, the
/// same sort/scope handling, the same pull-to-refresh, the same optimistic
/// vote logic.
class FeedPage extends ConsumerStatefulWidget {
  const FeedPage({super.key});

  @override
  ConsumerState<FeedPage> createState() => _FeedPageState();
}

class _FeedPageState extends ConsumerState<FeedPage> {
  /// Rough height of one card + its separator. A list of variable-height
  /// cards has no page index, so the scroll-depth analytics milestone is
  /// estimated from the offset instead of counted exactly.
  static const double _approxCardExtent = 430;

  /// Start the next page fetch while roughly three cards remain, matching
  /// the old `page >= length - 3` trigger.
  static const double _prefetchWindow = _approxCardExtent * 3;

  final _scroll = ScrollController();
  bool _feedViewTracked = false;
  int _lastMilestone = 0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final feedState = ref.read(feedProvider).valueOrNull;
    if (feedState == null) return;
    final position = _scroll.position;

    if (feedState.hasMore &&
        !feedState.isLoadingMore &&
        position.pixels >= position.maxScrollExtent - _prefetchWindow) {
      ref.read(feedProvider.notifier).loadMore();
    }

    final approxIndex = (position.pixels / _approxCardExtent).floor();
    if (approxIndex >= _lastMilestone + 5) {
      _lastMilestone = approxIndex - (approxIndex % 5);
      ref.read(analyticsProvider).feedScrolled(_lastMilestone);
    }
  }

  Future<void> _refresh() {
    // Same call the pull-to-refresh made before: re-run the current sort,
    // which the notifier resolves against the current scope.
    return ref
        .read(feedProvider.notifier)
        .changeSort(ref.read(feedSortProvider));
  }

  @override
  Widget build(BuildContext context) {
    // Realtime: new approved submissions and reaction/save edits flow in
    // without pull-to-refresh. autoDispose closes the channel on leaving.
    ref.watch(feedRealtimeProvider);

    // Nav-bar FEED taps bump the tick; scroll the live list back to the top
    // so the user sees the newest post rather than wherever they were.
    ref.listen<int>(feedScrollResetTickProvider, (prev, next) {
      if (prev == null || prev == next) return;
      if (!_scroll.hasClients) return;
      _lastMilestone = 0;
      _scroll.animateTo(
        0,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    });

    final feedAsync = ref.watch(feedProvider);
    final hasPosts = feedAsync.valueOrNull?.posts.isNotEmpty ?? false;
    // Only fire `feedViewed` once posts have actually been seen — firing on
    // first hasValue counted phantom views of an empty list.
    if (!_feedViewTracked && feedAsync.hasValue && hasPosts) {
      _feedViewTracked = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(analyticsProvider).feedViewed();
      });
    }

    return Scaffold(
      backgroundColor: QuestColors.osBg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const _FeedHeader(),
            Expanded(
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
                  // The nav pill floats over the content, so the last card
                  // needs to clear it.
                  final navInset =
                      MediaQuery.of(context).padding.bottom * 0.3 + 88;
                  return RefreshIndicator(
                    color: QuestColors.osPrimary,
                    backgroundColor: QuestColors.osCard,
                    onRefresh: _refresh,
                    child: ListView.separated(
                      controller: _scroll,
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: EdgeInsets.fromLTRB(14, 4, 14, navInset),
                      itemCount:
                          posts.length + (feedState.isLoadingMore ? 1 : 0),
                      separatorBuilder: (_, __) => const SizedBox(height: 14),
                      itemBuilder: (context, index) {
                        if (index >= posts.length) {
                          return const _LoadingMoreCard();
                        }
                        final post = posts[index];
                        return _FeedPostHost(
                          key: ValueKey(post.id),
                          post: post,
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Header: wordmark + sort / scope chips ───────────────────────────────────

/// `FEED` plus the `HOT` / `NEW` / `FOLLOWING` chips from the render.
///
/// This is an ordinary inline header now, not an overlay: the list scrolls
/// under nothing, so there is nothing to float above.
class _FeedHeader extends ConsumerWidget {
  const _FeedHeader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sort = ref.watch(feedSortProvider);
    final scope = ref.watch(feedScopeProvider);

    void setSort(String next) {
      HapticFeedback.selectionClick();
      ref.read(feedProvider.notifier).changeSort(next);
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 10),
      child: Row(
        children: [
          // The chip group always gets its natural width; the wordmark takes
          // what is left and shrinks into it. That keeps all three chips on
          // the row at 320dp instead of scrolling HOT off the left edge,
          // and nothing here can overflow.
          Expanded(
            child: FitText(
              'FEED',
              minFontSize: 18,
              style: QuestTypography.osDisplaySmall.copyWith(
                fontSize: 28,
                height: 1,
                letterSpacing: 0.5,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _HeaderChip(
                label: 'HOT',
                active: sort == feedSortHot,
                onTap: () => setSort(feedSortHot),
              ),
              const SizedBox(width: 8),
              _HeaderChip(
                label: 'NEW',
                active: sort == feedSortRecent,
                onTap: () => setSort(feedSortRecent),
              ),
              const SizedBox(width: 8),
              _HeaderChip(
                label: 'FOLLOWING',
                active: scope == feedScopeFollowing,
                onTap: () {
                  HapticFeedback.selectionClick();
                  ref.read(feedProvider.notifier).changeScope(
                        scope == feedScopeFollowing
                            ? feedScopeGlobal
                            : feedScopeFollowing,
                      );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Active = ink ground with cream type, idle = white with a 2px ink border,
/// both `r11`. Painted at ~30pt but hit at 44pt.
class _HeaderChip extends StatelessWidget {
  const _HeaderChip({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const ink = QuestColors.osTextPrimary;
    return Semantics(
      button: true,
      selected: active,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          height: QuestSpacing.minTouchTarget,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
              decoration: BoxDecoration(
                color: active ? ink : QuestColors.osCard,
                borderRadius: BorderRadius.circular(11),
                border: Border.all(color: ink, width: 2),
              ),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: QuestTypography.osLabelMedium.copyWith(
                  color: active ? QuestColors.osBg : ink,
                  fontSize: 11,
                  letterSpacing: 0.9,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Post host: wires providers → card ───────────────────────────────────────

/// Reads the reaction state for one post and hands the card plain values.
///
/// The optimistic vote / save logic is untouched — `toggleVote`,
/// `getEffectiveVoteCounts`, `getEffectiveVoteType` and `getEffectiveSaved`
/// are called exactly as the reels host called them.
class _FeedPostHost extends ConsumerWidget {
  const _FeedPostHost({super.key, required this.post});

  final FeedPostModel post;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUser = ref.watch(authSessionProvider);
    final myVoteType = currentUser == null
        ? null
        : getEffectiveVoteType(ref, post.id, currentUser.id);
    final counts = getEffectiveVoteCounts(ref, post.id, post);
    final isSaved = currentUser == null
        ? false
        : getEffectiveSaved(ref, post.id, currentUser.id);

    // Only a collab with at least two members who actually joined is a
    // collab; a 1-of-N versus with nobody else is just a solo post. The DB
    // stores coop as `'with'`, surfaced as the friendlier "COOP".
    String? modeBadge;
    if (post.isCollab && post.collabMemberCount >= 2) {
      final label = switch (post.collabMode ?? '') {
        CollabMode.versus => 'VERSUS',
        // The DB stores coop as `with`; the UI has always called it COOP.
        CollabMode.with_ => 'COOP',
        '' => 'COLLAB',
        final other => other.toUpperCase(),
      };
      modeBadge = '$label · ${post.collabMemberCount}';
    }

    void openDetails() {
      context.pushNamed(
        RouteNames.feedPostDetails,
        pathParameters: {'id': post.id},
      );
    }

    return GestureDetector(
      behavior: HitTestBehavior.deferToChild,
      // Report / block / share live behind a long press here. The render's
      // card has no overflow button, and the post-detail screen keeps the
      // same actions on its visible "…" menu one tap away.
      onLongPress: () {
        HapticFeedback.mediumImpact();
        showPostActionsSheet(
          context,
          ref: ref,
          postId: post.id,
          postUsername: post.username,
        );
      },
      child: FeedPostCard(
        post: post,
        upvotes: counts[ReactionType.upvote] ?? 0,
        downvotes: counts[ReactionType.downvote] ?? 0,
        isUpvoted: myVoteType == ReactionType.upvote,
        isDownvoted: myVoteType == ReactionType.downvote,
        isSaved: isSaved,
        timeAgoLabel: timeAgo(post.submittedAt),
        modeBadge: modeBadge,
        onOpen: openDetails,
        onUserTap: post.userId.isEmpty
            ? null
            : () => context.pushNamed(
                  RouteNames.userProfile,
                  pathParameters: {'userId': post.userId},
                ),
        onUpvote: currentUser == null
            ? null
            : () => toggleVote(
                  ref: ref,
                  submissionId: post.id,
                  userId: currentUser.id,
                  voteType: ReactionType.upvote,
                  baseCounts: counts,
                ),
        onDownvote: currentUser == null
            ? null
            : () => toggleVote(
                  ref: ref,
                  submissionId: post.id,
                  userId: currentUser.id,
                  voteType: ReactionType.downvote,
                  baseCounts: counts,
                ),
        onComment: () => openCommentsPage(context, submissionId: post.id),
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
      ),
    );
  }
}

// ── Loading / empty / error ─────────────────────────────────────────────────

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    // Card-shaped skeletons, so the structure is already right when the
    // posts land. In a scroll view because two 300pt blocks do not fit on
    // a short screen and a Column would overflow.
    return const SingleChildScrollView(
      physics: NeverScrollableScrollPhysics(),
      child: ArcadeSkeletonList(
        itemCount: 3,
        itemHeight: 300,
        spacing: 14,
        padding: EdgeInsets.fromLTRB(14, 4, 14, 14),
      ),
    );
  }
}

class _LoadingMoreCard extends StatelessWidget {
  const _LoadingMoreCard();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(top: 14),
      child: ArcadeSkeleton(height: 120, radius: 16),
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
    return RefreshIndicator(
      color: QuestColors.osPrimary,
      backgroundColor: QuestColors.osCard,
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(14, 40, 14, 40),
        children: [
          _StateCard(
            child: Column(
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: QuestColors.osSurface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: QuestColors.osTextPrimary,
                      width: 2,
                    ),
                  ),
                  child: const Icon(
                    Icons.photo_library_outlined,
                    size: 30,
                    color: QuestColors.osTextPrimary,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  title.toUpperCase(),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: QuestTypography.osHeadlineLarge.copyWith(
                    fontSize: 18,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  style: QuestTypography.osBodyMedium.copyWith(
                    color: QuestColors.osTextSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: _StateCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: QuestColors.osRed,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: QuestColors.osTextPrimary,
                    width: 2,
                  ),
                ),
                child: Icon(
                  Icons.wifi_off_rounded,
                  size: 30,
                  // Ink on coral, never white: white measures 3.03:1.
                  color: QuestColors.onAccent(QuestColors.osRed),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                l.failedToLoad.toUpperCase(),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: QuestTypography.osHeadlineLarge.copyWith(
                  fontSize: 18,
                  letterSpacing: 0.4,
                ),
              ),
              const SizedBox(height: 16),
              ArcadeButton(
                label: l.retry,
                icon: Icons.refresh_rounded,
                size: ArcadeButtonSize.small,
                onTap: onRetry,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A white `r16` panel with a square 3px ink shadow.
///
/// Not `ArcadeCard`: that primitive draws its shadow at `Offset(2, 3)`, and
/// hard shadows in this design are square. Worth fixing in `shared_ui`
/// itself — every caller inherits the 1px skew — but that file is not this
/// task's to edit.
class _StateCard extends StatelessWidget {
  const _StateCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    const ink = QuestColors.osTextPrimary;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: QuestColors.osCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: ink, width: 2),
        boxShadow: const [
          BoxShadow(color: ink, offset: Offset(3, 3), blurRadius: 0),
        ],
      ),
      child: child,
    );
  }
}
