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
import '../../../../core/providers/streak_provider.dart';
import '../../../../core/utils/streak_utils.dart';
import '../../../follows/data/follows_providers.dart';
import '../../../follows/presentation/widgets/follow_button.dart';
import '../../../quests/data/quest_providers.dart';
import '../../../submissions/data/submission_providers.dart';
import '../../domain/badge_definitions.dart';
import '../../domain/player_class.dart';
import '../../../map/data/map_providers.dart';
import '../../../map/presentation/map_page.dart' show DiscoveryProgress;
import '../../../../l10n/app_localizations.dart';
import '../../../reactions/presentation/providers/reaction_controller.dart';
import '../../../reactions/presentation/widgets/bsheeel_dialog.dart';
import '../providers/profile_realtime_provider.dart';

/// Profile — built to `export/mobile/12-profile.jpg`.
///
/// One scroll, no tab bar: header (avatar · name · EDIT), the violet XP panel
/// with its gold meter and rank ladder, three stat tiles, BADGES, ACTIVITY.
/// The frame draws nothing below the activity strip, so the six tab bodies
/// this page used to carry moved behind the controls that name them —
/// POSTS / FOLLOWERS / FOLLOWING open sheets, the locked badge tile opens the
/// full badge list. Saved posts ride the POSTS sheet as a second chip, since
/// this page is their only entry point. The old ACTIVITY tab's
/// completed-quests grid is gone: `quest_history_page.dart` already renders
/// it and is reachable from home.

