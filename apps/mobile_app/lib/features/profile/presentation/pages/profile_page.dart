import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/providers/auth_session_provider.dart';
import 'package:app_models/app_models.dart';
import 'package:app_core/app_core.dart';
import 'package:app_repositories/app_repositories.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:app_contracts/app_contracts.dart';
import 'package:share_plus/share_plus.dart';
import '../../../../core/config/deep_link_config.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/services/analytics_service.dart';
import '../../../../core/services/sign_out_service.dart';
import '../../../../core/providers/current_profile_provider.dart';
import '../../../../core/utils/streak_utils.dart';
import '../../../follows/data/follows_providers.dart';
import '../../../follows/presentation/widgets/follow_button.dart';
import '../../../quests/data/quest_providers.dart';
import '../../../submissions/data/submission_providers.dart';
import '../../domain/badge_definitions.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../reactions/presentation/providers/reaction_controller.dart';
import '../../../reactions/presentation/widgets/bsheeel_dialog.dart';
import '../../../../design/bs_widgets.dart';
import '../providers/profile_realtime_provider.dart';

String _classFromLevel(int level) {
  if (level <= 5) return 'SCOUT';
  if (level <= 10) return 'WARRIOR';
  if (level <= 20) return 'MAGE';
  if (level <= 35) return 'CHAMPION';
  return 'LEGEND';
}

