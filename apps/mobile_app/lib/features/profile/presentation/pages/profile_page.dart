import 'package:app_contracts/app_contracts.dart';
import 'package:app_core/app_core.dart';
import 'package:app_models/app_models.dart';
import 'package:app_repositories/app_repositories.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:video_player/video_player.dart';

import '../../../../core/config/deep_link_config.dart';
import '../../../../core/providers/auth_session_provider.dart';
import '../../../../core/providers/current_profile_provider.dart';
import '../../../../core/providers/streak_provider.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/services/analytics_service.dart';
import '../../../../core/services/sign_out_service.dart';
import '../../../../core/utils/streak_utils.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../follows/data/follows_providers.dart';
import '../../../follows/presentation/widgets/follow_button.dart';
import '../../../map/data/map_providers.dart';
import '../../../map/presentation/map_page.dart' show DiscoveryProgress;
import '../../../quests/data/quest_providers.dart';
import '../../../reactions/presentation/providers/reaction_controller.dart';
import '../../../reactions/presentation/widgets/bsheeel_dialog.dart';
import '../../../submissions/data/submission_providers.dart';
import '../../domain/badge_definitions.dart';
import '../../domain/player_class.dart';
import '../providers/profile_realtime_provider.dart';
import '../widgets/business_card.dart';

