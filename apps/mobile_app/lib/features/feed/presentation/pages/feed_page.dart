import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:app_core/app_core.dart';
import 'package:supabase_contracts/supabase_contracts.dart';

import '../../../../core/router/route_names.dart';
import '../../../../core/providers/auth_session_provider.dart';
import '../../../../core/services/analytics_service.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../comments/presentation/widgets/comments_section.dart';
import '../../../reactions/presentation/providers/reaction_controller.dart';
import '../../../reactions/presentation/widgets/bsheeel_dialog.dart';
import '../providers/feed_provider.dart';
import '../providers/post_realtime_provider.dart';
import '../widgets/comments_sheet.dart';
import '../widgets/feed_filter_sheet.dart';
import '../widgets/post_actions_sheet.dart';
import '../widgets/reels_card.dart';

/// Vertical full-screen Reels-style feed.
///
/// Each post is a full-screen page in a vertical [PageView]. The header
/// (FEED title, scope switch, sort filters) is overlaid on top of the media
/// so the post itself takes the entire viewport.
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

  @override
  void initState() {
    super.initState();
    _currentPage = ref.read(feedLastIndexProvider);
    _pageController = PageController(initialPage: _currentPage);
    _pageController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _pageController.removeListener(_onScroll);
    _pageController.dispose();
    super.dispose();
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
    final feedHasPosts = (feedAsync.valueOrNull?.posts.isNotEmpty ?? false);
    // Only fire `feedViewed` once the user has actually seen posts —
    // previously it fired on first hasValue even when the list was
    // empty, polluting the funnel with phantom views.
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
                  );
                }
                return RefreshIndicator(
                  color: QuestColors.softRed,
                  backgroundColor: QuestColors.osCard,
                  onRefresh: () async {
                    await ref
                        .read(feedProvider.notifier)
                        .changeSort(ref.read(feedSortProvider));
                  },
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

// ── Reels post host: wires data → ReelsCard ──────────────────────────────────

class _ReelsPostHost extends ConsumerWidget {
  const _ReelsPostHost({super.key, required this.post, required this.isActive});

  final dynamic post; // FeedPostModel
  final bool isActive;

  String _timeAgo(DateTime dt) => timeAgo(dt);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUser = ref.watch(authSessionProvider);
    final myVoteType = currentUser == null
        ? null
        : getEffectiveVoteType(ref, post.id, currentUser.id);
    final counts = getEffectiveVoteCounts(ref, post.id, post);
    final upvotes = counts[ReactionType.upvote] ?? 0;
    final downvotes = counts[ReactionType.downvote] ?? 0;
    final isSaved = currentUser == null
        ? false
        : getEffectiveSaved(ref, post.id, currentUser.id);

    final mediaUrls = (post.mediaUrls as List<dynamic>)
        .map((u) => u as String)
        .where((u) => u.isNotEmpty)
        .toList();

    // Only mark as collab if at least 2 members actually joined — a 1-of-N
    // versus/coop with nobody else is just a solo post.
    String? modeBadge;
    if (post.isCollab == true) {
      final n = (post.collabMemberCount as int?) ?? 0;
      if (n >= 2) {
        final mode = (post.collabMode as String?) ?? '';
        // The DB stores coop as `'with'` — surface it as the friendlier
        // "COOP · N" label for the badge instead of "WITH · N".
        final label = switch (mode) {
          'versus' => 'VERSUS',
          'with' => 'COOP',
          '' => 'COLLAB',
          _ => mode.toUpperCase(),
        };
        modeBadge = '$label · $n';
      }
    }

    return ReelsCard(
      submissionId: post.id,
      username: post.username,
      displayName: post.displayName,
      avatarUrl: post.avatarUrl,
      questTitle: post.questTitle,
      xpReward: post.xpReward,
      caption: post.caption,
      mediaUrls: mediaUrls,
      mediaType: post.mediaType,
      collabGroupId: post.collabGroupId as String?,
      collabMode: post.collabMode as String?,
      collabMembers: (post.collabMembers as List).cast(),
      expiresAt: post.expiresAt as DateTime?,
      upvoteCount: upvotes,
      downvoteCount: downvotes,
      myVoteType: myVoteType,
      isSaved: isSaved,
      timeAgo: _timeAgo(post.submittedAt),
      isActive: isActive,
      modeBadge: modeBadge,
      // Tap on the media surface is a no-op — the feed is consumption-only.
      // Comments, profile, save and report are reachable via the action
      // rail / username row. This mirrors IG Reels' single-purpose feed
      // (tap = pause/play on video; never navigate away).
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
        );
      },
    );
  }
}