class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key, this.userId});
  final String? userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUser = ref.watch(authSessionProvider);
    final isViewingOther = userId != null && userId != currentUser?.id;
    // Realtime: any UPDATE on the profile row (XP, level, avatar, bio,
    // badges) refreshes this page automatically. Shell channels cover
    // follow counts + posts; this one covers the row itself.
    final watchedId = isViewingOther ? userId! : currentUser?.id;
    if (watchedId != null) {
      ref.watch(profileRealtimeProvider(watchedId));
    }
    final profileAsync = isViewingOther
        ? ref.watch(viewedProfileProvider(userId!))
        : ref.watch(currentProfileProvider);
    final l = AppLocalizations.of(context)!;

    return profileAsync.when(
      loading: () => const Scaffold(
        backgroundColor: QuestColors.osBg,
        body: Center(
            child: CircularProgressIndicator(
                color: QuestColors.osPrimary, strokeWidth: 2)),
      ),
      error: (e, _) => Scaffold(
        backgroundColor: QuestColors.osBg,
        body: Center(
            child: Text('Error: $e',
                style: const TextStyle(
                    fontFamily: 'DMSans',
                    fontVariations: [FontVariation('wght', 500)],
                    color: QuestColors.osRed))),
      ),
      data: (profile) {
        if (profile == null) {
          return Scaffold(
            backgroundColor: QuestColors.osBg,
            body: Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(l.failedToLoad,
                  style: const TextStyle(
                      fontFamily: 'Syne',
                      fontVariations: [FontVariation('wght', 800)],
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: QuestColors.osTextPrimary)),
              const SizedBox(height: 16),
              ChunkyButton(
                label: l.retry,
                onPressed: () => ref.invalidate(currentProfileProvider),
                variant: ChunkyVariant.primary,
              ),
              if (!isViewingOther) ...[
                const SizedBox(height: 12),
                ChunkyButton(
                  label: 'SIGN OUT',
                  onPressed: () async {
                    try {
                      await signOutAndCleanup(ref);
                      if (context.mounted) context.goNamed(RouteNames.login);
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Sign out failed: $e')));
                      }
                    }
                  },
                  variant: ChunkyVariant.surface,
                ),
              ],
            ])),
          );
        }

        final xpInLevel = profile.xp - (profile.level - 1) * 100;
        const xpForNextLevel = 100;
        final playerClass = _classFromLevel(profile.level);

        final questHistoryAsync = isViewingOther
            ? ref.watch(questHistoryByUserProvider(profile.id))
            : ref.watch(questHistoryProvider);
        final questHistory =
            questHistoryAsync.valueOrNull ?? const <UserQuestModel>[];
        final approvedQuests = questHistory
            .where((q) => q.status == UserQuestStatus.approved)
            .toList();

        final submissions = (isViewingOther
                    ? ref.watch(userSubmissionsByUserProvider(profile.id))
                    : ref.watch(userSubmissionsProvider))
                .valueOrNull ??
            const <SubmissionModel>[];

        final activityTimestamps = submissions.isNotEmpty
            ? submissions.map((s) => s.submittedAt)
            : questHistory
                .where((q) =>
                    q.status == UserQuestStatus.submitted ||
                    q.status == UserQuestStatus.approved ||
                    q.status == UserQuestStatus.rejected)
                .map((q) => q.completedAt ?? q.assignedAt);
        final activeDays = uniqueLocalDates(activityTimestamps);
        final streak = calculateCurrentStreakFromTimestamps(activityTimestamps);

        // Single source of truth: profiles.quests_completed is kept in
        // sync by the approval/revocation triggers, so it correctly drops
        // when a post is removed by admin or the user. MAX-of-multiple
        // sources used to inflate this past the real count whenever
        // attempted/submitted included a now-deleted quest.
        final displayedQuestCount = profile.questsCompleted;

        final socialQuestCount = approvedQuests
            .where((q) =>
                q.quest?.category == QuestCategory.social &&
                q.status == UserQuestStatus.approved)
            .length;
        final badges = allBadges;
        final xpProgress = (xpInLevel / xpForNextLevel).clamp(0.0, 1.0);

        // Hoisted out so every tab body can reuse the same handler.
        // Invalidates every cache the page surfaces and awaits the
        // re-fetches so the spinner stays visible until data is back.
        Future<void> handleRefresh() async {
          ref.invalidate(followCountsProvider(profile.id));
          if (isViewingOther) {
            ref.invalidate(viewedProfileProvider(profile.id));
            ref.invalidate(questHistoryByUserProvider(profile.id));
            ref.invalidate(userSubmissionsByUserProvider(profile.id));
            ref.invalidate(_savedPostsProvider(profile.id));
            await Future.wait<dynamic>([
              ref.read(viewedProfileProvider(profile.id).future),
              ref.read(questHistoryByUserProvider(profile.id).future),
              ref.read(userSubmissionsByUserProvider(profile.id).future),
              ref.read(followCountsProvider(profile.id).future),
            ]);
          } else {
            ref.invalidate(currentProfileProvider);
            ref.invalidate(questHistoryProvider);
            ref.invalidate(userSubmissionsProvider);
            ref.invalidate(_savedPostsProvider(profile.id));
            await Future.wait<dynamic>([
              ref.read(currentProfileProvider.future),
              ref.read(questHistoryProvider.future),
              ref.read(userSubmissionsProvider.future),
              ref.read(followCountsProvider(profile.id).future),
            ]);
          }
        }

        // Wraps a tab body in a RefreshIndicator. AlwaysScrollableScrollPhysics
        // ensures even short / empty bodies still accept the pull gesture.
        Widget refreshable(Widget child) {
          return RefreshIndicator(
            color: QuestColors.osPrimary,
            backgroundColor: QuestColors.osCard,
            onRefresh: handleRefresh,
            child: child,
          );
        }

        return DefaultTabController(
          length: isViewingOther ? 5 : 6,
          child: Scaffold(
            backgroundColor: QuestColors.osBg,
            body: SafeArea(
              child: NestedScrollView(
                headerSliverBuilder: (context, _) => [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                      child: Column(children: [
                        // ── Header row ────────────────────────────
                        Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(mainAxisSize: MainAxisSize.min, children: [
                                if (isViewingOther) ...[
                                  _IconBtn(
                                    icon: Icons.arrow_back_rounded,
                                    onTap: () => context.canPop()
                                        ? context.pop()
                                        : context.goNamed(RouteNames.profile),
                                  ),
                                  const SizedBox(width: 10),
                                ],
                                // Title only shows on the user's OWN profile.
                                // When viewing someone else, the big @handle
                                // here was redundant with the handle shown
                                // next to the avatar below — dropped.
                                if (!isViewingOther)
                                  Text(
                                    l.profile,
                                    style: const TextStyle(
                                      fontFamily: 'Syne',
                                      fontVariations: [
                                        FontVariation('wght', 800)
                                      ],
                                      fontSize: 22,
                                      fontWeight: FontWeight.w800,
                                      color: QuestColors.osTextPrimary,
                                      letterSpacing: -0.3,
                                    ),
                                  ),
                              ]),
                              Row(mainAxisSize: MainAxisSize.min, children: [
                                _IconBtn(
                                  icon: Icons.share_outlined,
                                  onTap: () {
                                    ref
                                        .read(analyticsProvider)
                                        .profileShared(profile.id);
                                    SharePlus.instance.share(ShareParams(
                                      text:
                                          'Check out @${profile.username} on BSHEEL!\n\n${DeepLinkConfig.profileLink(profile.id)}',
                                    ));
                                  },
                                ),
                                if (!isViewingOther) ...[
                                  const SizedBox(width: 8),
                                  _IconBtn(
                                    icon: Icons.settings_outlined,
                                    onTap: () =>
                                        context.pushNamed(RouteNames.settings),
                                  ),
                                ],
                              ]),
                            ]),
                        const SizedBox(height: 20),

                        // ── Avatar + info ─────────────────────────
                        Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Stack(clipBehavior: Clip.none, children: [
                                GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: () {
                                    if (profile.avatarUrl != null &&
                                        profile.avatarUrl!.isNotEmpty) {
                                      _openAvatarFullscreen(
                                        context,
                                        imageUrl: profile.avatarUrl!,
                                        heroTag: 'profile-avatar-${profile.id}',
                                      );
                                    }
                                  },
                                  child: Hero(
                                    tag: 'profile-avatar-${profile.id}',
                                    child: Container(
                                      width: 108,
                                      height: 108,
                                      decoration: BoxDecoration(
                                        gradient: const LinearGradient(colors: [
                                          QuestColors.osPrimary,
                                          QuestColors.osRed
                                        ]),
                                        border: Border.all(
                                            color: QuestColors.osTextPrimary,
                                            width:
                                                QuestSpacing.cardBorderWidth),
                                        borderRadius: BorderRadius.circular(28),
                                        boxShadow: const [
                                          BoxShadow(
                                              color: QuestColors.osTextPrimary,
                                              offset: Offset(0, 4))
                                        ],
                                      ),
                                      child: profile.avatarUrl != null &&
                                              profile.avatarUrl!.isNotEmpty
                                          ? ClipRRect(
                                              borderRadius:
                                                  BorderRadius.circular(26),
                                              child: CachedNetworkImage(
                                                imageUrl: profile.avatarUrl!,
                                                fit: BoxFit.cover,
                                                memCacheWidth: 200,
                                                errorWidget: (_, __, ___) =>
                                                    Center(
                                                        child: Text(
                                                  _avatarInitial(
                                                      profile.displayName),
                                                  style: const TextStyle(
                                                      fontFamily: 'Syne',
                                                      fontVariations: [
                                                        FontVariation(
                                                            'wght', 800)
                                                      ],
                                                      fontSize: 44,
                                                      fontWeight:
                                                          FontWeight.w800,
                                                      color: QuestColors
                                                          .osTextOnPrimary),
                                                )),
                                              ),
                                            )
                                          : Center(
                                              child: Text(
                                              _avatarInitial(
                                                  profile.displayName),
                                              style: const TextStyle(
                                                  fontFamily: 'Syne',
                                                  fontVariations: [
                                                    FontVariation('wght', 800)
                                                  ],
                                                  fontSize: 44,
                                                  fontWeight: FontWeight.w800,
                                                  color: QuestColors
                                                      .osTextOnPrimary),
                                            )),
                                    ),
                                  ),
                                ),
                                // Level badge
                                Positioned(
                                    right: -6,
                                    bottom: -6,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 7, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: QuestColors.osAccent,
                                        border: Border.all(
                                            color: QuestColors.osTextPrimary,
                                            width:
                                                QuestSpacing.cardBorderWidth),
                                        borderRadius: BorderRadius.circular(11),
                                      ),
                                      child: Text('L${profile.level}',
                                          style: const TextStyle(
                                              fontFamily: 'Syne',
                                              fontVariations: [
                                                FontVariation('wght', 800)
                                              ],
                                              fontSize: 11,
                                              fontWeight: FontWeight.w800,
                                              color: QuestColors.osAccentInk)),
                                    )),
                              ]),
                              const SizedBox(width: 16),
                              Expanded(
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                    FitText(profile.displayName,
                                        minFontSize: 12,
                                        style: const TextStyle(
                                            fontFamily: 'Syne',
                                            fontVariations: [
                                              FontVariation('wght', 800)
                                            ],
                                            fontSize: 20,
                                            fontWeight: FontWeight.w800,
                                            color: QuestColors.osTextPrimary)),
                                    FitText('@${profile.username}',
                                        minFontSize: 10,
                                        style: const TextStyle(
                                            fontFamily: 'DMSans',
                                            fontVariations: [
                                              FontVariation('wght', 500)
                                            ],
                                            fontSize: 13,
                                            color:
                                                QuestColors.osTextSecondary)),
                                    if (profile.bio != null &&
                                        profile.bio!.isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Text(profile.bio!,
                                          style: const TextStyle(
                                              fontFamily: 'DMSans',
                                              fontVariations: [
                                                FontVariation('wght', 500)
                                              ],
                                              fontSize: 12,
                                              color:
                                                  QuestColors.osTextSecondary),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis),
                                    ],
                                    const SizedBox(height: 6),
                                    BsChip(
                                      label: playerClass,
                                      bg: QuestColors.osPrimary.withAlpha(20),
                                      fg: QuestColors.osPrimary,
                                    ),
                                  ])),
                              const SizedBox(width: 8),
                              _FollowCountsBlock(userId: profile.id),
                            ]),
                        if (isViewingOther) ...[
                          const SizedBox(height: 16),
                          FollowButton(targetUserId: userId!),
                        ],
                        const SizedBox(height: 16),

                        // ── XP · level panel ──────────────────────
                        // The render draws this as a violet panel with
                        // white type and a gold meter, not as bare text on
                        // the cream page. It is the one block on the profile
                        // that states progress, so it gets the emphasis.
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                          decoration: BoxDecoration(
                            color: QuestColors.osPrimary,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: QuestColors.osTextPrimary,
                              width: 2,
                            ),
                            boxShadow: const [
                              BoxShadow(
                                color: QuestColors.osTextPrimary,
                                offset: Offset(4, 4),
                                blurRadius: 0,
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Flexible(
                                      child: Text('XP · LEVEL ${profile.level}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                              fontFamily: 'DMSans',
                                              fontVariations: [
                                                FontVariation('wght', 500)
                                              ],
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700,
                                              color:
                                                  QuestColors.osTextSecondary,
                                              letterSpacing: 0.4)),
                                    ),
                                    const SizedBox(width: 8),
                                    Flexible(
                                      child: Text(
                                          '$xpInLevel / $xpForNextLevel',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          textAlign: TextAlign.right,
                                          style: const TextStyle(
                                              fontFamily: 'Syne',
                                              fontVariations: [
                                                FontVariation('wght', 800)
                                              ],
                                              fontSize: 12,
                                              fontWeight: FontWeight.w800,
                                              color: QuestColors.pureWhite)),
                                    ),
                                  ]),
                              const SizedBox(height: 6),
                              ArcadeMeter(
                                  progress: xpProgress,
                                  fill: QuestColors.osAccent),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),

                        // ── Stat pills ────────────────────────────
                        Row(children: [
                          _StatPill(
                              value: '$displayedQuestCount', label: l.done),
                          const SizedBox(width: 8),
                          _StatPill(value: '${profile.xp}', label: 'XP'),
                          const SizedBox(width: 8),
                          _StatPill(value: '$streak', label: 'STREAK'),
                        ]),
                        const SizedBox(height: 16),
                      ]),
                    ),
                  ),
                  SliverPersistentHeader(
                    pinned: true,
                    delegate: _TabBarDelegate(
                      TabBar(
                        labelColor: QuestColors.osTextPrimary,
                        unselectedLabelColor: QuestColors.osTextMuted,
                        indicatorColor: QuestColors.osPrimary,
                        indicatorWeight: 3,
                        labelStyle: const TextStyle(
                            fontFamily: 'Syne',
                            fontVariations: [FontVariation('wght', 800)],
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.4),
                        unselectedLabelStyle: const TextStyle(
                            fontFamily: 'DMSans',
                            fontVariations: [FontVariation('wght', 500)],
                            fontSize: 12,
                            fontWeight: FontWeight.w600),
                        isScrollable: true,
                        tabAlignment: TabAlignment.start,
                        tabs: [
                          Tab(text: l.posts),
                          Tab(text: l.activity),
                          Tab(text: l.badges),
                          Tab(text: l.followers),
                          Tab(text: l.following),
                          if (!isViewingOther) const Tab(text: 'BSHEEEL'),
                        ],
                      ),
                      QuestColors.osBg,
                    ),
                  ),
                ],
                body: TabBarView(children: [
                  // Posts — own pull-to-refresh.
                  refreshable(ListView(
                    padding: const EdgeInsets.all(20),
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      _UserPostsGrid(submissions: submissions),
                    ],
                  )),

                  // Activity — own pull-to-refresh.
                  refreshable(ListView(
                    padding: const EdgeInsets.all(20),
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      _ActivityHeatmap(activeDays: activeDays),
                      const SizedBox(height: 20),
                      if (approvedQuests.isNotEmpty) ...[
                        BsSectionHeader(l.completedQuests),
                        GridView.builder(
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            mainAxisSpacing: 10,
                            crossAxisSpacing: 10,
                            childAspectRatio: 1.1,
                          ),
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: approvedQuests.length,
                          itemBuilder: (context, index) {
                            final uq = approvedQuests[index];
                            final quest = uq.quest;
                            return _CompletedQuestTile(
                              title: quest?.title ?? 'Quest',
                              category: quest?.category ?? '',
                              xp: quest?.xpReward ?? 0,
                              onTap: quest != null
                                  ? () => context.pushNamed(
                                      RouteNames.questDetails,
                                      pathParameters: {'id': uq.questId})
                                  : null,
                            );
                          },
                        ),
                      ],
                    ],
                  )),

                  // Badges — own pull-to-refresh.
                  refreshable(ListView.separated(
                    padding: const EdgeInsets.all(20),
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: badges.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final badge = badges[index];
                      final unlocked = badge.isUnlocked(
                          profile: profile,
                          streak: streak,
                          socialQuestCount: socialQuestCount);
                      final current = badge.currentValue(
                          profile: profile,
                          streak: streak,
                          socialQuestCount: socialQuestCount);
                      final progress =
                          (current / badge.targetValue).clamp(0.0, 1.0);
                      return GestureDetector(
                        onTap: () =>
                            _showBadgeDetail(context, badge, unlocked, current),
                        child: ChunkyCard(
                          shadow: false,
                          tint: unlocked
                              ? QuestColors.osPrimary.withAlpha(20)
                              : null,
                          padding: const EdgeInsets.all(14),
                          child: Row(children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: unlocked
                                    ? QuestColors.osPrimary.withAlpha(40)
                                    : QuestColors.osTextPrimary.withAlpha(15),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Icon(badge.icon,
                                  size: 22,
                                  color: unlocked
                                      ? QuestColors.osPrimary
                                      : QuestColors.osTextMuted),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                  Row(children: [
                                    Flexible(
                                      child: Text(badge.label,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                              fontFamily: 'Syne',
                                              fontVariations: const [
                                                FontVariation('wght', 800)
                                              ],
                                              fontSize: 13,
                                              fontWeight: FontWeight.w800,
                                              color: unlocked
                                                  ? QuestColors.osTextPrimary
                                                  : QuestColors
                                                      .osTextSecondary)),
                                    ),
                                    if (unlocked) ...[
                                      const SizedBox(width: 6),
                                      const Icon(Icons.check_circle,
                                          size: 14,
                                          color: QuestColors.osSuccess),
                                    ],
                                  ]),
                                  const SizedBox(height: 2),
                                  Text(badge.description,
                                      style: const TextStyle(
                                          fontFamily: 'DMSans',
                                          fontVariations: [
                                            FontVariation('wght', 500)
                                          ],
                                          fontSize: 11,
                                          color: QuestColors.osTextMuted)),
                                  const SizedBox(height: 6),
                                  ArcadeMeter(
                                    progress: progress,
                                    height: 8,
                                    fill: unlocked
                                        ? QuestColors.osSuccess
                                        : QuestColors.osPrimary,
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    unlocked
                                        ? l.completed
                                        : '$current / ${badge.targetValue}',
                                    style: TextStyle(
                                        fontFamily: 'DMSans',
                                        fontVariations: const [
                                          FontVariation('wght', 500)
                                        ],
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                        color: unlocked
                                            ? QuestColors.osSuccess
                                            : QuestColors.osTextMuted),
                                  ),
                                ])),
                            const Icon(Icons.chevron_right,
                                size: 16, color: QuestColors.osTextMuted),
                          ]),
                        ),
                      );
                    },
                  )),

                  // Followers — own pull-to-refresh.
                  refreshable(
                    _FollowListTab(userId: profile.id, isFollowers: true),
                  ),

                  // Following — own pull-to-refresh.
                  refreshable(
                    _FollowListTab(userId: profile.id, isFollowers: false),
                  ),

                  // BSHEEEL — own pull-to-refresh.
                  if (!isViewingOther)
                    refreshable(_SavedPostsTab(userId: profile.id)),
                ]),
              ),
            ),
          ),
        );
      },
    );
  }
}