/// Profile — the tabbed layout the legacy Bsheel app shipped.
///
/// A pinned header (avatar with level badge, name, class chip, follower
/// counts, XP bar, DONE / XP / STREAK pills) over a sticky tab bar:
/// POSTS · ACTIVITY · BADGES · FOLLOWERS · FOLLOWING, plus BSHEEEL on the
/// viewer's own profile. Every tab body pulls to refresh.
///
/// The data underneath is the current stack — server-derived streak, the
/// discovery-progress strip, the same providers the single-scroll version
/// read — only the presentation went back.
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
        body: SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(20, 20, 20, 20),
            child: ArcadeSkeletonList(itemCount: 5, itemHeight: 72),
          ),
        ),
      ),
      error: (e, _) => Scaffold(
        backgroundColor: QuestColors.osBg,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Text(
              mapDbError(e, action: 'load profile'),
              textAlign: TextAlign.center,
              style: QuestTypography.osBodyMedium
                  .copyWith(color: QuestColors.osRedText),
            ),
          ),
        ),
      ),
      data: (profile) {
        if (profile == null) {
          return Scaffold(
            backgroundColor: QuestColors.osBg,
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(l.failedToLoad,
                        style: QuestTypography.osHeadlineMedium),
                    const SizedBox(height: 16),
                    ArcadeButton(
                      label: l.retry,
                      expand: false,
                      onTap: () => ref.invalidate(currentProfileProvider),
                    ),
                    if (!isViewingOther) ...[
                      const SizedBox(height: 12),
                      ArcadeButton(
                        label: 'Sign out',
                        variant: ArcadeButtonVariant.secondary,
                        expand: false,
                        onTap: () async {
                          try {
                            await signOutAndCleanup(ref);
                            if (context.mounted) {
                              context.goNamed(RouteNames.login);
                            }
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                      content: Text('Sign out failed: $e')));
                            }
                          }
                        },
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        }

        // Linear curve: level n starts at (n-1)*100.
        final xpInLevel = profile.xp - (profile.level - 1) * 100;
        const xpForNextLevel = 100;
        final xpProgress = (xpInLevel / xpForNextLevel).clamp(0.0, 1.0);
        final playerClass = playerClassForLevel(profile.level);

        final questHistoryAsync = isViewingOther
            ? ref.watch(questHistoryByUserProvider(profile.id))
            : ref.watch(questHistoryProvider);
        final questHistory =
            questHistoryAsync.valueOrNull ?? const <UserQuestModel>[];
        final approvedQuests = questHistory
            .where((q) => q.status == UserQuestStatus.approved)
            .toList(growable: false);

        final submissions = (isViewingOther
                    ? ref.watch(userSubmissionsByUserProvider(profile.id))
                    : ref.watch(userSubmissionsProvider))
                .valueOrNull ??
            const <SubmissionModel>[];

        final activityTimestamps = (submissions.isNotEmpty
                ? submissions.map((s) => s.submittedAt)
                : questHistory
                    .where((q) =>
                        q.status == UserQuestStatus.submitted ||
                        q.status == UserQuestStatus.approved ||
                        q.status == UserQuestStatus.rejected)
                    .map((q) => q.completedAt ?? q.assignedAt))
            .toList(growable: false);
        final activeDays = uniqueLocalDates(activityTimestamps);

        // Server-derived (#46), per profile rather than per viewer: the
        // legacy page counted this on the client from whatever history page
        // had loaded, and later read the signed-in user's own streak on
        // everyone's profile.
        final streak = (isViewingOther
                    ? ref.watch(userStreakProvider(profile.id))
                    : ref.watch(streakProvider))
                .valueOrNull
                ?.current ??
            0;

        // Single source of truth: profiles.quests_completed is kept in sync
        // by the approval/revocation path, so it correctly drops when a post
        // is removed by an admin or the user.
        final displayedQuestCount = profile.questsCompleted;

        final socialQuestCount = approvedQuests
            .where((q) => q.quest?.category == QuestCategory.social)
            .length;
        final badges = allBadges;

        // Hoisted out so every tab body can reuse the same handler.
        // Invalidates every cache the page surfaces and awaits the
        // re-fetches so the spinner stays visible until data is back.
        Future<void> handleRefresh() async {
          ref.invalidate(followCountsProvider(profile.id));
          if (isViewingOther) {
            ref.invalidate(viewedProfileProvider(profile.id));
            ref.invalidate(questHistoryByUserProvider(profile.id));
            ref.invalidate(userSubmissionsByUserProvider(profile.id));
            ref.invalidate(userStreakProvider(profile.id));
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
            ref.invalidate(streakProvider);
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
        // on the bodies ensures even short / empty ones accept the pull.
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
              bottom: false,
              child: NestedScrollView(
                headerSliverBuilder: (context, _) => [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                      child: Column(
                        children: [
                          // ── Header row ────────────────────────────
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (isViewingOther) ...[
                                    _IconBtn(
                                      icon: Icons.arrow_back_rounded,
                                      semanticLabel: 'Back',
                                      onTap: () => context.canPop()
                                          ? context.pop()
                                          : context.goNamed(RouteNames.profile),
                                    ),
                                    const SizedBox(width: 10),
                                  ],
                                  // Title only on the user's OWN profile.
                                  // On someone else's the big @handle here
                                  // would repeat the one beside the avatar.
                                  if (!isViewingOther)
                                    Text(
                                      l.profile.toUpperCase(),
                                      style: QuestTypography.osDisplaySmall
                                          .copyWith(
                                        fontSize: 22,
                                        height: 1,
                                        letterSpacing: -0.3,
                                      ),
                                    ),
                                ],
                              ),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _IconBtn(
                                    icon: Icons.share_outlined,
                                    semanticLabel: 'Share profile',
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
                                      icon: Icons.edit_outlined,
                                      semanticLabel: 'Edit profile',
                                      onTap: () => context
                                          .pushNamed(RouteNames.editProfile),
                                    ),
                                    const SizedBox(width: 8),
                                    _IconBtn(
                                      icon: Icons.settings_outlined,
                                      semanticLabel: 'Settings',
                                      onTap: () => context
                                          .pushNamed(RouteNames.settings),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),

                          // ── Avatar + info ─────────────────────────
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              _LevelledAvatar(
                                profile: profile,
                                onTap: () {
                                  final url = profile.avatarUrl;
                                  if (url != null && url.isNotEmpty) {
                                    _openAvatarFullscreen(
                                      context,
                                      imageUrl: url,
                                      heroTag: 'profile-avatar-${profile.id}',
                                    );
                                  }
                                },
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    FitText(
                                      profile.displayName,
                                      minFontSize: 12,
                                      style: QuestTypography.osHeadlineLarge
                                          .copyWith(fontSize: 20, height: 1.1),
                                    ),
                                    FitText(
                                      '@${profile.username}',
                                      minFontSize: 10,
                                      style: QuestTypography.osBodySmall
                                          .copyWith(
                                              color:
                                                  QuestColors.osTextSecondary),
                                    ),
                                    if (profile.bio != null &&
                                        profile.bio!.isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        profile.bio!,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: QuestTypography.osBodySmall
                                            .copyWith(
                                                color: QuestColors
                                                    .osTextSecondary),
                                      ),
                                    ],
                                    const SizedBox(height: 6),
                                    _Chip(
                                      label: playerClass,
                                      bg: QuestColors.osPrimary.withAlpha(20),
                                      fg: QuestColors.osPrimary,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              _FollowCountsBlock(userId: profile.id),
                            ],
                          ),
                          if (isViewingOther) ...[
                            const SizedBox(height: 16),
                            FollowButton(targetUserId: userId!),
                          ],

                          // ── Business account ──────────────────────
                          // #14: the only thing being a business changes in
                          // this app. Own profile only — a business account
                          // is not public information here — and the widget
                          // renders nothing for everyone else, which is
                          // almost everyone.
                          if (!isViewingOther) ...[
                            const SizedBox(height: 16),
                            const BusinessCard(),
                          ],
                          const SizedBox(height: 14),
                          ref
                              .watch(mapProfileCountriesProvider(profile.id))
                              .when(
                                data: (countries) =>
                                    DiscoveryProgress(countries: countries),
                                loading: () => const LinearProgressIndicator(),
                                error: (_, __) => TextButton(
                                    onPressed: () => ref.invalidate(
                                        mapProfileCountriesProvider(
                                            profile.id)),
                                    child:
                                        const Text('RETRY DISCOVERY PROGRESS')),
                              ),
                          const SizedBox(height: 16),

                          // ── XP bar ────────────────────────────────
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'XP · LEVEL ${profile.level}',
                                style: QuestTypography.osLabelSmall.copyWith(
                                  color: QuestColors.osTextSecondary,
                                  letterSpacing: 0.4,
                                ),
                              ),
                              Text(
                                '$xpInLevel / $xpForNextLevel',
                                style: QuestTypography.osHeadlineSmall
                                    .copyWith(fontSize: 12),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          ArcadeMeter(
                            progress: xpProgress,
                            fill: QuestColors.osPrimary,
                            height: 12,
                          ),
                          const SizedBox(height: 16),

                          // ── Stat pills ────────────────────────────
                          Row(
                            children: [
                              _StatPill(
                                  value: '$displayedQuestCount', label: l.done),
                              const SizedBox(width: 8),
                              _StatPill(value: '${profile.xp}', label: 'XP'),
                              const SizedBox(width: 8),
                              _StatPill(value: '$streak', label: 'STREAK'),
                            ],
                          ),
                          const SizedBox(height: 16),
                        ],
                      ),
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
                        labelStyle: QuestTypography.osLabelMedium
                            .copyWith(fontSize: 12, letterSpacing: 0.4),
                        unselectedLabelStyle: QuestTypography.osLabelMedium
                            .copyWith(fontSize: 12, letterSpacing: 0.4),
                        isScrollable: true,
                        tabAlignment: TabAlignment.start,
                        tabs: [
                          Tab(text: l.posts.toUpperCase()),
                          Tab(text: l.activity.toUpperCase()),
                          Tab(text: l.badges.toUpperCase()),
                          Tab(text: l.followers.toUpperCase()),
                          Tab(text: l.following.toUpperCase()),
                          if (!isViewingOther) const Tab(text: 'BSHEEEL'),
                        ],
                      ),
                      QuestColors.osBg,
                    ),
                  ),
                ],
                body: TabBarView(
                  children: [
                    // Posts — own pull-to-refresh.
                    refreshable(ListView(
                      // Bottom clears the floating nav pill.
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        _UserPostsGrid(submissions: submissions),
                      ],
                    )),

                    // Activity — heatmap + completed quests.
                    refreshable(ListView(
                      // Bottom clears the floating nav pill.
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        _ActivityHeatmap(activeDays: activeDays),
                        if (approvedQuests.isNotEmpty) ...[
                          const SizedBox(height: 20),
                          _SectionLabel(l.completedQuests),
                          const SizedBox(height: 10),
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
                                          pathParameters: {'id': uq.questId},
                                        )
                                    : null,
                              );
                            },
                          ),
                        ],
                      ],
                    )),

                    // Badges — every badge with its progress.
                    refreshable(ListView.separated(
                      // Bottom clears the floating nav pill.
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
                      physics: const AlwaysScrollableScrollPhysics(),
                      itemCount: badges.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final badge = badges[index];
                        final unlocked = badge.isUnlocked(
                          profile: profile,
                          streak: streak,
                          socialQuestCount: socialQuestCount,
                        );
                        final current = badge.currentValue(
                          profile: profile,
                          streak: streak,
                          socialQuestCount: socialQuestCount,
                        );
                        return _BadgeRow(
                          badge: badge,
                          unlocked: unlocked,
                          current: current,
                          onTap: () => _showBadgeDetail(
                              context, badge, unlocked, current),
                        );
                      },
                    )),

                    // Followers / following — own pull-to-refresh.
                    refreshable(
                      _FollowListTab(userId: profile.id, isFollowers: true),
                    ),
                    refreshable(
                      _FollowListTab(userId: profile.id, isFollowers: false),
                    ),

                    // BSHEEEL — saved quests, own profile only.
                    if (!isViewingOther)
                      refreshable(_SavedPostsTab(userId: profile.id)),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ── Avatar with level badge ────────────────────────────────────────────────