// ── Top overlay (FEED title + scope segbar + sort chips) ─────────────────────

class _TopOverlay extends ConsumerWidget {
  const _TopOverlay();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scope = ref.watch(feedScopeProvider);
    final activeSort = ref.watch(feedSortProvider);
    final filterActive = activeSort != feedSortRecent;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 14),
      child: Row(
        children: [
          // Tabs anchored to the left edge — the search + filter actions
          // sit on the right and the remaining space is left empty so the
          // bar doesn't crowd the active video underneath it.
          Expanded(
            child: _FeedScopeTabs(
              value: scope,
              onChange: (s) => ref.read(feedProvider.notifier).changeScope(s),
            ),
          ),
          // Right: filter + search, smaller and translucent.
          _IconAction(
            icon: Icons.filter_list_rounded,
            badge: filterActive,
            onTap: () {
              HapticFeedback.lightImpact();
              showFeedFilterSheet(context, ref: ref);
            },
          ),
          const SizedBox(width: 8),
          _IconAction(
            icon: Icons.search,
            onTap: () {
              HapticFeedback.lightImpact();
              context.pushNamed(RouteNames.search);
            },
          ),
        ],
      ),
    );
  }
}

/// Centered IG-style segmented tabs — text only, active tab has a short
/// underline indicator and full-white text; inactive is 60% white.
class _FeedScopeTabs extends StatelessWidget {
  const _FeedScopeTabs({required this.value, required this.onChange});

  final String value;
  final ValueChanged<String> onChange;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.start,
      children: [
        _tab(label: 'Following', key: feedScopeFollowing),
        const SizedBox(width: 16),
        Container(
            width: 0.5,
            height: 14,
            color: QuestColors.textPrimary.withAlpha(120)),
        const SizedBox(width: 16),
        _tab(label: 'For You', key: feedScopeGlobal),
      ],
    );
  }

  Widget _tab({required String label, required String key}) {
    final active = value == key;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onChange(key);
      },
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
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
                Shadow(color: Colors.black54, blurRadius: 6),
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
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ],
      ),
    );
  }
}

/// Tiny translucent icon button used for the filter + search corner
/// actions. Replaces the chunky ink-bordered tiles.
class _IconAction extends StatelessWidget {
  const _IconAction({
    required this.icon,
    required this.onTap,
    this.badge = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool badge;

  @override
  Widget build(BuildContext context) {
    return _PressableScale(
      onTap: onTap,
      child: SizedBox(
        width: 32,
        height: 32,
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
                    color: Colors.black54, blurRadius: 8, offset: Offset(0, 1)),
              ],
            ),
            if (badge)
              Positioned(
                top: -1,
                right: -1,
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
    );
  }
}

// ── Loading / empty / error states ──────────────────────────────────────────

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: QuestColors.pureBlack,
      child: const Center(
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
  const _EmptyState({required this.title, required this.subtitle});
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: QuestColors.pureBlack,
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
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: QuestColors.pureWhite, width: 2.5),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [QuestColors.osPrimary, QuestColors.softRed],
                  ),
                ),
                child: const Icon(Icons.bookmark_border,
                    size: 36, color: QuestColors.osTextOnPrimary),
              ),
              const SizedBox(height: QuestSpacing.lg),
              Text(
                title,
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
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Container(
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
                child: const Icon(Icons.error_outline,
                    color: QuestColors.osTextOnPrimary, size: 36),
              ),
              const SizedBox(height: QuestSpacing.lg),
              Text(
                l.failedToLoad,
                style: QuestTypography.headlineSmall.copyWith(
                  color: QuestColors.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: QuestSpacing.md),
              GestureDetector(
                onTap: onRetry,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
                  decoration: BoxDecoration(
                    color: QuestColors.accentYellow,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: QuestColors.pureBlack, width: 2),
                  ),
                  child: Text(
                    l.retry.toUpperCase(),
                    style: const TextStyle(
                      color: QuestColors.pureBlack,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
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