void _showBadgeDetail(
    BuildContext context, BadgeDefinition badge, bool unlocked, int current) {
  final progress = (current / badge.targetValue).clamp(0.0, 1.0);
  showDialog(
    context: context,
    barrierColor: QuestColors.pureBlack.withAlpha(120),
    builder: (ctx) => Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
              decoration: BoxDecoration(
                color: QuestColors.osCard,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                    color: QuestColors.osTextPrimary,
                    width: QuestSpacing.cardBorderWidth),
                boxShadow: const [
                  BoxShadow(
                      color: QuestColors.osTextPrimary, offset: Offset(0, 5))
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: unlocked
                          ? QuestColors.osPrimary.withAlpha(25)
                          : QuestColors.osTextPrimary.withAlpha(15),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                          color: QuestColors.osTextPrimary,
                          width: QuestSpacing.cardBorderWidth),
                    ),
                    child: Icon(
                      badge.icon,
                      size: 36,
                      color: unlocked
                          ? QuestColors.osPrimary
                          : QuestColors.osTextMuted,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    badge.label,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontFamily: 'Syne',
                      fontVariations: [FontVariation('wght', 800)],
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: QuestColors.osTextPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    badge.rarity.label,
                    style: const TextStyle(
                      fontFamily: 'DMSans',
                      fontVariations: [FontVariation('wght', 500)],
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: QuestColors.osTextMuted,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    badge.description,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontFamily: 'DMSans',
                      fontVariations: [FontVariation('wght', 500)],
                      fontSize: 13,
                      color: QuestColors.osTextSecondary,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 20),
                  ArcadeMeter(
                    progress: progress,
                    height: 12,
                    fill: unlocked
                        ? QuestColors.osSuccess
                        : QuestColors.osPrimary,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    unlocked
                        ? AppLocalizations.of(context)!.completed
                        : '$current / ${badge.targetValue}',
                    style: TextStyle(
                      fontFamily: 'DMSans',
                      fontVariations: const [FontVariation('wght', 500)],
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: unlocked
                          ? QuestColors.osSuccess
                          : QuestColors.osTextMuted,
                    ),
                  ),
                  const SizedBox(height: 16),
                  GestureDetector(
                    onTap: () => Navigator.of(ctx).pop(),
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: QuestColors.osAccent,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: QuestColors.osTextPrimary,
                            width: QuestSpacing.cardBorderWidth),
                        boxShadow: const [
                          BoxShadow(
                              color: QuestColors.osTextPrimary,
                              offset: Offset(0, 3)),
                        ],
                      ),
                      alignment: Alignment.center,
                      child: const Text(
                        'CLOSE',
                        style: TextStyle(
                          fontFamily: 'Syne',
                          fontVariations: [FontVariation('wght', 800)],
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: QuestColors.osAccentInk,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

// ── Icon button ───────────────────────────────────────────────────────────────

class _IconBtn extends StatelessWidget {
  const _IconBtn({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: BsMinTouch(
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: QuestColors.osCard,
            border: Border.all(
                color: QuestColors.osTextPrimary,
                width: QuestSpacing.cardBorderWidth),
            borderRadius: BorderRadius.circular(12),
            boxShadow: const [
              BoxShadow(color: QuestColors.osTextPrimary, offset: Offset(0, 2))
            ],
          ),
          child: Icon(icon, size: 18, color: QuestColors.osTextPrimary),
        ),
      ),
    );
  }
}

// ── Stat pill ─────────────────────────────────────────────────────────────────

class _StatPill extends StatelessWidget {
  const _StatPill({required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: QuestColors.osCard,
          border: Border.all(
              color: QuestColors.osTextPrimary,
              width: QuestSpacing.cardBorderWidth),
          borderRadius: BorderRadius.circular(14),
          boxShadow: const [
            BoxShadow(color: QuestColors.osTextPrimary, offset: Offset(0, 2))
          ],
        ),
        child: Column(children: [
          // FittedBox lets a 6+ digit XP/streak/follower count shrink to
          // fit inside the pill on iPhone-SE-class screens instead of
          // overflowing.
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(value,
                maxLines: 1,
                style: const TextStyle(
                    fontFamily: 'Syne',
                    fontVariations: [FontVariation('wght', 800)],
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: QuestColors.osTextPrimary)),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(label,
                maxLines: 1,
                style: const TextStyle(
                    fontFamily: 'DMSans',
                    fontVariations: [FontVariation('wght', 500)],
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: QuestColors.osTextMuted,
                    letterSpacing: 0.8)),
          ),
        ]),
      ),
    );
  }
}