/// The legacy 108pt avatar: violet→coral gradient behind the photo, ink
/// outline and shadow, and the `L{level}` gold badge pinned to its corner.
class _LevelledAvatar extends StatelessWidget {
  const _LevelledAvatar({required this.profile, required this.onTap});

  final ProfileModel profile;
  final VoidCallback onTap;

  static const double _size = 108;

  @override
  Widget build(BuildContext context) {
    final initial = Center(
      child: Text(
        _avatarInitial(profile.displayName),
        style: QuestTypography.osDisplayMedium.copyWith(
          fontSize: 44,
          color: QuestColors.osTextOnPrimary,
          height: 1,
        ),
      ),
    );
    final hasAvatar =
        profile.avatarUrl != null && profile.avatarUrl!.isNotEmpty;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Hero(
            tag: 'profile-avatar-${profile.id}',
            child: Container(
              width: _size,
              height: _size,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [QuestColors.osPrimary, QuestColors.osRed]),
                border: Border.all(
                    color: QuestColors.osTextPrimary,
                    width: QuestSpacing.cardBorderWidth),
                borderRadius: BorderRadius.circular(QuestSpacing.radiusSheet),
                boxShadow: QuestSpacing.shadowMd,
              ),
              child: hasAvatar
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(QuestSpacing.inner(
                          QuestSpacing.radiusSheet,
                          QuestSpacing.cardBorderWidth)),
                      child: CachedNetworkImage(
                        imageUrl: profile.avatarUrl!,
                        fit: BoxFit.cover,
                        memCacheWidth: 200,
                        errorWidget: (_, __, ___) => initial,
                      ),
                    )
                  : initial,
            ),
          ),
        ),
        // Level badge
        Positioned(
          right: -6,
          bottom: -6,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: QuestColors.osAccent,
              border: Border.all(
                  color: QuestColors.osTextPrimary,
                  width: QuestSpacing.cardBorderWidth),
              borderRadius: BorderRadius.circular(QuestSpacing.radiusSm),
            ),
            child: Text(
              'L${profile.level}',
              style: QuestTypography.osLabelSmall.copyWith(
                fontSize: 11,
                color: QuestColors.osAccentInk,
                height: 1.2,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Small tinted chip (class, category, XP) ───────────────────────────────

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.bg, required this.fg});
  final String label;
  final Color bg;
  final Color fg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(QuestSpacing.radiusChip),
      ),
      child: Text(
        label.toUpperCase(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: QuestTypography.osLabelSmall.copyWith(
          fontSize: 10,
          color: fg,
          letterSpacing: 0.8,
          height: 1.2,
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: QuestTypography.osLabelMedium.copyWith(
        color: QuestColors.osTextSecondary,
        letterSpacing: 1.6,
      ),
    );
  }
}