// Badge tile tints, in the frame's order: gold, jade, coral, then sky and
// violet for anyone who unlocks more than three.
const _badgeTints = <Color>[
  QuestColors.osAccent,
  QuestColors.osSuccess,
  QuestColors.osRed,
  QuestColors.osCool,
  QuestColors.osPrimary,
];

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

        // XP maths follows the app's own linear curve — level n starts at
        // (n-1)*100 — but is *presented* the way the frame sets it: total XP
        // over the next level's threshold, e.g. "4,180 / 4,600".
        final xpInLevel = profile.xp - (profile.level - 1) * 100;
        final nextThreshold = profile.level * 100;
        final xpProgress = (xpInLevel / 100).clamp(0.0, 1.0);
        final playerClass = playerClassForLevel(profile.level);

        final questHistoryAsync = isViewingOther
            ? ref.watch(questHistoryByUserProvider(profile.id))
            : ref.watch(questHistoryProvider);
        final questHistory =
            questHistoryAsync.valueOrNull ?? const <UserQuestModel>[];

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
        // Server-derived (#46). The old client calculation read whatever
        // history page was loaded, counted rejected attempts, and bucketed by
        // local date while the reminder job uses UTC.
        final streak = ref.watch(streakProvider).valueOrNull?.current ?? 0;

        final socialQuestCount = questHistory
            .where((q) =>
                q.quest?.category == QuestCategory.social &&
                q.status == UserQuestStatus.approved)
            .length;

        // POSTS counts what the posts grid actually shows: approved,
        // non-deleted submissions.
        final postCount = submissions
            .where((s) =>
                s.status == SubmissionStatus.approved &&
                s.visibility != SubmissionVisibility.deleted &&
                s.deletedAt == null)
            .length;

        final counts = ref.watch(followCountsProvider(profile.id)).valueOrNull;

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

        final badges = allBadges;
        final unlocked = badges
            .where((b) => b.isUnlocked(
                  profile: profile,
                  streak: streak,
                  socialQuestCount: socialQuestCount,
                ))
            .toList(growable: false);

        return Scaffold(
          backgroundColor: QuestColors.osBg,
          body: SafeArea(
            bottom: false,
            child: RefreshIndicator(
              color: QuestColors.osPrimary,
              backgroundColor: QuestColors.osCard,
              onRefresh: handleRefresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
                children: [
                  _Header(
                    profile: profile,
                    isViewingOther: isViewingOther,
                    onBack: () => context.canPop()
                        ? context.pop()
                        : context.goNamed(RouteNames.home),
                    onEdit: () => context.pushNamed(RouteNames.editProfile),
                    onSettings: () => context.pushNamed(RouteNames.settings),
                    onShare: () {
                      ref.read(analyticsProvider).profileShared(profile.id);
                      SharePlus.instance.share(ShareParams(
                        text:
                            'Check out @${profile.username} on BSHEEL!\n\n${DeepLinkConfig.profileLink(profile.id)}',
                      ));
                    },
                    onAvatarTap: () {
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
                    ref.watch(mapProfileCountriesProvider(profile.id)).when(
                          data: (countries) =>
                              DiscoveryProgress(countries: countries),
                          loading: () => const LinearProgressIndicator(),
                          error: (_, __) => TextButton(
                              onPressed: () =>
                                  ref.invalidate(mapProfileCountriesProvider(profile.id)),
                              child: const Text('RETRY DISCOVERY PROGRESS')),
                        ),
                  if (isViewingOther) ...[
                    const SizedBox(height: 14),
                    FollowButton(targetUserId: userId!),
                  ],
                  const SizedBox(height: 16),
                  _XpPanel(
                    level: profile.level,
                    playerClass: playerClass,
                    xp: profile.xp,
                    nextThreshold: nextThreshold,
                    progress: xpProgress,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: _StatTile(
                          value: '$postCount',
                          label: l.posts,
                          onTap: () => _showProfileSheet(
                            context,
                            title: l.posts,
                            child: _PostsSheetBody(
                              userId: profile.id,
                              submissions: submissions,
                              showSaved: !isViewingOther,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _StatTile(
                          value: counts == null ? '—' : '${counts.followers}',
                          label: l.followers,
                          onTap: () => _showProfileSheet(
                            context,
                            title: l.followers,
                            child: _FollowListTab(
                                userId: profile.id, isFollowers: true),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _StatTile(
                          value: counts == null ? '—' : '${counts.following}',
                          label: l.following,
                          onTap: () => _showProfileSheet(
                            context,
                            title: l.following,
                            child: _FollowListTab(
                                userId: profile.id, isFollowers: false),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  _SectionLabel(l.badges),
                  const SizedBox(height: 10),
                  _BadgeRow(
                    unlocked: unlocked,
                    onBadgeTap: (badge) => _showBadgeDetail(
                      context,
                      badge,
                      true,
                      badge.currentValue(
                        profile: profile,
                        streak: streak,
                        socialQuestCount: socialQuestCount,
                      ),
                    ),
                    onSeeAll: () => _showProfileSheet(
                      context,
                      title: l.badges,
                      child: _BadgeListBody(
                        badges: badges,
                        profile: profile,
                        streak: streak,
                        socialQuestCount: socialQuestCount,
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  _SectionLabel(l.activity),
                  const SizedBox(height: 10),
                  _ActivityStrip(timestamps: activityTimestamps),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ── Header ────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header({
    required this.profile,
    required this.isViewingOther,
    required this.onBack,
    required this.onEdit,
    required this.onSettings,
    required this.onShare,
    required this.onAvatarTap,
  });

  final ProfileModel profile;
  final bool isViewingOther;
  final VoidCallback onBack;
  final VoidCallback onEdit;
  final VoidCallback onSettings;
  final VoidCallback onShare;
  final VoidCallback onAvatarTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (isViewingOther) ...[
          _IconBtn(icon: Icons.arrow_back_rounded, onTap: onBack),
          const SizedBox(width: 10),
        ],
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onAvatarTap,
          child: Hero(
            tag: 'profile-avatar-${profile.id}',
            child: _SquareAvatar(
              url: profile.avatarUrl,
              fallback: profile.displayName,
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              FitText(
                profile.displayName.toUpperCase(),
                // Low floor on purpose: at 320dp the avatar plus EDIT plus
                // the gear leave the name about 60pt, and the frame sets it
                // on one line.
                minFontSize: 11,
                style: QuestTypography.osDisplayMedium.copyWith(
                  fontSize: 28,
                  letterSpacing: -0.8,
                  height: 1,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '@${profile.username}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: QuestTypography.osLabelMedium
                    .copyWith(color: QuestColors.osTextSecondary),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        if (isViewingOther)
          _IconBtn(icon: Icons.share_outlined, onTap: onShare)
        else ...[
          _TextButton(label: 'EDIT', onTap: onEdit),
          const SizedBox(width: 8),
          // Not in the frame, but the settings screen is only reachable from
          // here — dropping the gear would orphan the whole screen.
          _IconBtn(icon: Icons.settings_outlined, onTap: onSettings),
        ],
      ],
    );
  }
}

/// The frame's profile avatar: a 72pt rounded square, `r18`, 2px ink, 4px ink
/// shadow. Falls back to the violet→coral gradient with the initial; white on
/// that gradient measures 4.56:1 against ink's 3.43:1, so it stays white.
class _SquareAvatar extends StatelessWidget {
  const _SquareAvatar({required this.url, required this.fallback});

  final String? url;
  final String fallback;

  static const double _size = 72;

  @override
  Widget build(BuildContext context) {
    final initial = Center(
      child: Text(
        _avatarInitial(fallback),
        style: QuestTypography.displaySmall.copyWith(
          fontSize: 30,
          color: QuestColors.pureWhite,
          height: 1,
        ),
      ),
    );
    return Container(
      width: _size,
      height: _size,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [QuestColors.osPrimary, QuestColors.osRed],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: QuestColors.osTextPrimary, width: 2),
        boxShadow: const [
          BoxShadow(
            color: QuestColors.osTextPrimary,
            offset: Offset(4, 4),
            blurRadius: 0,
          ),
        ],
      ),
      child: (url == null || url!.isEmpty)
          ? initial
          : ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: CachedNetworkImage(
                imageUrl: url!,
                fit: BoxFit.cover,
                memCacheWidth: 200,
                placeholder: (_, __) => initial,
                errorWidget: (_, __, ___) => initial,
              ),
            ),
    );
  }
}

/// EDIT — warm surface, `r11`, 2px ink, 3px ink shadow, 44pt tall.
class _TextButton extends StatelessWidget {
  const _TextButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: QuestSpacing.minTouchTarget,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: QuestColors.osSurface,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: QuestColors.osTextPrimary, width: 2),
          boxShadow: const [
            BoxShadow(
              color: QuestColors.osTextPrimary,
              offset: Offset(3, 3),
              blurRadius: 0,
            ),
          ],
        ),
        child: Text(
          label,
          style: QuestTypography.osHeadlineLarge.copyWith(
            fontSize: 15,
            letterSpacing: 0.4,
            height: 1,
          ),
        ),
      ),
    );
  }
}

// ── XP panel ──────────────────────────────────────────────────────────────

/// Violet panel, `r16`, 4px ink shadow: LVL in display white, the class in
/// gold, the XP fraction in white mono, a gold meter, and the rank ladder
/// underneath with the current rung in gold.
class _XpPanel extends StatelessWidget {
  const _XpPanel({
    required this.level,
    required this.playerClass,
    required this.xp,
    required this.nextThreshold,
    required this.progress,
  });

  final int level;
  final String playerClass;
  final int xp;
  final int nextThreshold;
  final double progress;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: BoxDecoration(
        color: QuestColors.osPrimary,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: QuestColors.osTextPrimary, width: 2),
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
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Flexible(
                flex: 3,
                child: FitText(
                  'LVL $level',
                  minFontSize: 16,
                  style: QuestTypography.displayLarge.copyWith(
                    fontSize: 32,
                    color: QuestColors.pureWhite,
                    height: 1,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                flex: 2,
                child: Text(
                  playerClass,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: QuestTypography.labelMedium
                      .copyWith(color: QuestColors.osAccent),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                flex: 4,
                child: FitText(
                  '${_thousands(xp)} / ${_thousands(nextThreshold)}',
                  minFontSize: 9,
                  textAlign: TextAlign.right,
                  style: QuestTypography.labelMedium
                      .copyWith(color: QuestColors.pureWhite, fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ArcadeMeter(progress: progress, fill: QuestColors.osAccent),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (final rung in playerClassLadder)
                Flexible(
                  child: Text(
                    rung,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: QuestTypography.labelSmall.copyWith(
                      fontSize: 9,
                      // White on violet is the readable pair; the inactive
                      // rungs stay full-strength white rather than alpha-
                      // muted, because 9px type has no contrast to spare.
                      color: rung == playerClass
                          ? QuestColors.osAccent
                          : QuestColors.pureWhite,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// `18420` → `18,420`, which is how every score is set in the frames.
String _thousands(int value) {
  final digits = value.abs().toString();
  final buffer = StringBuffer(value < 0 ? '-' : '');
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}

// ── Stat tile ─────────────────────────────────────────────────────────────

class _StatTile extends StatelessWidget {
  const _StatTile({required this.value, required this.label, this.onTap});

  final String value;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 60,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: QuestColors.osCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: QuestColors.osTextPrimary, width: 2),
          boxShadow: const [
            BoxShadow(
              color: QuestColors.osTextPrimary,
              offset: Offset(3, 3),
              blurRadius: 0,
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            FitText(
              value,
              minFontSize: 12,
              textAlign: TextAlign.center,
              style: QuestTypography.osDisplayMedium.copyWith(
                fontSize: 26,
                height: 1,
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
                  height: 1,
                ),
              ),
            ),
          ],
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

// ── Badges ────────────────────────────────────────────────────────────────

/// Four tiles across: up to three unlocked badges as filled squares, the rest
/// dashed "?" placeholders. The trailing placeholder opens the full list.
class _BadgeRow extends StatelessWidget {
  const _BadgeRow({
    required this.unlocked,
    required this.onBadgeTap,
    required this.onSeeAll,
  });

  final List<BadgeDefinition> unlocked;
  final void Function(BadgeDefinition) onBadgeTap;
  final VoidCallback onSeeAll;

  @override
  Widget build(BuildContext context) {
    final shown = unlocked.take(3).toList(growable: false);
    return Row(
      children: [
        for (var i = 0; i < 4; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          Expanded(
            child: i < shown.length
                ? _BadgeTile(
                    icon: shown[i].icon,
                    tint: _badgeTints[i % _badgeTints.length],
                    onTap: () => onBadgeTap(shown[i]),
                  )
                : _LockedBadgeTile(onTap: onSeeAll),
          ),
        ],
      ],
    );
  }
}

class _BadgeTile extends StatelessWidget {
  const _BadgeTile({
    required this.icon,
    required this.tint,
    required this.onTap,
  });

  final IconData icon;
  final Color tint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AspectRatio(
        aspectRatio: 1,
        child: Container(
          decoration: BoxDecoration(
            color: tint,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: QuestColors.osTextPrimary, width: 2),
            boxShadow: const [
              BoxShadow(
                color: QuestColors.osTextPrimary,
                offset: Offset(4, 4),
                blurRadius: 0,
              ),
            ],
          ),
          // Ink on gold, jade and coral — never white. `onAccent` decides.
          child: Icon(icon, size: 30, color: QuestColors.onAccent(tint)),
        ),
      ),
    );
  }
}

class _LockedBadgeTile extends StatelessWidget {
  const _LockedBadgeTile({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AspectRatio(
        aspectRatio: 1,
        child: CustomPaint(
          painter: const _DashedBorderPainter(radius: 16),
          child: Container(
            decoration: BoxDecoration(
              color: QuestColors.osSurface,
              borderRadius: BorderRadius.circular(16),
            ),
            alignment: Alignment.center,
            child: Text(
              '?',
              style: QuestTypography.osHeadlineLarge.copyWith(
                fontSize: 20,
                color: QuestColors.osTextMuted,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Activity strip ────────────────────────────────────────────────────────

/// The frame's ACTIVITY block: one white card holding 28 days as two rows of
/// fourteen cells. Three states, read off the render — warm surface for a
/// blank day, light violet for one submission, full violet for two or more —
/// plus coral for today when today is active.
class _ActivityStrip extends StatelessWidget {
  const _ActivityStrip({required this.timestamps});

  final List<DateTime> timestamps;

  static const int _days = 28;

  @override
  Widget build(BuildContext context) {
    final counts = <DateTime, int>{};
    for (final t in timestamps) {
      final day = toLocalDateOnly(t);
      counts[day] = (counts[day] ?? 0) + 1;
    }
    final today = toLocalDateOnly(DateTime.now());

    Color tint(int offsetFromOldest) {
      final day = today.subtract(Duration(days: _days - 1 - offsetFromOldest));
      final count = counts[day] ?? 0;
      if (count == 0) return QuestColors.osSurface;
      if (day == today) return QuestColors.osRed;
      if (count == 1) return QuestColors.textSecondary;
      return QuestColors.osPrimary;
    }

    Widget row(int start) {
      return Row(
        children: [
          for (var i = 0; i < 14; i++) ...[
            if (i > 0) const SizedBox(width: 4),
            Expanded(
              child: AspectRatio(
                aspectRatio: 1,
                child: Container(
                  decoration: BoxDecoration(
                    color: tint(start + i),
                    borderRadius: BorderRadius.circular(5),
                  ),
                ),
              ),
            ),
          ],
        ],
      );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: QuestColors.osCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: QuestColors.osTextPrimary, width: 2),
        boxShadow: const [
          BoxShadow(
            color: QuestColors.osTextPrimary,
            offset: Offset(3, 3),
            blurRadius: 0,
          ),
        ],
      ),
      child: Column(
        children: [row(0), const SizedBox(height: 6), row(14)],
      ),
    );
  }
}

// ── Sheets ────────────────────────────────────────────────────────────────

/// The tab bodies this page used to carry, presented as a cream sheet with an
/// ink outline and an `r18` top — the frame's panel treatment.
void _showProfileSheet(
  BuildContext context, {
  required String title,
  required Widget child,
}) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (ctx) => FractionallySizedBox(
      heightFactor: 0.85,
      child: Container(
        decoration: const BoxDecoration(
          color: QuestColors.osBg,
          borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
          border: Border(
            top: BorderSide(color: QuestColors.osTextPrimary, width: 2),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: QuestTypography.osDisplaySmall.copyWith(
                        fontSize: 22,
                        height: 1,
                      ),
                    ),
                  ),
                  _IconBtn(
                    icon: Icons.close_rounded,
                    onTap: () => Navigator.of(ctx).pop(),
                  ),
                ],
              ),
            ),
            Expanded(child: child),
          ],
        ),
      ),
    ),
  );
}

/// POSTS sheet. Saved posts ride here as a second chip because the profile is
/// their only entry point and the frame gives them no tile of their own.
class _PostsSheetBody extends StatefulWidget {
  const _PostsSheetBody({
    required this.userId,
    required this.submissions,
    required this.showSaved,
  });

  final String userId;
  final List<SubmissionModel> submissions;
  final bool showSaved;

  @override
  State<_PostsSheetBody> createState() => _PostsSheetBodyState();
}

class _PostsSheetBodyState extends State<_PostsSheetBody> {
  bool _saved = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.showSaved)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _OptionChip(
                  label: 'POSTS',
                  selected: !_saved,
                  onTap: () => setState(() => _saved = false),
                ),
                _OptionChip(
                  label: 'BSHEEEL',
                  selected: _saved,
                  onTap: () => setState(() => _saved = true),
                ),
              ],
            ),
          ),
        Expanded(
          child: _saved
              ? _SavedPostsTab(userId: widget.userId)
              : ListView(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
                  children: [_UserPostsGrid(submissions: widget.submissions)],
                ),
        ),
      ],
    );
  }
}

class _BadgeListBody extends StatelessWidget {
  const _BadgeListBody({
    required this.badges,
    required this.profile,
    required this.streak,
    required this.socialQuestCount,
  });

  final List<BadgeDefinition> badges;
  final ProfileModel profile;
  final int streak;
  final int socialQuestCount;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
      itemCount: badges.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final badge = badges[i];
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
        final progress = (current / badge.targetValue).clamp(0.0, 1.0);
        final tint = _badgeTints[i % _badgeTints.length];
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _showBadgeDetail(context, badge, unlocked, current),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: QuestColors.osCard,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: QuestColors.osTextPrimary, width: 2),
              boxShadow: const [
                BoxShadow(
                  color: QuestColors.osTextPrimary,
                  offset: Offset(3, 3),
                  blurRadius: 0,
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: unlocked ? tint : QuestColors.osSurface,
                    borderRadius: BorderRadius.circular(11),
                    border:
                        Border.all(color: QuestColors.osTextPrimary, width: 2),
                  ),
                  child: Icon(
                    badge.icon,
                    size: 22,
                    color: unlocked
                        ? QuestColors.onAccent(tint)
                        : QuestColors.osTextMuted,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        badge.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: QuestTypography.osHeadlineSmall.copyWith(
                          color: unlocked
                              ? QuestColors.osTextPrimary
                              : QuestColors.osTextSecondary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        badge.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: QuestTypography.osBodySmall
                            .copyWith(color: QuestColors.osTextMuted),
                      ),
                      const SizedBox(height: 6),
                      ArcadeMeter(
                        progress: progress,
                        height: 8,
                        fill: unlocked ? QuestColors.osSuccess : tint,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        unlocked
                            ? l.completed
                            : '$current / ${badge.targetValue}',
                        style: QuestTypography.osLabelSmall.copyWith(
                          color: unlocked
                              ? QuestColors.osSuccessText
                              : QuestColors.osTextMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Selected = ink ground with cream type; the rest are white with a 2px ink
/// outline. Same chip as the leaderboard scope and the settings language pair.
class _OptionChip extends StatelessWidget {
  const _OptionChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        // No `alignment:` here: inside a Wrap the constraints are bounded and
        // an Align with no widthFactor would stretch the chip to the run.
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? QuestColors.osTextPrimary : QuestColors.osCard,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: QuestColors.osTextPrimary, width: 2),
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: QuestTypography.osLabelMedium.copyWith(
              color: selected ? QuestColors.osBg : QuestColors.osTextPrimary,
              fontSize: 12,
              letterSpacing: 1,
              height: 1,
            ),
          ),
        ),
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter({required this.radius});

  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = QuestColors.osTextMuted
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(1, 1, size.width - 2, size.height - 2),
      Radius.circular(radius),
    );
    for (final metric in (Path()..addRRect(rect)).computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = (distance + 6).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance = end + 5;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter oldDelegate) =>
      oldDelegate.radius != radius;
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
                      color: QuestColors.osTextPrimary, offset: Offset(5, 5))
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
                              offset: Offset(3, 3)),
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

/// The spec's recurring icon button: 44pt, `r11`, white ground, 2px ink,
/// 3px ink shadow, 15-18px glyph.
class _IconBtn extends StatelessWidget {
  const _IconBtn({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
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
          borderRadius: BorderRadius.circular(11),
          boxShadow: const [
            BoxShadow(
              color: QuestColors.osTextPrimary,
              offset: Offset(3, 3),
              blurRadius: 0,
            )
          ],
        ),
        child: Icon(icon, size: 18, color: QuestColors.osTextPrimary),
      ),
    );
  }
}

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
          child: ArcadeCard(
              borderRadius: 12,
              shadowOffset: 3,
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
                  color: QuestColors.osRedText))),
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
        child: ArcadeCard(
          borderRadius: 12,
          shadowOffset: 3,
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
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minWidth: QuestSpacing.minTouchTarget,
                  minHeight: QuestSpacing.minTouchTarget,
                ),
                child: Container(
                  width: 44,
                  height: 44,
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
                BoxShadow(color: ink, offset: Offset(4, 4)),
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
                          constraints: const BoxConstraints(
                              minHeight: QuestSpacing.minTouchTarget),
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
                          constraints: const BoxConstraints(
                              minHeight: QuestSpacing.minTouchTarget),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: QuestColors.osRed,
                            borderRadius: BorderRadius.circular(11),
                            border: Border.all(color: ink, width: 2),
                            boxShadow: const [
                              BoxShadow(color: ink, offset: Offset(3, 3)),
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
} // ── Avatar fullscreen viewer ────────────────────────────────────────────────

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
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minWidth: QuestSpacing.minTouchTarget,
                    minHeight: QuestSpacing.minTouchTarget,
                  ),
                  child: Container(
                    width: 44,
                    height: 44,
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