// ── Tab bar delegate ──────────────────────────────────────────────────────────

class _TabBarDelegate extends SliverPersistentHeaderDelegate {
  _TabBarDelegate(this.tabBar, this.bgColor);
  final TabBar tabBar;
  final Color bgColor;

  @override
  Widget build(
          BuildContext context, double shrinkOffset, bool overlapsContent) =>
      ColoredBox(color: bgColor, child: tabBar);

  @override
  double get maxExtent => tabBar.preferredSize.height;
  @override
  double get minExtent => tabBar.preferredSize.height;
  @override
  bool shouldRebuild(_TabBarDelegate _) => false;
}

// ── Activity heatmap ──────────────────────────────────────────────────────────

class _ActivityHeatmap extends StatefulWidget {
  const _ActivityHeatmap({required this.activeDays});
  final Set<DateTime> activeDays;

  @override
  State<_ActivityHeatmap> createState() => _ActivityHeatmapState();
}

class _ActivityHeatmapState extends State<_ActivityHeatmap> {
  bool _expanded = false;

  static const _monthNames = [
    'JANUARY',
    'FEBRUARY',
    'MARCH',
    'APRIL',
    'MAY',
    'JUNE',
    'JULY',
    'AUGUST',
    'SEPTEMBER',
    'OCTOBER',
    'NOVEMBER',
    'DECEMBER',
  ];

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();