// ── Badge row (BADGES tab) ────────────────────────────────────────────────

class _BadgeRow extends StatelessWidget {
  const _BadgeRow({
    required this.badge,
    required this.unlocked,
    required this.current,
    required this.onTap,
  });

  final BadgeDefinition badge;
  final bool unlocked;
  final int current;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final progress = (current / badge.targetValue).clamp(0.0, 1.0);
    return ArcadeCard(
      onTap: onTap,
      backgroundColor:
          unlocked ? QuestColors.osPrimary.withAlpha(20) : QuestColors.osCard,
      borderRadius: QuestSpacing.radiusCard,
      shadowOffset: 0,
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: unlocked
                  ? QuestColors.osPrimary.withAlpha(40)
                  : QuestColors.osTextPrimary.withAlpha(15),
              borderRadius: BorderRadius.circular(QuestSpacing.radiusMd),
            ),
            child: Icon(badge.icon,
                size: 22,
                color:
                    unlocked ? QuestColors.osPrimary : QuestColors.osTextMuted),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        badge.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: QuestTypography.osHeadlineSmall.copyWith(
                          fontSize: 13,
                          color: unlocked
                              ? QuestColors.osTextPrimary
                              : QuestColors.osTextSecondary,
                        ),
                      ),
                    ),
                    if (unlocked) ...[
                      const SizedBox(width: 6),
                      const Icon(Icons.check_circle,
                          size: 14, color: QuestColors.osSuccess),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  badge.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: QuestTypography.osBodySmall
                      .copyWith(fontSize: 11, color: QuestColors.osTextMuted),
                ),
                const SizedBox(height: 6),
                ArcadeMeter(
                  progress: progress,
                  height: 8,
                  fill:
                      unlocked ? QuestColors.osSuccess : QuestColors.osPrimary,
                ),
                const SizedBox(height: 3),
                Text(
                  unlocked ? l.completed : '$current / ${badge.targetValue}',
                  style: QuestTypography.osLabelSmall.copyWith(
                    fontSize: 10,
                    color: unlocked
                        ? QuestColors.osSuccessText
                        : QuestColors.osTextMuted,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right,
              size: 16, color: QuestColors.osTextMuted),
        ],
      ),
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
                borderRadius: BorderRadius.circular(QuestSpacing.radiusHero),
                border: Border.all(
                    color: QuestColors.osTextPrimary,
                    width: QuestSpacing.cardBorderWidth),
                boxShadow: QuestSpacing.shadowLg,
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
                      borderRadius:
                          BorderRadius.circular(QuestSpacing.radiusHero),
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
                    style:
                        QuestTypography.osHeadlineLarge.copyWith(fontSize: 20),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    badge.rarity.label,
                    style: QuestTypography.osLabelSmall.copyWith(
                      fontSize: 10,
                      color: QuestColors.osTextMuted,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    badge.description,
                    textAlign: TextAlign.center,
                    style: QuestTypography.osBodyMedium.copyWith(
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
                    style: QuestTypography.osLabelSmall.copyWith(
                      fontSize: 11,
                      color: unlocked
                          ? QuestColors.osSuccessText
                          : QuestColors.osTextMuted,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ArcadeButton(
                    label: 'Close',
                    variant: ArcadeButtonVariant.secondary,
                    onTap: () => Navigator.of(ctx).pop(),
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

/// The recurring 44pt icon button: white ground, 2px ink, 3px ink shadow.
class _IconBtn extends StatelessWidget {
  const _IconBtn({
    required this.icon,
    required this.semanticLabel,
    required this.onTap,
  });
  final IconData icon;
  final String semanticLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: QuestSpacing.minTouchTarget,
          height: QuestSpacing.minTouchTarget,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: QuestColors.osCard,
            border: Border.all(
                color: QuestColors.osTextPrimary,
                width: QuestSpacing.cardBorderWidth),
            borderRadius: BorderRadius.circular(QuestSpacing.radiusButton),
            boxShadow: QuestSpacing.shadowSm,
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
          borderRadius: BorderRadius.circular(QuestSpacing.radiusMd),
          boxShadow: QuestSpacing.shadowSm,
        ),
        child: Column(
          children: [
            // FittedBox lets a 6+ digit XP/streak count shrink to fit inside
            // the pill on iPhone-SE-class screens instead of overflowing.
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                maxLines: 1,
                style: QuestTypography.osDisplayMedium
                    .copyWith(fontSize: 18, height: 1.1),
              ),
            ),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label.toUpperCase(),
                maxLines: 1,
                style: QuestTypography.osLabelSmall.copyWith(
                  fontSize: 9,
                  color: QuestColors.osTextMuted,
                  letterSpacing: 0.8,
                ),
              ),
            ),
          ],
        ),
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

    return Semantics(
      button: true,
      label: _expanded ? 'Collapse activity months' : 'Expand activity months',
      child: ArcadeCard(
        onTap: () => setState(() => _expanded = !_expanded),
        borderRadius: QuestSpacing.radiusCard,
        shadowOffset: 0,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row with current month + expand chevron
            Row(
              children: [
                Text(
                  _monthNames[months.first.month - 1],
                  style: QuestTypography.osHeadlineLarge
                      .copyWith(fontSize: 16, letterSpacing: 0.8),
                ),
                const SizedBox(width: 8),
                Text(
                  '${months.first.year}',
                  style: QuestTypography.osBodySmall.copyWith(
                    fontSize: 13,
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
                          style: QuestTypography.osHeadlineMedium
                              .copyWith(fontSize: 14, letterSpacing: 0.8),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '${months[i].year}',
                          style: QuestTypography.osBodySmall.copyWith(
                            fontSize: 11,
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
              style: QuestTypography.osLabelSmall.copyWith(
                fontSize: 9,
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
                      style: QuestTypography.osLabelSmall.copyWith(
                        fontSize: 9,
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
                      borderRadius:
                          BorderRadius.circular(QuestSpacing.radiusSegment),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '$dayNum',
                      style: QuestTypography.osLabelSmall.copyWith(
                        fontSize: 9,
                        color: active
                            // Ink on jade — white measures short of AA there.
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
  const _CompletedQuestTile({
    required this.title,
    required this.category,
    required this.xp,
    this.onTap,
  });
  final String title, category;
  final int xp;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ArcadeCard(
      onTap: onTap,
      borderRadius: QuestSpacing.radiusCard,
      shadowOffset: 0,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (category.isNotEmpty)
                _Chip(
                  label: category,
                  bg: QuestColors.osCool.withAlpha(30),
                  fg: QuestColors.osTextPrimary,
                ),
              const SizedBox(height: 6),
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: QuestTypography.osHeadlineSmall
                    .copyWith(fontSize: 12, height: 1.2),
              ),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _Chip(
                label: '+$xp XP',
                bg: QuestColors.osSuccess.withAlpha(30),
                fg: QuestColors.osSuccessText,
              ),
              const Icon(Icons.check_circle,
                  color: QuestColors.osSuccess, size: 18),
            ],
          ),
        ],
      ),
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
          child: Text(
            AppLocalizations.of(context)!.noPostsYet,
            style: QuestTypography.osBodyMedium
                .copyWith(color: QuestColors.osTextSecondary),
          ),
        ),
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
        final isVideo = s.mediaType == MediaType.video || isVideoUrl(thumb);
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
      // Chunky empty state instead of plain dim text — matches the rest of
      // the app's empty surfaces. In a scroll view so pull-to-refresh works.
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          BsheelEmptyState(
            title: widget.isFollowers ? l.noFollowersYet : l.notFollowingAnyone,
            icon: widget.isFollowers
                ? Icons.people_outline_rounded
                : Icons.person_add_outlined,
          ),
        ],
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: _users.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final u = _users[index];
        final name = u.displayName.isNotEmpty ? u.displayName : u.username;
        return ArcadeCard(
          onTap: () => context.pushNamed(RouteNames.userProfile,
              pathParameters: {'userId': u.id}),
          borderRadius: QuestSpacing.radiusCard,
          shadowOffset: 0,
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            PixelAvatar(imageUrl: u.avatarUrl, username: u.username, size: 36),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FitText(
                    name,
                    minFontSize: 10,
                    style:
                        QuestTypography.osHeadlineSmall.copyWith(fontSize: 14),
                  ),
                  FitText(
                    '@${u.username}',
                    minFontSize: 9,
                    style: QuestTypography.osBodySmall.copyWith(
                        fontSize: 11, color: QuestColors.osTextSecondary),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right,
                size: 16, color: QuestColors.osTextMuted),
          ]),
        );
      },
    );
  }
}