    // Current month + previous 5 for the expanded view (newest first).
    final months = List.generate(
      6,
      (i) => DateTime(now.year, now.month - i, 1),
    );

    return GestureDetector(
      onTap: () => setState(() => _expanded = !_expanded),
      behavior: HitTestBehavior.opaque,
      child: ChunkyCard(
        shadow: false,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row with current month + expand chevron
            Row(
              children: [
                Text(
                  _monthNames[months.first.month - 1],
                  style: const TextStyle(
                    fontFamily: 'Syne',
                    fontVariations: [FontVariation('wght', 800)],
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: QuestColors.osTextPrimary,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${months.first.year}',
                  style: const TextStyle(
                    fontFamily: 'DMSans',
                    fontVariations: [FontVariation('wght', 500)],
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: QuestColors.osTextMuted,
                  ),
                ),
                const Spacer(),
                AnimatedRotation(
                  turns: _expanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 220),
                  child: const Icon(
                    Icons.expand_more_rounded,
                    color: QuestColors.osTextSecondary,
                    size: 22,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _MonthGrid(month: months.first, activeDays: widget.activeDays),
            AnimatedCrossFade(
              crossFadeState: _expanded
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 240),
              firstChild: const SizedBox(width: double.infinity),
              secondChild: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 1; i < months.length; i++) ...[
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Text(
                          _monthNames[months[i].month - 1],
                          style: const TextStyle(
                            fontFamily: 'Syne',
                            fontVariations: [FontVariation('wght', 800)],
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: QuestColors.osTextPrimary,
                            letterSpacing: 0.8,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '${months[i].year}',
                          style: const TextStyle(
                            fontFamily: 'DMSans',
                            fontVariations: [FontVariation('wght', 500)],
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: QuestColors.osTextMuted,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _MonthGrid(
                      month: months[i],
                      activeDays: widget.activeDays,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 10),
            Text(
              _expanded
                  ? 'TAP TO COLLAPSE  •  GREEN = ACTIVE DAY'
                  : 'TAP TO SEE MORE MONTHS  •  GREEN = ACTIVE DAY',
              style: const TextStyle(
                fontFamily: 'DMSans',
                fontVariations: [FontVariation('wght', 500)],
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: QuestColors.osTextMuted,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Renders a single calendar month as a 7-column grid with weekday labels.
/// Empty slots before day 1 and after the last day stay blank so the grid
/// aligns to real calendar dates (Monday-start).
class _MonthGrid extends StatelessWidget {
  const _MonthGrid({required this.month, required this.activeDays});
  final DateTime month;
  final Set<DateTime> activeDays;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final todayDate = DateTime(now.year, now.month, now.day);

    // Monday-start: Dart weekday = Mon=1 … Sun=7
    final firstDay = DateTime(month.year, month.month, 1);
    final leadingBlanks = firstDay.weekday - 1; // 0..6
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final totalCells = leadingBlanks + daysInMonth;
    final rowCount = (totalCells / 7).ceil();

    const weekdays = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

    return LayoutBuilder(builder: (context, constraints) {
      const gap = 4.0;
      final cellSize = ((constraints.maxWidth - gap * 6) / 7).floorToDouble();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Weekday labels
          Row(
            children: List.generate(7, (i) {
              return SizedBox(
                width: cellSize + (i < 6 ? gap : 0),
                child: Padding(
                  padding: EdgeInsets.only(right: i < 6 ? gap : 0),
                  child: Center(
                    child: Text(
                      weekdays[i],
                      style: const TextStyle(
                        fontFamily: 'DMSans',
                        fontVariations: [FontVariation('wght', 500)],
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: QuestColors.osTextMuted,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 6),
          for (var row = 0; row < rowCount; row++) ...[
            Row(
              children: List.generate(7, (col) {
                final cellIndex = row * 7 + col;
                final dayNum = cellIndex - leadingBlanks + 1;
                final inMonth = dayNum >= 1 && dayNum <= daysInMonth;
                Widget cell;
                if (!inMonth) {
                  cell = SizedBox(width: cellSize, height: cellSize);
                } else {
                  final date = DateTime(month.year, month.month, dayNum);
                  final isFuture = date.isAfter(todayDate);
                  final active = activeDays.contains(date);
                  final isToday = date == todayDate;
                  cell = Container(
                    width: cellSize,
                    height: cellSize,
                    decoration: BoxDecoration(
                      color: isFuture
                          ? QuestColors.osSurface.withAlpha(80)
                          : active
                              ? QuestColors.osSuccess
                              : QuestColors.osSurface,
                      border: Border.all(
                        color: isToday
                            ? QuestColors.osPrimary
                            : active
                                ? QuestColors.osTextPrimary
                                : QuestColors.osBorder,
                        width: isToday ? 1.8 : 1,
                      ),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '$dayNum',
                      style: TextStyle(
                        fontFamily: 'DMSans',
                        fontVariations: const [FontVariation('wght', 500)],
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: active
                            ? QuestColors.onAccent(QuestColors.osSuccess)
                            : isFuture
                                ? QuestColors.osTextMuted
                                : QuestColors.osTextSecondary,
                      ),
                    ),
                  );
                }
                return Padding(
                  padding: EdgeInsets.only(right: col < 6 ? gap : 0),
                  child: cell,
                );
              }),
            ),
            if (row < rowCount - 1) const SizedBox(height: gap),
          ],
        ],
      );
    });
  }
}

// ── Completed quest tile ──────────────────────────────────────────────────────

class _CompletedQuestTile extends StatelessWidget {
  const _CompletedQuestTile(
      {required this.title,
      required this.category,
      required this.xp,
      this.onTap});
  final String title, category;
  final int xp;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ChunkyCard(
      shadow: false,
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              BsChip(
                  label: category,
                  bg: QuestColors.osCool.withAlpha(30),
                  fg: QuestColors.osCool),
              const SizedBox(height: 6),
              Text(title,
                  style: const TextStyle(
                      fontFamily: 'Syne',
                      fontVariations: [FontVariation('wght', 800)],
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: QuestColors.osTextPrimary,
                      height: 1.2),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
            ]),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              BsChip(
                  label: '+$xp XP',
                  bg: QuestColors.osSuccess.withAlpha(30),
                  fg: QuestColors.osSuccess),
              const Icon(Icons.check_circle,
                  color: QuestColors.osSuccess, size: 18),
            ]),
          ]),
    );
  }
}

// ── User posts grid ───────────────────────────────────────────────────────────

class _UserPostsGrid extends StatelessWidget {
  const _UserPostsGrid({required this.submissions});
  final List<SubmissionModel> submissions;

  @override
  Widget build(BuildContext context) {
    // Profile grid shows only APPROVED, NON-DELETED posts. Pending /
    // rejected posts belong on the home page (IN REVIEW / REJECTED).
    // Belt-and-suspenders on the delete check: a post is treated as
    // deleted if EITHER the visibility flag is `deleted` OR `deletedAt`
    // is set, so a half-set row can never leak through.
    final visible = submissions
        .where((s) =>
            s.status == SubmissionStatus.approved &&
            s.visibility != SubmissionVisibility.deleted &&
            s.deletedAt == null)
        .toList();
    if (visible.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Center(
            child: Text(AppLocalizations.of(context)!.noPostsYet,
                style: const TextStyle(
                    fontFamily: 'DMSans',
                    fontVariations: [FontVariation('wght', 500)],
                    fontSize: 13,
                    color: QuestColors.osTextSecondary))),
      );
    }
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 2,
          crossAxisSpacing: 2,
          childAspectRatio: 1),
      itemCount: visible.length,
      itemBuilder: (context, index) {
        final s = visible[index];
        final thumb = s.mediaUrls.isNotEmpty ? s.mediaUrls.first : '';
        final isVideo = s.mediaType == MediaType.video ||
            thumb.toLowerCase().contains('.mp4') ||
            thumb.toLowerCase().contains('.mov');
        return GestureDetector(
          onTap: () => context.pushNamed(RouteNames.feedPostDetails,
              pathParameters: {'id': s.id}),
          child: Stack(fit: StackFit.expand, children: [
            if (thumb.isEmpty)
              const ColoredBox(color: QuestColors.osSurface)
            else if (isVideo)
              _GridVideoThumb(url: thumb)
            else
              CachedNetworkImage(
                imageUrl: thumb,
                fit: BoxFit.cover,
                memCacheWidth: 300,
                placeholder: (_, __) =>
                    const ColoredBox(color: QuestColors.osSurface),
                errorWidget: (_, __, ___) => const ColoredBox(
                    color: QuestColors.osSurface,
                    child: Icon(Icons.image_outlined,
                        size: 24, color: QuestColors.osTextMuted)),
              ),
            if (isVideo)
              const Positioned(
                  top: 4,
                  right: 4,
                  child: Icon(Icons.play_circle_outline,
                      size: 18, color: QuestColors.pureWhite)),
            if (s.mediaUrls.length > 1)
              const Positioned(
                  top: 4,
                  right: 4,
                  child: Icon(Icons.collections_outlined,
                      size: 16, color: QuestColors.pureWhite)),
            if (s.status != SubmissionStatus.approved)
              Positioned.fill(
                child: ColoredBox(
                    color: QuestColors.pureBlack.withAlpha(100),
                    child: Center(
                        child: Text(s.status.toUpperCase(),
                            style: TextStyle(
                                fontFamily: 'Syne',
                                fontVariations: const [
                                  FontVariation('wght', 800)
                                ],
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                color: s.status == SubmissionStatus.pending
                                    ? QuestColors.osAccent
                                    : QuestColors.osSuccess,
                                letterSpacing: 0.5)))),
              ),
          ]),
        );
      },
    );
  }
}

/// Thumbnail for a video tile in the profile grid. Spins up a
/// `VideoPlayerController` just long enough to seek to the first frame
/// and render it as a still image — never plays audio. Falls back to a
/// styled placeholder if the video fails to load.
class _GridVideoThumb extends StatefulWidget {
  const _GridVideoThumb({required this.url});
  final String url;

  @override
  State<_GridVideoThumb> createState() => _GridVideoThumbState();
}

class _GridVideoThumbState extends State<_GridVideoThumb> {
  VideoPlayerController? _ctrl;
  bool _ready = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final c = VideoPlayerController.networkUrl(Uri.parse(widget.url));
      await c.initialize();
      // Seek a little past 0 so we don't render a black frame.
      if (c.value.duration.inMilliseconds > 200) {
        await c.seekTo(const Duration(milliseconds: 200));
      }
      await c.setVolume(0);
      if (!mounted) {
        await c.dispose();
        return;
      }
      setState(() {
        _ctrl = c;
        _ready = true;
      });
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return const ColoredBox(
        color: QuestColors.osSurface,
        child: Icon(Icons.videocam_outlined,
            size: 24, color: QuestColors.osTextMuted),
      );
    }
    if (!_ready || _ctrl == null) {
      return const ColoredBox(color: QuestColors.osSurface);
    }
    // FittedBox + AspectRatio = cover-fit without distortion.
    return ClipRect(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: _ctrl!.value.size.width,
          height: _ctrl!.value.size.height,
          child: VideoPlayer(_ctrl!),
        ),
      ),
    );
  }
}

// ── Follow list tab ───────────────────────────────────────────────────────────

class _FollowListTab extends ConsumerStatefulWidget {
  const _FollowListTab({required this.userId, required this.isFollowers});
  final String userId;
  final bool isFollowers;

  @override
  ConsumerState<_FollowListTab> createState() => _FollowListTabState();
}

class _FollowListTabState extends ConsumerState<_FollowListTab> {
  List<FollowProfile> _users = const [];
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final users = await ref.read(followsRepositoryProvider).listConnections(
            userId: widget.userId,
            isFollowers: widget.isFollowers,
          );
      if (!mounted) return;
      setState(() {
        _users = users;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      AppLogger.error('[Profile] follow list load failed', e);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    if (_loading) return const BsheelLoading();
    if (_error != null) {
      return BsheelErrorState(
        error: _error!,
        action: 'load list',
        onRetry: _load,
      );
    }
    if (_users.isEmpty) {
      // UX-213: chunky empty state instead of plain dim text — matches
      // the rest of the app's empty surfaces.
      return BsheelEmptyState(
        title: widget.isFollowers ? l.noFollowersYet : l.notFollowingAnyone,
        icon: widget.isFollowers
            ? Icons.people_outline_rounded
            : Icons.person_add_outlined,
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(20),
      itemCount: _users.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final u = _users[index];
        final name = u.displayName.isNotEmpty ? u.displayName : u.username;
        return GestureDetector(
          onTap: () => context.pushNamed(RouteNames.userProfile,
              pathParameters: {'userId': u.id}),
          child: ChunkyCard(
              shadow: false,
              padding: const EdgeInsets.all(14),
              child: Row(children: [
                PixelAvatar(
                    imageUrl: u.avatarUrl, username: u.username, size: 36),
                const SizedBox(width: 12),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      FitText(name,
                          minFontSize: 10,
                          style: const TextStyle(
                              fontFamily: 'Syne',
                              fontVariations: [FontVariation('wght', 800)],
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: QuestColors.osTextPrimary)),
                      FitText('@${u.username}',
                          minFontSize: 9,
                          style: const TextStyle(
                              fontFamily: 'DMSans',
                              fontVariations: [FontVariation('wght', 500)],
                              fontSize: 11,
                              color: QuestColors.osTextSecondary)),
                    ])),
                const Icon(Icons.chevron_right,
                    size: 16, color: QuestColors.osTextMuted),
              ])),
        );
      },
    );
  }
}

// ── Saved posts tab ───────────────────────────────────────────────────────────

/// Loads BSHEEEL items in a single round-trip (RPC) — no per-tile detail
/// fetch. Filters out submissions whose visibility = 'deleted' server-side
/// so admin-removed posts don't surface as ghost rows.
final _savedPostsProvider = FutureProvider.autoDispose
    .family<List<SavedPostWithQuest>, String>((ref, userId) {
  return ref
      .watch(savedPostsRepositoryProvider)
      .getSavedPostsWithQuests(userId);
});

class _SavedPostsTab extends ConsumerWidget {
  const _SavedPostsTab({required this.userId});
  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final savedAsync = ref.watch(_savedPostsProvider(userId));
    return savedAsync.when(
      loading: () => const Center(
          child: CircularProgressIndicator(
              color: QuestColors.osPrimary, strokeWidth: 2)),
      error: (e, _) => Center(
          child: Text('Error: $e',
              style: const TextStyle(
                  fontFamily: 'DMSans',
                  fontVariations: [FontVariation('wght', 500)],
                  color: QuestColors.osRed))),
      data: (savedPosts) {
        if (savedPosts.isEmpty) {
          return Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.bookmark_border,
                size: 48, color: QuestColors.osTextMuted),
            const SizedBox(height: 16),
            Text(AppLocalizations.of(context)!.noSavedPostsYet,
                style: const TextStyle(
                    fontFamily: 'Syne',
                    fontVariations: [FontVariation('wght', 800)],
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: QuestColors.osTextPrimary)),
            const SizedBox(height: 8),
            Text(AppLocalizations.of(context)!.savedPostsHint,
                style: const TextStyle(
                    fontFamily: 'DMSans',
                    fontVariations: [FontVariation('wght', 500)],
                    fontSize: 12,
                    color: QuestColors.osTextSecondary)),
          ]));
        }
        return ListView.builder(
          padding: const EdgeInsets.all(20),
          itemCount: savedPosts.length,
          itemBuilder: (context, index) => _SavedPostTile(
            saved: savedPosts[index],
            userId: userId,
          ),
        );
      },
    );
  }
}