// ── Saved posts tab ───────────────────────────────────────────────────────────

/// Loads BSHEEEL items in a single round-trip — no per-tile detail fetch.
/// Filters out submissions whose visibility = 'deleted' server-side so
/// admin-removed posts don't surface as ghost rows.
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
    final l = AppLocalizations.of(context)!;
    return savedAsync.when(
      loading: () => const BsheelLoading(),
      error: (e, _) => BsheelErrorState(
        error: e,
        action: 'load saved quests',
        onRetry: () => ref.invalidate(_savedPostsProvider(userId)),
      ),
      data: (savedPosts) {
        if (savedPosts.isEmpty) {
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              BsheelEmptyState(
                title: l.noSavedPostsYet,
                message: l.savedPostsHint,
                icon: Icons.bookmark_border,
              ),
            ],
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
          physics: const AlwaysScrollableScrollPhysics(),
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
      child: ArcadeCard(
        // Main tap → confirm and take the quest as active.
        onTap: () => assignQuestFlow(
          context: context,
          ref: ref,
          questId: saved.questId,
          questTitle: saved.questTitle,
          userId: userId,
        ),
        borderRadius: QuestSpacing.radiusCard,
        shadowOffset: 0,
        padding: const EdgeInsets.all(14),
        child: Row(children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: QuestColors.osPrimary,
              borderRadius: BorderRadius.circular(QuestSpacing.radiusControl),
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
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: QuestTypography.osHeadlineSmall
                  .copyWith(fontSize: 14, height: 1.2),
            ),
          ),
          const SizedBox(width: 8),
          // Unsave button — filled bookmark, tap removes from Bsheeel.
          Semantics(
            button: true,
            label: 'Remove from BSHEEEL',
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _confirmUnsave(context, ref, saved.questTitle),
              child: Container(
                width: QuestSpacing.minTouchTarget,
                height: QuestSpacing.minTouchTarget,
                decoration: BoxDecoration(
                  color: QuestColors.osAccent,
                  borderRadius:
                      BorderRadius.circular(QuestSpacing.radiusButton),
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
              borderRadius: BorderRadius.circular(QuestSpacing.radiusHero),
              border: Border.all(color: ink, width: 2),
              boxShadow: QuestSpacing.shadowMd,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: QuestColors.osRed,
                    borderRadius: BorderRadius.circular(QuestSpacing.radiusMd),
                    border: Border.all(color: ink, width: 2),
                  ),
                  alignment: Alignment.center,
                  child: Icon(Icons.bookmark_remove_rounded,
                      color: QuestColors.onAccent(QuestColors.osRed), size: 24),
                ),
                const SizedBox(height: 12),
                Text(
                  'REMOVE FROM BSHEEEL?',
                  textAlign: TextAlign.center,
                  style: QuestTypography.osHeadlineMedium
                      .copyWith(fontSize: 15, letterSpacing: 1),
                ),
                const SizedBox(height: 4),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: QuestTypography.osBodySmall
                      .copyWith(color: QuestColors.osTextMuted),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: ArcadeButton(
                        label: 'Cancel',
                        variant: ArcadeButtonVariant.secondary,
                        size: ArcadeButtonSize.small,
                        onTap: () => Navigator.pop(ctx, false),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ArcadeButton(
                        label: 'Remove',
                        variant: ArcadeButtonVariant.destructive,
                        size: ArcadeButtonSize.small,
                        onTap: () => Navigator.pop(ctx, true),
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
/// `followCountsProvider` family — pull-to-refresh invalidates it — and
/// tapping either jumps to its tab.
class _FollowCountsBlock extends ConsumerWidget {
  const _FollowCountsBlock({required this.userId});
  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(followCountsProvider(userId));
    final counts = async.valueOrNull;

    Widget cell(String value, String label, VoidCallback? onTap) {
      return Semantics(
        button: true,
        label: '$value $label',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            constraints:
                const BoxConstraints(minHeight: QuestSpacing.minTouchTarget),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: QuestColors.osCard,
              borderRadius: BorderRadius.circular(QuestSpacing.radiusControl),
              border: Border.all(
                  color: QuestColors.osTextPrimary,
                  width: QuestSpacing.cardBorderWidth),
              boxShadow: QuestSpacing.shadowSm,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    value,
                    maxLines: 1,
                    style: QuestTypography.osDisplayMedium
                        .copyWith(fontSize: 16, height: 1),
                  ),
                ),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    maxLines: 1,
                    style: QuestTypography.osLabelSmall.copyWith(
                      fontSize: 9,
                      color: QuestColors.osTextSecondary,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Tab order: Posts(0), Activity(1), Badges(2), Followers(3), Following(4).
    // Lives inside the DefaultTabController scope so animateTo works here.
    void switchTab(int index) {
      DefaultTabController.maybeOf(context)?.animateTo(index);
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
                child: Container(
                  width: QuestSpacing.minTouchTarget,
                  height: QuestSpacing.minTouchTarget,
                  decoration: BoxDecoration(
                    color: QuestColors.pureBlack.withAlpha(128),
                    shape: BoxShape.circle,
                    border: Border.all(color: QuestColors.pureWhite, width: 2),
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
        ],
      ),
    );
  }
}