class _SavedPostTile extends ConsumerWidget {
  const _SavedPostTile({required this.saved, required this.userId});
  final SavedPostWithQuest saved;
  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: GestureDetector(
        // Main tap → confirm and take the quest as active.
        onTap: () => assignQuestFlow(
          context: context,
          ref: ref,
          questId: saved.questId,
          questTitle: saved.questTitle,
          userId: userId,
        ),
        behavior: HitTestBehavior.opaque,
        child: ChunkyCard(
          shadow: false,
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: QuestColors.osPrimary,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: QuestColors.osTextPrimary,
                    width: QuestSpacing.cardBorderWidth),
              ),
              alignment: Alignment.center,
              child: const Icon(Icons.flag_rounded,
                  color: QuestColors.osTextOnPrimary, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                saved.questTitle,
                style: const TextStyle(
                  fontFamily: 'Syne',
                  fontVariations: [FontVariation('wght', 800)],
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: QuestColors.osTextPrimary,
                  height: 1.2,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            // Unsave button — filled bookmark, tap removes from Bsheeel.
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _confirmUnsave(context, ref, saved.questTitle),
              child: BsMinTouch(
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: QuestColors.osAccent,
                    borderRadius: BorderRadius.circular(11),
                    border: Border.all(
                        color: QuestColors.osTextPrimary,
                        width: QuestSpacing.cardBorderWidth),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.bookmark_remove_rounded,
                    color: QuestColors.osAccentInk,
                    size: 20,
                  ),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Future<void> _confirmUnsave(
    BuildContext context,
    WidgetRef ref,
    String title,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        const ink = QuestColors.osTextPrimary;
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(28),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: QuestColors.osCard,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: ink, width: 2),
              boxShadow: const [
                BoxShadow(color: ink, offset: Offset(0, 4)),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: QuestColors.osRed,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: ink, width: 2),
                  ),
                  alignment: Alignment.center,
                  child: Icon(Icons.bookmark_remove_rounded,
                      color: QuestColors.onAccent(QuestColors.osRed), size: 24),
                ),
                const SizedBox(height: 12),
                const Text(
                  'REMOVE FROM BSHEEEL?',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Syne',
                    fontVariations: [FontVariation('wght', 800)],
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: ink,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'DMSans',
                    fontVariations: [FontVariation('wght', 500)],
                    fontSize: 12,
                    color: QuestColors.osTextMuted,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => Navigator.pop(ctx, false),
                        behavior: HitTestBehavior.opaque,
                        child: Container(
                          constraints:
                              const BoxConstraints(minHeight: kMinTouchTarget),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: QuestColors.osCard,
                            borderRadius: BorderRadius.circular(11),
                            border: Border.all(color: ink, width: 2),
                          ),
                          alignment: Alignment.center,
                          child: const Text(
                            'CANCEL',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: 'Syne',
                              fontVariations: [FontVariation('wght', 800)],
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: ink,
                              letterSpacing: 1,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => Navigator.pop(ctx, true),
                        behavior: HitTestBehavior.opaque,
                        child: Container(
                          constraints:
                              const BoxConstraints(minHeight: kMinTouchTarget),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: QuestColors.osRed,
                            borderRadius: BorderRadius.circular(11),
                            border: Border.all(color: ink, width: 2),
                            boxShadow: const [
                              BoxShadow(color: ink, offset: Offset(0, 3)),
                            ],
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            'REMOVE',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: 'Syne',
                              fontVariations: const [
                                FontVariation('wght', 800)
                              ],
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: QuestColors.onAccent(QuestColors.osRed),
                              letterSpacing: 1,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
    if (confirmed != true) return;
    await toggleSavePost(
      ref: ref,
      submissionId: saved.submissionId,
      userId: userId,
    );
    ref.invalidate(_savedPostsProvider(userId));
  }
}

/// Avatar fallback letter — uses `characters` to grapheme-cluster safely
/// (handles emoji, combining marks) and never raises RangeError on an
/// empty/blank display name.
String _avatarInitial(String? source) {
  final s = (source ?? '').trim();
  if (s.isEmpty) return '?';
  return s.characters.first.toUpperCase();
}

// ── Follower / following counts block ───────────────────────────────────────

/// Stacked FOLLOWERS / FOLLOWING numbers shown to the right of the
/// avatar+info row in the profile header. Reads from the
/// `followCountsProvider` family — pull-to-refresh invalidates it.
class _FollowCountsBlock extends ConsumerWidget {
  const _FollowCountsBlock({required this.userId});
  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(followCountsProvider(userId));
    final counts = async.valueOrNull;

    Widget cell(String value, String label, VoidCallback? onTap) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: QuestColors.osCard,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: QuestColors.osTextPrimary, width: 1.6),
            boxShadow: const [
              BoxShadow(
                  color: QuestColors.osTextPrimary, offset: Offset(1.5, 2))
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  value,
                  maxLines: 1,
                  style: const TextStyle(
                    fontFamily: 'Syne',
                    fontVariations: [FontVariation('wght', 800)],
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: QuestColors.osTextPrimary,
                    height: 1,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  maxLines: 1,
                  style: const TextStyle(
                    fontFamily: 'DMSans',
                    fontVariations: [FontVariation('wght', 500)],
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    color: QuestColors.osTextSecondary,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Tab order: Posts(0), Activity(1), Badges(2), Followers(3), Following(4).
    // Lives inside the DefaultTabController scope so animateTo works here.
    void switchTab(int index) {
      final controller = DefaultTabController.maybeOf(context);
      controller?.animateTo(index);
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        cell(
          counts == null ? '—' : '${counts.followers}',
          'FOLLOWERS',
          () => switchTab(3),
        ),
        const SizedBox(height: 6),
        cell(
          counts == null ? '—' : '${counts.following}',
          'FOLLOWING',
          () => switchTab(4),
        ),
      ],
    );
  }
}

// ── Avatar fullscreen viewer ────────────────────────────────────────────────

void _openAvatarFullscreen(
  BuildContext context, {
  required String imageUrl,
  required String heroTag,
}) {
  Navigator.of(context, rootNavigator: true).push(
    PageRouteBuilder(
      opaque: false,
      barrierColor: QuestColors.pureBlack,
      transitionDuration: const Duration(milliseconds: 220),
      reverseTransitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (_, animation, __) => FadeTransition(
        opacity: animation,
        child: _AvatarFullscreen(imageUrl: imageUrl, heroTag: heroTag),
      ),
    ),
  );
}

class _AvatarFullscreen extends StatelessWidget {
  const _AvatarFullscreen({required this.imageUrl, required this.heroTag});
  final String imageUrl;
  final String heroTag;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: QuestColors.pureBlack,
      body: Stack(
        children: [
          // Tap-outside dismisses.
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context).maybePop(),
            ),
          ),
          Center(
            child: Hero(
              tag: heroTag,
              child: InteractiveViewer(
                minScale: 1,
                maxScale: 4,
                child: CachedNetworkImage(
                  imageUrl: imageUrl,
                  fit: BoxFit.contain,
                  errorWidget: (_, __, ___) => Icon(
                    Icons.broken_image_outlined,
                    color: QuestColors.pureWhite
                        .withAlpha(QuestColors.alphaOverlay),
                    size: 64,
                  ),
                ),
              ),
            ),
          ),
          // X close button — top-left, above the safe area.
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 12,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => Navigator.of(context).maybePop(),
                child: BsMinTouch(
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: QuestColors.pureBlack.withAlpha(128),
                      shape: BoxShape.circle,
                      border:
                          Border.all(color: QuestColors.pureWhite, width: 2),
                    ),
                    child: const Icon(
                      Icons.close_rounded,
                      color: QuestColors.textPrimary,
                      size: 22,
                    ),
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
