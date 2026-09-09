import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:app_core/app_core.dart';
import 'package:app_models/app_models.dart';
import 'package:app_contracts/app_contracts.dart' show UserQuestStatus;

import '../../../../design/bs_widgets.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../core/providers/account_status_provider.dart';
import '../../../../core/providers/auth_session_provider.dart';
import '../../../../core/providers/current_profile_provider.dart';
import '../../../../core/backend/app_backend.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/utils/streak_utils.dart';
import '../../../notifications/presentation/providers/notifications_provider.dart';
import '../../../submissions/data/submission_providers.dart';
import '../../data/quest_providers.dart';
import '../widgets/home_arcade_widgets.dart';
import '../widgets/home_extras.dart';

/// ──────────────────────────────────────────────────────────────────────────
/// HOME — Arcade Pop rebuild (Direction A)
///
/// Business logic (providers, realtime, roll limit, inject slot, appeals,
/// account status, saved quests) is identical to the previous version.
/// Only the rendering layer is replaced with chunky ink-bordered,
/// hard-shadow, bright-on-cream Arcade Pop widgets.
/// ──────────────────────────────────────────────────────────────────────────
class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage>
    with TickerProviderStateMixin {
  // Realtime for user_quests + submissions lives in `BottomNavShell` —
  // having a duplicate subscription here meant every DB event triggered
  // two parallel refetch waves. The shell sub invalidates the same
  // providers HomePage cares about (activeQuest, questHistory,
  // userSubmissions) and stays alive across tab switches, which is
  // strictly better.
  StreamSubscription<List<Map<String, dynamic>>>? _questStream;

  // Animations
  late final AnimationController _slotBounce;

  @override
  void initState() {
    super.initState();
    _slotBounce = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..forward();
  }

  @override
  void dispose() {
    _questStream?.cancel();
    _slotBounce.dispose();
    super.dispose();
  }

  bool _rolling = false;

  Future<void> _rollWheel() async {
    if (_rolling) return;
    _rolling = true;
    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        barrierColor: QuestColors.pureBlack.withAlpha(180),
        builder: (_) => const _RollPickerSheet(),
      );
    } finally {
      _rolling = false;
    }
  }

  Future<void> _acceptQuestOfTheDay(QuestOfTheDayModel qotd) async {
    // Reject early if the player already has a live quest — assigning a
    // second one would either silently fail (the unique partial index) or
    // overwrite their current attempt depending on timing. Also catches
    // the case where they have a submitted-but-not-yet-reviewed quest;
    // the RPC's unique partial index would reject it server-side anyway,
    // but blocking client-side gives a friendlier message.
    final existing = ref.read(activeQuestProvider).valueOrNull;
    if (existing != null &&
        (existing.status == UserQuestStatus.assigned ||
            existing.status == UserQuestStatus.submitted)) {
      final msg = existing.status == UserQuestStatus.submitted
          ? "You have a quest waiting for review. Wait for it to be reviewed before starting another."
          : "You already have an active quest. Finish or cancel it first.";
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      return;
    }

    final session = ref.read(authSessionProvider);
    if (session == null) return;

    try {
      await ref
          .read(questsRepositoryProvider)
          .assignSpecificQuest(session.id, qotd.questId);
      ref.invalidate(activeQuestProvider);
      ref.invalidate(questHistoryProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('🎫 Ticket accepted — "${qotd.questTitle}" is live.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not accept ticket: $e')),
      );
    }
  }

  Future<void> _showPendingList(List<UserQuestModel> pending) async {
    if (pending.length == 1) {
      context.pushNamed(
        RouteNames.questDetails,
        pathParameters: {'id': pending.first.questId},
      );
      return;
    }
    await showDialog<void>(
      context: context,
      barrierColor: QuestColors.pureBlack.withAlpha(160),
      builder: (_) => _PendingListDialog(pending: pending),
    );
  }

  @override
  Widget build(BuildContext context) {
    final activeQuestAsync = ref.watch(activeQuestProvider);
    final profileAsync = ref.watch(currentProfileProvider);
    final profile = profileAsync.valueOrNull;
    final profileLoading = profileAsync is AsyncLoading && profile == null;
    final questHistoryAsync = ref.watch(questHistoryProvider);
    final questHistory =
        questHistoryAsync.valueOrNull ?? const <UserQuestModel>[];
    final questHistoryLoading = questHistoryAsync is AsyncLoading &&
        questHistoryAsync.valueOrNull == null;
    final submissions = ref.watch(userSubmissionsProvider).valueOrNull ??
        const <SubmissionModel>[];
    final unreadCount = ref.watch(unreadCountProvider).valueOrNull ?? 0;
    final accountStatus = ref.watch(accountStatusProvider).valueOrNull;

    final displayName = profile?.displayName ?? profile?.username ?? 'Agent';

    final todayDate = toLocalDateOnly(DateTime.now());
    final approvedQuests = questHistory
        .where((q) => q.status == UserQuestStatus.approved)
        .toList();

    // All-time totals for the home stat tiles.
    // Both reads come from `profiles.*` so the home tile and the
    // profile page stay in lockstep after a self-delete (which
    // decrements `profiles.quests_completed` via the 0110 trigger).
    // ARC-025: previously this was approvedQuests.length which kept
    // counting deleted posts because the user_quest row stays
    // 'approved' even after the submission's visibility flips.
    final questsTotal = profile?.questsCompleted ?? approvedQuests.length;
    final xpTotal = profile?.xp ?? 0;

    // 28-day activity heatmap (oldest → newest)
    final activeDays = List<bool>.generate(28, (i) {
      final day = todayDate.subtract(Duration(days: 27 - i));
      return submissions.any((s) => toLocalDateOnly(s.submittedAt) == day) ||
          approvedQuests.any((q) =>
              q.completedAt != null && toLocalDateOnly(q.completedAt!) == day);
    });

    // Longest streak from history
    int longestStreak = 0;
    int run = 0;
    for (final active in activeDays) {
      run = active ? run + 1 : 0;
      if (run > longestStreak) longestStreak = run;
    }

    final activityTimestamps = submissions.isNotEmpty
        ? submissions.map((s) => s.submittedAt)
        : questHistory
            .where((q) =>
                q.status == UserQuestStatus.submitted ||
                q.status == UserQuestStatus.approved ||
                q.status == UserQuestStatus.rejected)
            .map((q) => q.completedAt ?? q.assignedAt);
    final streak = calculateCurrentStreakFromTimestamps(activityTimestamps);

    final bool locked =
        accountStatus == 'suspended' || accountStatus == 'banned';

    return Scaffold(
      backgroundColor: QuestColors.bg(context),
      body: Stack(
        children: [
          // Pixel grid background (faint, fades down)
          const Positioned.fill(child: ArcadePixelGrid()),

          // Main scrollable
          Positioned.fill(
            child: SafeArea(
              child: RefreshIndicator(
                color: QuestColors.osRed,
                backgroundColor: QuestColors.cardBg(context),
                onRefresh: () async {
                  ref.invalidate(activeQuestProvider);
                  ref.invalidate(currentProfileProvider);
                  ref.invalidate(userSubmissionsProvider);
                  ref.invalidate(unreadCountProvider);
                  ref.invalidate(questHistoryProvider);
                  await Future.delayed(const Duration(milliseconds: 400));
                },
                child: CustomScrollView(
                  physics: const BouncingScrollPhysics(),
                  slivers: [
                    // ── Top row: user name + notification bell ──
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(
                            QuestSpacing.screenPadding,
                            14,
                            QuestSpacing.screenPadding,
                            0),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                displayName.toUpperCase(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: QuestTypography.displayLarge.copyWith(
                                  // Same navy ink as the bottom nav pill.
                                  color: QuestColors.osTextPrimary,
                                  fontSize: 28,
                                  fontWeight: FontWeight.w800,
                                  height: 1,
                                  letterSpacing: -0.3,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            ArcadeNotificationBell(
                              unreadCount: unreadCount,
                              onTap: () =>
                                  context.pushNamed(RouteNames.notifications),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // ── Hero headline ──
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(
                            QuestSpacing.screenPadding,
                            0,
                            QuestSpacing.screenPadding,
                            4),
                        child: _Headline(name: displayName),
                      ),
                    ),

                    // ── All-time stat tiles: total Quests Done + total XP Earned ──
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(
                            QuestSpacing.screenPadding,
                            14,
                            QuestSpacing.screenPadding,
                            10),
                        child: Row(
                          children: [
                            Expanded(
                              child: profileLoading
                                  ? const _StatTileSkeleton()
                                  : ArcadeStatTile(
                                      label: AppLocalizations.of(context)!
                                          .questsDone,
                                      value: '$questsTotal',
                                      sublabel:
                                          AppLocalizations.of(context)!.allTime,
                                      tint: QuestColors.accentYellow,
                                      icon: Icons.flag_rounded,
                                    ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: profileLoading
                                  ? const _StatTileSkeleton()
                                  : ArcadeStatTile(
                                      label: AppLocalizations.of(context)!
                                          .xpEarnedLabel,
                                      value: _fmtXp(xpTotal),
                                      sublabel: 'ALL TIME',
                                      tint: QuestColors.osPrimary,
                                      icon: Icons.bolt_rounded,
                                    ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // ── Quest of the Day ticket (above the generator) ──
                    // Renders nothing when no QOTD is queued for today; users
                    // can't tell the widget exists when it's empty. Hidden
                    // entirely for suspended/banned accounts so the accept
                    // CTA can't fire an RPC that the backend will reject.
                    if (!locked)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(
                              QuestSpacing.screenPadding,
                              0,
                              QuestSpacing.screenPadding,
                              16),
                          child: BsQuestOfDayTicket(
                            onAccept: (qotd) => _acceptQuestOfTheDay(qotd),
                          ),
                        ),
                      ),

                    // ── Hero zone: slot machine OR active quest ──
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(
                            QuestSpacing.screenPadding,
                            0,
                            QuestSpacing.screenPadding,
                            16),
                        child: activeQuestAsync.when(
                          loading: () => _HeroSkeleton(),
                          error: (_, __) => _HeroSkeleton(),
                          data: (activeQuest) {
                            if (locked) {
                              return _LockedCard(
                                title: accountStatus == 'banned'
                                    ? 'ACCOUNT BANNED'
                                    : 'ACCOUNT SUSPENDED',
                                subtitle:
                                    'New quests are paused. Reach out to support.',
                              );
                            }
                            // Every user_quest currently awaiting admin review,
                            // newest first. This stays visible regardless of
                            // whatever quest is "active" right now.
                            final pendingList = [
                              ...questHistory.where(
                                (q) => q.status == UserQuestStatus.submitted,
                              ),
                            ]..sort((a, b) => (b.completedAt ?? b.assignedAt)
                                .compareTo(a.completedAt ?? a.assignedAt));

                            final hasLiveQuest = activeQuest != null &&
                                activeQuest.status == UserQuestStatus.assigned;

                            return Column(
                              children: [
                                if (pendingList.isNotEmpty) ...[
                                  _PendingReviewCard(
                                    pending: pendingList,
                                    onOpen: () => _showPendingList(pendingList),
                                  ),
                                  const SizedBox(height: 14),
                                ],
                                if (hasLiveQuest)
                                  _ActiveQuestHero(
                                    activeQuest: activeQuest,
                                    onSubmit: () => context.pushNamed(
                                      RouteNames.submitProof,
                                      pathParameters: {
                                        'userQuestId': activeQuest.id
                                      },
                                    ),
                                    onOpen: () => context.pushNamed(
                                      RouteNames.questDetails,
                                      pathParameters: {
                                        'id': activeQuest.questId
                                      },
                                    ),
                                  )
                                else
                                  _SlotMachineZone(
                                    slotBounce: _slotBounce,
                                    onGenerate: _rollWheel,
                                  ),
                              ],
                            );
                          },
                        ),
                      ),
                    ),

                    // ── Recent quest history (5 latest) ──
                    if (questHistoryLoading)
                      const SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(
                              QuestSpacing.screenPadding,
                              0,
                              QuestSpacing.screenPadding,
                              16),
                          child: _RecentQuestsSkeleton(),
                        ),
                      )
                    else if (questHistory.isNotEmpty)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(
                              QuestSpacing.screenPadding,
                              0,
                              QuestSpacing.screenPadding,
                              16),
                          child: _RecentQuestsCard(
                            quests: questHistory,
                            onSeeMore: () =>
                                context.pushNamed(RouteNames.questHistory),
                          ),
                        ),
                      ),

                    // ── Weekly XP race — visible motivation toward a goal ──
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(
                            QuestSpacing.screenPadding,
                            0,
                            QuestSpacing.screenPadding,
                            12),
                        child: BsWeeklyXpMeter(questHistory: questHistory),
                      ),
                    ),

                    // ── Friend / community activity carousel ──
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(QuestSpacing.screenPadding,
                            4, QuestSpacing.screenPadding, 16),
                        child: BsFriendActivityStrip(),
                      ),
                    ),

                    // ── Streak card (this week only) — below the wheel ──
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(
                            QuestSpacing.screenPadding,
                            0,
                            QuestSpacing.screenPadding,
                            16),
                        child: ArcadeStreakCard(
                          currentStreak: streak,
                          longestStreak: longestStreak,
                          activeDays: activeDays,
                        ),
                      ),
                    ),

                    // Bottom spacer so the last card doesn't sit on the nav bar.
                    const SliverToBoxAdapter(child: SizedBox(height: 120)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────

String _fmtXp(int xp) {
  if (xp >= 1000) {
    return '${(xp / 1000).toStringAsFixed(xp % 1000 == 0 ? 0 : 1)}k';
  }
  return '$xp';
}

// ── Headline ──────────────────────────────────────────────────────────────

class _Headline extends StatelessWidget {
  const _Headline({required this.name});
  final String name;

  @override
  Widget build(BuildContext context) {
    final ink = QuestColors.text(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          AppLocalizations.of(context)!.homeHeadline,
          style: QuestTypography.displayLarge.copyWith(
            color: ink,
            fontSize: 32,
            fontWeight: FontWeight.w800,
            height: 1.05,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Container(
              width: 44,
              height: 6,
              decoration: BoxDecoration(
                color: QuestColors.osRed,
                borderRadius: BorderRadius.circular(2),
                border: Border.all(color: ink, width: 1.4),
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                AppLocalizations.of(context)!.homeHeadlineTagline,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: QuestTypography.labelSmall.copyWith(
                  color: ink.withAlpha(170),
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.1,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ── Pending review card ──────────────────────────────────────────────────
//
// Shown above the Quest Machine whenever a previously submitted quest is
// still awaiting admin review (status == submitted). Tapping opens the
// quest detail so the user can check their submission.

class _PendingReviewCard extends StatelessWidget {
  const _PendingReviewCard({required this.pending, required this.onOpen});

  final List<UserQuestModel> pending;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final ink = QuestColors.text(context);
    final count = pending.length;
    final multiple = count > 1;
    final subtitle = multiple
        ? '$count submissions awaiting review'
        : (pending.isNotEmpty
            ? (pending.first.quest?.title ?? 'Your submission')
            : 'Your submission');

    return GestureDetector(
      onTap: onOpen,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: QuestColors.accentYellow,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: ink, width: 2),
          boxShadow: [
            BoxShadow(color: ink, offset: const Offset(4, 4), blurRadius: 0),
          ],
        ),
        child: Row(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: QuestColors.osCard,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: ink, width: 2),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.hourglass_top_rounded,
                    color: QuestColors.accentYellowInk,
                    size: 22,
                  ),
                ),
                if (multiple)
                  Positioned(
                    right: -6,
                    top: -6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: QuestColors.osRed,
                        borderRadius: BorderRadius.circular(11),
                        border: Border.all(color: ink, width: 1.5),
                      ),
                      child: Text(
                        '$count',
                        style: QuestTypography.labelSmall.copyWith(
                          color: QuestColors.onAccent(QuestColors.osRed),
                          fontSize: 10,
                          height: 1,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    multiple
                        ? AppLocalizations.of(context)!.inReviewTapToSeeAll
                        : 'IN REVIEW',
                    style: QuestTypography.labelSmall.copyWith(
                      color: QuestColors.accentYellowInk,
                      fontSize: 10,
                      letterSpacing: 1.4,
                      height: 1,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: QuestTypography.headlineSmall.copyWith(
                      color: QuestColors.accentYellowInk,
                      fontSize: 14,
                      height: 1.2,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                color: QuestColors.accentYellowInk, size: 22),
          ],
        ),
      ),
    );
  }
}

// ── Slot machine zone ─────────────────────────────────────────────────────

class _SlotMachineZone extends StatelessWidget {
  const _SlotMachineZone({
    required this.slotBounce,
    required this.onGenerate,
  });
  final AnimationController slotBounce;
  final VoidCallback onGenerate;

  @override
  Widget build(BuildContext context) {
    final ink = QuestColors.text(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 18),
      decoration: BoxDecoration(
        // The design draws this as a white card, not an ink panel: it is the
        // one thing to do on an empty home, so it should read as the bright
        // surface rather than recede.
        color: QuestColors.osCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: ink, width: 2),
        boxShadow: const [
          // A *coloured* shadow marks the single most important thing on
          // screen; everything else takes ink. With no active quest, that is
          // this card. 6px, coral, per the frame.
          BoxShadow(
            color: QuestColors.osRed,
            offset: Offset(6, 6),
            blurRadius: 0,
          ),
        ],
      ),
      child: Column(
        children: [
          // Retro arcade chase scene — Pac-Man eating dots with a ghost
          // chasing from behind. Runs continuously until you tap generate.
          const _RetroArcadeScene(),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: onGenerate,
            child: Container(
              width: double.infinity,
              height: 48,
              decoration: BoxDecoration(
                color: QuestColors.accentYellow,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: ink, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: ink,
                    offset: const Offset(3, 3),
                    blurRadius: 0,
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.casino_rounded, color: ink, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    AppLocalizations.of(context)!.generateAQuest,
                    style: QuestTypography.buttonText.copyWith(
                      color: ink,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Three chunky reels that continuously spin. Each reel vertically scrolls
/// a strip of glyphs at a slightly different speed / direction so they feel
/// independent, like a real slot machine before you pull the lever.
/// Retro arcade chase scene — a Pac-Man sprite walks left→right chomping a
/// row of dots, with a ghost tailing behind. Draws everything with
/// [CustomPainter] so it stays crisp at any size and has no asset deps.
/// The slot-machine reels: three warm-surface tiles, per the design frame.
///
/// This replaced a hand-painted Pac-Man scene on a black strip. The frame
/// draws plain 78pt reels — `#FFF1D6` ground, 2px ink border, 12px radius,
/// a 26px glyph — and the black strip cannot survive inside the white card
/// the frame specifies anyway: its pale dot palette was chosen for black.
class _RetroArcadeScene extends StatefulWidget {
  const _RetroArcadeScene();

  @override
  State<_RetroArcadeScene> createState() => _RetroArcadeSceneState();
}

class _RetroArcadeSceneState extends State<_RetroArcadeScene>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    duration: const Duration(milliseconds: 1400),
    vsync: this,
  )..repeat();

  /// The reels idle rather than sit dead: each cycles its glyph on its own
  /// phase, so the zone reads as a machine waiting to be pulled.
  static const List<String> _glyphs = ['◇', '◈', '◆'];

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ink = QuestColors.text(context);
    return AnimatedBuilder(
      animation: _spin,
      builder: (context, _) {
        return Row(
          children: [
            for (var reel = 0; reel < 3; reel++) ...[
              if (reel > 0) const SizedBox(width: 9),
              Expanded(
                child: Container(
                  height: 78,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: QuestColors.osSurface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: ink, width: 2),
                  ),
                  child: Text(
                    // Offset phase per reel so they never land together.
                    _glyphs[((_spin.value * _glyphs.length).floor() + reel) %
                        _glyphs.length],
                    style: TextStyle(fontSize: 26, color: ink, height: 1),
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

// ── Active quest hero ─────────────────────────────────────────────────────

class _ActiveQuestHero extends ConsumerStatefulWidget {
  const _ActiveQuestHero({
    required this.activeQuest,
    required this.onSubmit,
    required this.onOpen,
  });

  final UserQuestModel activeQuest;

  /// Tap on "SUBMIT PROOF" row (if shown).
  final VoidCallback onSubmit;

  /// Tap on "SHOW DETAILS" — opens the Mission Log (quest detail page).
  final VoidCallback onOpen;

  @override
  ConsumerState<_ActiveQuestHero> createState() => _ActiveQuestHeroState();
}

class _ActiveQuestHeroState extends ConsumerState<_ActiveQuestHero>
    with SingleTickerProviderStateMixin {
  // Blink controller for the status dot.
  late final AnimationController _blink = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  late Timer _tick;
  Duration _left = Duration.zero;
  bool _canceling = false;

  @override
  void initState() {
    super.initState();
    _updateLeft();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => _updateLeft());
  }

  void _updateLeft() {
    final exp = widget.activeQuest.expiresAt;
    if (exp == null) return;
    final d = exp.difference(DateTime.now());
    if (mounted) setState(() => _left = d.isNegative ? Duration.zero : d);
  }

  @override
  void dispose() {
    _blink.dispose();
    _tick.cancel();
    super.dispose();
  }

  String _two(int n) => n.toString().padLeft(2, '0');
  String get _countdown =>
      '${_two(_left.inHours)}:${_two(_left.inMinutes.remainder(60))}:${_two(_left.inSeconds.remainder(60))}';

  Future<void> _rollAgain() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: QuestColors.pureBlack.withAlpha(180),
      builder: (_) => const _RollPickerSheet(),
    );
  }

  Future<void> _confirmCancelQuest() async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: QuestColors.pureBlack.withAlpha(170),
      builder: (dialogContext) {
        final ink = QuestColors.text(dialogContext);
        return AlertDialog(
          backgroundColor: QuestColors.cardBg(dialogContext),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: ink, width: 2),
          ),
          title: Text(
            'CANCEL QUEST?',
            style: QuestTypography.headlineSmall.copyWith(
              color: QuestColors.osRedText,
              letterSpacing: 1,
            ),
          ),
          content: Text(
            'This will remove your active quest. You can generate a new one after canceling.',
            style: QuestTypography.bodyMedium.copyWith(
              color: QuestColors.text(dialogContext),
              height: 1.35,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(
                'KEEP IT',
                style: QuestTypography.labelMedium.copyWith(
                  color: QuestColors.textDim(dialogContext),
                  letterSpacing: 1,
                ),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(
                'CANCEL',
                style: QuestTypography.labelMedium.copyWith(
                  color: QuestColors.osRedText,
                  letterSpacing: 1,
                ),
              ),
            ),
          ],
        );
      },
    );
    if (confirmed != true || _canceling) return;

    setState(() => _canceling = true);
    try {
      await ref
          .read(questsRepositoryProvider)
          .markQuestExpired(widget.activeQuest.id);
      ref.invalidate(activeQuestProvider);
      ref.invalidate(questHistoryProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Quest canceled')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _canceling = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not cancel quest: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final quest = widget.activeQuest.quest;
    final expiresAt = widget.activeQuest.expiresAt;
    final isExpired = expiresAt != null &&
        !expiresAt.isAfter(DateTime.now()) &&
        widget.activeQuest.status != UserQuestStatus.submitted;

    if (isExpired) {
      return _TimeOverCard(
        title: quest?.title ?? 'Quest',
        onGenerate: _rollAgain,
      );
    }

    // Navy ink — same colour as the bottom nav pill.
    const navy = QuestColors.osTextPrimary;
    final ink = QuestColors.text(context);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: navy,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: ink, width: 2),
        boxShadow: const [
          // The hero stays an ink panel, but its shadow is violet rather
          // than ink: a coloured shadow marks the single most important
          // thing on screen, and while a quest is running that is this.
          // 6px is the spec's depth for hero panels.
          BoxShadow(
            color: QuestColors.osPrimary,
            offset: Offset(6, 6),
            blurRadius: 0,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ACTIVE indicator row — centered
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedBuilder(
                animation: _blink,
                builder: (_, __) => Opacity(
                  opacity: 0.35 + 0.65 * _blink.value,
                  child: Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      color: QuestColors.osRed,
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: QuestColors.textPrimary, width: 1.2),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'ACTIVE',
                style: QuestTypography.labelSmall.copyWith(
                  color: QuestColors.textPrimary,
                  fontSize: 10,
                  letterSpacing: 1.4,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Full-width bare countdown — centered
          Text(
            _countdown,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'JetBrainsMono',
              fontSize: 36,
              fontWeight: FontWeight.w800,
              letterSpacing: 2,
              height: 1,
              color: _left.inMinutes < 30
                  ? QuestColors.osRed
                  : QuestColors.textPrimary,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            quest?.title ?? 'Quest',
            textAlign: TextAlign.center,
            style: QuestTypography.headlineLarge.copyWith(
              color: QuestColors.textPrimary,
              fontSize: 20,
              height: 1.2,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if ((quest?.description ?? '').isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              quest!.description,
              textAlign: TextAlign.center,
              style: QuestTypography.bodyMedium.copyWith(
                color: QuestColors.textPrimary.withAlpha(200),
                fontSize: 13,
                height: 1.35,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: 16),
          // Stacked actions — each on its own row, no icons, tighter text.
          _HeroAction(
            label: 'SHOW DETAILS',
            fill: QuestColors.pureWhite.withAlpha(28),
            fg: QuestColors.textPrimary,
            borderColor: QuestColors.textPrimary,
            onTap: widget.onOpen,
          ),
          const SizedBox(height: 10),
          _HeroAction(
            label: 'SUBMIT PROOF',
            fill: QuestColors.accentYellow,
            fg: QuestColors.accentYellowInk,
            borderColor: QuestColors.textPrimary,
            onTap: widget.onSubmit,
          ),
          const SizedBox(height: 10),
          _HeroAction(
            label: _canceling ? 'CANCELING...' : 'CANCEL QUEST',
            fill: QuestColors.pureWhite.withAlpha(12),
            fg: QuestColors.textPrimary.withAlpha(220),
            borderColor: QuestColors.textPrimary.withAlpha(150),
            onTap: _canceling ? () {} : _confirmCancelQuest,
          ),
        ],
      ),
    );
  }
}

class _HeroAction extends StatelessWidget {
  const _HeroAction({
    required this.label,
    required this.fill,
    required this.fg,
    required this.borderColor,
    required this.onTap,
  });
  final String label;
  final Color fill;
  final Color fg;
  final Color borderColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: double.infinity,
        height: kMinTouchTarget,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: borderColor, width: 1.5),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
          style: QuestTypography.buttonText.copyWith(
            color: fg,
            fontSize: 11.5,
            letterSpacing: 1.3,
          ),
        ),
      ),
    );
  }
}

/// Shown when the quest expired without a submission. Coral-red card with
/// big TIME OVER label and a single "GENERATE NEW QUEST" button.
class _TimeOverCard extends StatelessWidget {
  const _TimeOverCard({required this.title, required this.onGenerate});
  final String title;
  final VoidCallback onGenerate;

  @override
  Widget build(BuildContext context) {
    final ink = QuestColors.text(context);
    final onCoral = QuestColors.onAccent(QuestColors.osRed);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: QuestColors.osRed,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: ink, width: 2),
        boxShadow: [
          BoxShadow(color: ink, offset: const Offset(4, 4), blurRadius: 0),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.timer_off_rounded, color: onCoral, size: 18),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  'TIME OVER',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: QuestTypography.labelSmall.copyWith(
                    color: onCoral,
                    fontSize: 11,
                    letterSpacing: 1.8,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: QuestTypography.headlineLarge.copyWith(
              color: onCoral,
              fontSize: 20,
              height: 1.2,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 6),
          Text(
            "You didn't submit before the timer ended. Roll a new quest to keep going.",
            style: QuestTypography.bodyMedium.copyWith(
              color: QuestColors.onAccentSoft(QuestColors.osRed),
              fontSize: 12.5,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: onGenerate,
            behavior: HitTestBehavior.opaque,
            child: Container(
              width: double.infinity,
              height: 52,
              decoration: BoxDecoration(
                color: QuestColors.accentYellow,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: ink, width: 2),
                boxShadow: [
                  BoxShadow(
                      color: ink, offset: const Offset(3, 3), blurRadius: 0),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.casino_rounded,
                      color: QuestColors.accentYellowInk, size: 18),
                  const SizedBox(width: 10),
                  Text(
                    'GENERATE NEW QUEST',
                    style: QuestTypography.buttonText.copyWith(
                      color: QuestColors.accentYellowInk,
                      fontSize: 13.5,
                      letterSpacing: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Hero skeleton ─────────────────────────────────────────────────────────

/// Pulsing skeleton placeholder shown while the active-quest state is
/// resolving. Replaces the previous `CircularProgressIndicator` so the
/// hero zone feels lazy-loaded instead of "blocked on network."
class _HeroSkeleton extends StatefulWidget {
  @override
  State<_HeroSkeleton> createState() => _HeroSkeletonState();
}

class _HeroSkeletonState extends State<_HeroSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ac = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _ac.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ink = QuestColors.text(context);
    return AnimatedBuilder(
      animation: _ac,
      builder: (_, __) {
        final pulse = 0.35 + 0.35 * _ac.value; // 0.35..0.70
        Color bar(double scale) => ink.withAlpha(
            ((QuestColors.alphaHairline + 18) * scale).round().clamp(20, 255));
        return Container(
          height: 180,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: QuestColors.cardBg(context),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: ink.withAlpha(60), width: 2),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: bar(pulse),
                    borderRadius: BorderRadius.circular(11),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        height: 14,
                        width: 160,
                        decoration: BoxDecoration(
                          color: bar(pulse),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        height: 10,
                        width: 100,
                        decoration: BoxDecoration(
                          color: bar(pulse * 0.8),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ],
                  ),
                ),
              ]),
              Container(
                height: 38,
                decoration: BoxDecoration(
                  color: bar(pulse),
                  borderRadius: BorderRadius.circular(11),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Reusable bar-shaped skeleton (pulsing) for inline placeholders.
class _SkeletonBar extends StatefulWidget {
  const _SkeletonBar({this.height = 12, this.width, this.radius = 4});
  final double height;
  final double? width;
  final double radius;

  @override
  State<_SkeletonBar> createState() => _SkeletonBarState();
}

class _SkeletonBarState extends State<_SkeletonBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ac = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _ac.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ink = QuestColors.text(context);
    return AnimatedBuilder(
      animation: _ac,
      builder: (_, __) {
        final a = (40 + 60 * _ac.value).round();
        return Container(
          height: widget.height,
          width: widget.width,
          decoration: BoxDecoration(
            color: ink.withAlpha(a),
            borderRadius: BorderRadius.circular(widget.radius),
          ),
        );
      },
    );
  }
}

/// Tile-shaped skeleton matching `ArcadeStatTile` proportions, shown
/// while the profile XP/quest counts are loading.
class _StatTileSkeleton extends StatelessWidget {
  const _StatTileSkeleton();

  @override
  Widget build(BuildContext context) {
    final ink = QuestColors.text(context);
    return Container(
      height: 92,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: QuestColors.cardBg(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: ink.withAlpha(60), width: 2),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _SkeletonBar(width: 70, height: 10),
          _SkeletonBar(width: 60, height: 22, radius: 6),
          _SkeletonBar(width: 50, height: 8),
        ],
      ),
    );
  }
}

/// Card-shaped skeleton mimicking the recent quests list while
/// `questHistoryProvider` is loading.
class _RecentQuestsSkeleton extends StatelessWidget {
  const _RecentQuestsSkeleton();

  @override
  Widget build(BuildContext context) {
    final ink = QuestColors.text(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: QuestColors.cardBg(context),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: ink.withAlpha(60), width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SkeletonBar(width: 140, height: 12),
          const SizedBox(height: 14),
          for (int i = 0; i < 3; i++) ...[
            Row(children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: ink.withAlpha(40),
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SkeletonBar(height: 11, width: 200),
                    SizedBox(height: 6),
                    _SkeletonBar(height: 9, width: 120),
                  ],
                ),
              ),
            ]),
            if (i < 2) const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

// ── Locked ────────────────────────────────────────────────────────────────

class _LockedCard extends StatelessWidget {
  const _LockedCard({required this.title, required this.subtitle});
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final ink = QuestColors.text(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: QuestColors.cardBg(context),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: QuestColors.osRed, width: 2),
        boxShadow: [
          BoxShadow(
            color: ink,
            offset: const Offset(4, 4),
            blurRadius: 0,
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: QuestColors.osRed,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: ink, width: 2),
            ),
            child: Icon(Icons.lock_rounded,
                color: QuestColors.onAccent(QuestColors.osRed), size: 26),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: QuestTypography.headlineMedium.copyWith(
              color: ink,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style:
                QuestTypography.bodyMedium.copyWith(color: ink.withAlpha(170)),
          ),
        ],
      ),
    );
  }
}

// ── Roll-wheel picker bottom sheet ────────────────────────────────────────
//
// Opens when the user taps ROLL THE WHEEL. Two phases:
//   1. Casino spin: the word "GENERATING" animates, every letter cycling
//      like a slot-machine column before settling on its target letter.
//   2. Pick: three random active quests are shown as chunky cards. Tapping
//      one assigns it as the user's new active quest.

class _RollPickerSheet extends ConsumerStatefulWidget {
  const _RollPickerSheet();

  @override
  ConsumerState<_RollPickerSheet> createState() => _RollPickerSheetState();
}

class _RollPickerSheetState extends ConsumerState<_RollPickerSheet> {
  // Screen-specific colour — not a theme token.
  static const Color _dialogBg = QuestColors.darkCard;

  static const _spinDuration = Duration(milliseconds: 2200);
  // 5 rerolls per rolling 24h window. Stored client-side as a list of
  // ISO timestamps; the oldest one falling out of the window is what
  // unlocks the next reroll.
  static const _rerollWindow = Duration(hours: 24);
  static const _maxRerollsPerWindow = 5;

  List<QuestModel>? _options;
  bool _spinDone = false;
  bool _assigning = false;
  bool _rerolling = false;
  String? _error;
  // Timestamps of recent rerolls within the last [_rerollWindow]. Older
  // entries are pruned on every read so this list never grows unbounded.
  List<DateTime> _rerollHistory = const [];
  int? _serverRerollsRemaining;
  int _deckKey = 0; // animation key — bumps on each reroll

  @override
  void initState() {
    super.initState();
    _loadRerollState();
    _fetchQuests();
  }

  String? get _rerollStorageKey {
    final userId = ref.read(authSessionProvider)?.id;
    if (userId == null) return null;
    return 'quest_reroll_history_$userId';
  }

  /// Legacy single-timestamp key from before the 5-per-day budget. We
  /// migrate it on first launch so an in-flight cooldown isn't lost.
  String? get _legacyRerollKey {
    final userId = ref.read(authSessionProvider)?.id;
    if (userId == null) return null;
    return 'quest_last_reroll_at_$userId';
  }

  Future<void> _loadRerollState() async {
    final key = _rerollStorageKey;
    if (key == null) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    final history = <DateTime>[];

    if (raw != null) {
      try {
        final list = jsonDecode(raw) as List<dynamic>;
        for (final entry in list) {
          final ts = DateTime.tryParse(entry as String);
          if (ts != null) history.add(ts);
        }
      } catch (_) {
        // Corrupt payload — ignore and reset.
      }
    } else {
      // First load on this version: migrate the old single-timestamp key
      // so users mid-cooldown don't suddenly get 5 fresh rerolls.
      final legacyKey = _legacyRerollKey;
      if (legacyKey != null) {
        final legacyRaw = prefs.getString(legacyKey);
        final legacy = legacyRaw == null ? null : DateTime.tryParse(legacyRaw);
        if (legacy != null) history.add(legacy);
        await prefs.remove(legacyKey);
      }
    }

    final pruned = _pruneHistory(history);
    int? serverRemaining;
    try {
      serverRemaining =
          await AppBackend.repositories.quests.getRerollsRemaining();
    } on Object {
      // Preserve the local rolling-window UX while offline. The server still
      // enforces the authoritative limit when a reroll is recorded.
    }
    if (!mounted) return;
    setState(() {
      _rerollHistory = pruned;
      _serverRerollsRemaining = serverRemaining;
    });
  }

  List<DateTime> _pruneHistory(List<DateTime> history) {
    final cutoff = DateTime.now().subtract(_rerollWindow);
    return history.where((t) => t.isAfter(cutoff)).toList()..sort();
  }

  int get _rerollsRemaining {
    final pruned = _pruneHistory(_rerollHistory);
    final used = pruned.length;
    final remaining = _maxRerollsPerWindow - used;
    final local = remaining < 0 ? 0 : remaining;
    final server = _serverRerollsRemaining;
    return server == null || local < server ? local : server;
  }

  Future<void> _fetchQuests() async {
    try {
      // Server returns up to 3 options. If the user has a pending
      // admin injection, it is pinned at index 0 and consumed in the
      // same call — so it pops up only on this first generate, never
      // resurfaces, and never appears for any other user.
      final picks =
          await ref.read(questsRepositoryProvider).getQuestPickerOptions();
      if (!mounted) return;
      setState(() => _options = picks);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'No quests available right now');
    }
  }

  Future<void> _reroll() async {
    if (_rerolling || _assigning) return;
    if (!_canRerollNow()) {
      await _showRerollLimitDialog();
      return;
    }

    setState(() {
      _rerolling = true;
      _error = null;
    });
    // Brief pause so the user sees the shuffle animation play out.
    await Future.delayed(const Duration(milliseconds: 350));
    try {
      final picks =
          await ref.read(questsRepositoryProvider).getQuestPickerOptions();
      if (!mounted) return;
      await _recordReroll();
      if (!mounted) return;
      setState(() {
        _options = picks;
        _deckKey++;
        _rerolling = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _rerolling = false;
        _error = 'No quests available right now';
      });
    }
  }

  bool _canRerollNow() => _rerollsRemaining > 0;

  /// Time until the oldest reroll in the current window expires, freeing
  /// up a slot. Returns null if rerolls are available right now.
  Duration? _rerollRefillIn() {
    if (_canRerollNow()) return null;
    final pruned = _pruneHistory(_rerollHistory);
    if (pruned.isEmpty) return null;
    final oldest = pruned.first;
    final unlock = oldest.add(_rerollWindow);
    final remaining = unlock.difference(DateTime.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  Future<void> _recordReroll() async {
    final serverRemaining = await AppBackend.repositories.quests.recordReroll();
    final now = DateTime.now();
    final next = _pruneHistory([..._rerollHistory, now]);
    final key = _rerollStorageKey;
    if (key != null) {
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode(next.map((t) => t.toIso8601String()).toList());
      await prefs.setString(key, encoded);
    }
    if (!mounted) return;
    setState(() {
      _rerollHistory = next;
      _serverRerollsRemaining = serverRemaining;
    });
  }

  Future<void> _showRerollLimitDialog() async {
    final refillIn = _rerollRefillIn();
    final hours = refillIn == null ? 24 : refillIn.inHours;
    final minutes = refillIn == null ? 0 : refillIn.inMinutes.remainder(60);
    final waitText = refillIn == null
        ? 'Try again later.'
        : 'Next reroll unlocks in ${hours}h ${minutes}m.';

    await showDialog<void>(
      context: context,
      barrierColor: QuestColors.pureBlack.withAlpha(170),
      builder: (dialogContext) {
        final ink = QuestColors.text(dialogContext);
        return AlertDialog(
          backgroundColor: QuestColors.cardBg(dialogContext),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: ink, width: 2),
          ),
          title: Text(
            'REROLL LIMIT',
            style: QuestTypography.headlineSmall.copyWith(
              color: QuestColors.osRedText,
              letterSpacing: 1,
            ),
          ),
          content: Text(
            'You\'ve used all $_maxRerollsPerWindow rerolls for this 24h window.\n\n$waitText',
            style: QuestTypography.bodyMedium.copyWith(
              color: QuestColors.text(dialogContext),
              height: 1.35,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(
                'OK',
                style: QuestTypography.labelMedium.copyWith(
                  color: QuestColors.osPrimary,
                  letterSpacing: 1,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _assign(QuestModel q) async {
    if (_assigning) return;
    setState(() => _assigning = true);
    try {
      final user = ref.read(authSessionProvider);
      if (user == null) throw StateError('Not logged in');
      await ref
          .read(questsRepositoryProvider)
          .assignSpecificQuest(user.id, q.id);
      ref.invalidate(activeQuestProvider);
      ref.invalidate(questHistoryProvider);
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('NEW QUEST: ${q.title.toUpperCase()}'),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString();
      String userMsg = 'Could not assign quest';
      if (msg.contains('already has an active quest')) {
        userMsg = 'You already have an active quest';
      }
      setState(() {
        _assigning = false;
        _error = userMsg;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ink = QuestColors.text(context);
    final onCoral = QuestColors.onAccent(QuestColors.osRed);
    final showPicker = _spinDone && _options != null;
    final pickerReady = showPicker && _options!.isNotEmpty;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Container(
          padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
          decoration: BoxDecoration(
            color: _dialogBg,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: ink, width: 2),
            boxShadow: [
              BoxShadow(
                color: ink,
                offset: const Offset(3, 5),
                blurRadius: 0,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!_spinDone || _error == null)
                _GeneratingText(
                  duration: _spinDuration,
                  onDone: () {
                    if (!mounted) return;
                    setState(() => _spinDone = true);
                  },
                ),
              const SizedBox(height: 16),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Text(
                    _error!.toUpperCase(),
                    textAlign: TextAlign.center,
                    style: QuestTypography.labelMedium.copyWith(
                      color: QuestColors.osRed,
                      letterSpacing: 1.2,
                    ),
                  ),
                )
              else if (!showPicker)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 26),
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    valueColor:
                        AlwaysStoppedAnimation<Color>(QuestColors.accentYellow),
                  ),
                )
              else if (!pickerReady)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Text(
                    'NO QUESTS AVAILABLE',
                    style: QuestTypography.labelMedium.copyWith(
                      color: QuestColors.textPrimary.withAlpha(180),
                      letterSpacing: 1.2,
                    ),
                  ),
                )
              else ...[
                Text(
                  'PICK ONE',
                  style: QuestTypography.labelSmall.copyWith(
                    color: QuestColors.textPrimary.withAlpha(180),
                    letterSpacing: 2,
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 12),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  switchInCurve: Curves.easeOut,
                  switchOutCurve: Curves.easeIn,
                  transitionBuilder: (child, anim) => SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0.15, 0),
                      end: Offset.zero,
                    ).animate(anim),
                    child: FadeTransition(opacity: anim, child: child),
                  ),
                  child: Column(
                    key: ValueKey(_deckKey),
                    children: [
                      for (var i = 0; i < _options!.length; i++) ...[
                        _QuestChoiceCard(
                          quest: _options![i],
                          disabled: _assigning || _rerolling,
                          index: i,
                          onPick: () => _assign(_options![i]),
                        ),
                        if (i < _options!.length - 1)
                          const SizedBox(height: 10),
                      ],
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap:
                          _assigning ? null : () => Navigator.of(context).pop(),
                      behavior: HitTestBehavior.opaque,
                      child: Container(
                        height: kMinTouchTarget,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: QuestColors.pureWhite.withAlpha(12),
                          borderRadius: BorderRadius.circular(11),
                          border: Border.all(
                            color: QuestColors.textPrimary.withAlpha(120),
                            width: 1.3,
                          ),
                        ),
                        child: Text(
                          'CANCEL',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: QuestTypography.labelMedium.copyWith(
                            color: QuestColors.textPrimary.withAlpha(220),
                            letterSpacing: 1.4,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (pickerReady) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      child: GestureDetector(
                        onTap: (_assigning || _rerolling) ? null : _reroll,
                        behavior: HitTestBehavior.opaque,
                        child: Container(
                          height: kMinTouchTarget,
                          alignment: Alignment.center,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          decoration: BoxDecoration(
                            color: QuestColors.osRed,
                            borderRadius: BorderRadius.circular(11),
                            border: Border.all(color: onCoral, width: 1.5),
                          ),
                          child: _rerolling
                              ? SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor:
                                        AlwaysStoppedAnimation<Color>(onCoral),
                                  ),
                                )
                              : Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.refresh_rounded,
                                        color: onCoral, size: 14),
                                    const SizedBox(width: 6),
                                    Flexible(
                                      child: Text(
                                        'RE-ROLL',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: QuestTypography.labelMedium
                                            .copyWith(
                                          color: onCoral,
                                          letterSpacing: 1.4,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    // Remaining-count chip — sits inside
                                    // the button so users see at a glance
                                    // how many of their 5 daily rerolls
                                    // are left.
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color:
                                            QuestColors.pureWhite.withAlpha(60),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(
                                          color: onCoral,
                                          width: 1,
                                        ),
                                      ),
                                      child: Text(
                                        '$_rerollsRemaining/$_maxRerollsPerWindow',
                                        maxLines: 1,
                                        style:
                                            QuestTypography.labelSmall.copyWith(
                                          color: onCoral,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 0.6,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Casino-style letter-spin reveal. Each column cycles through random glyphs
/// at ~12 fps and settles on the target letter in staggered left-to-right
/// order over [duration]. When the last letter lands, [onDone] is invoked.
class _GeneratingText extends StatefulWidget {
  const _GeneratingText({
    required this.duration,
    required this.onDone,
  });

  final Duration duration;
  final VoidCallback onDone;
  final String text = 'GENERATING';

  @override
  State<_GeneratingText> createState() => _GeneratingTextState();
}

class _GeneratingTextState extends State<_GeneratingText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ac;
  Timer? _tick;
  final _rand = Random();
  int _tickCount = 0;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _ac = AnimationController(vsync: this, duration: widget.duration)
      ..forward().whenComplete(() {
        if (!mounted || _done) return;
        _done = true;
        widget.onDone();
      });
    _tick = Timer.periodic(const Duration(milliseconds: 70), (_) {
      if (!mounted) return;
      setState(() => _tickCount++);
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _ac.dispose();
    super.dispose();
  }

  String _charAt(int i) {
    final settledAt = 0.25 + (i / widget.text.length) * 0.72;
    if (_ac.value >= settledAt) return widget.text[i];
    // Cycle through uppercase letters pseudo-randomly per tick.
    final code = 65 + ((_rand.nextInt(26) + _tickCount + i) % 26);
    return String.fromCharCode(code);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ac,
      builder: (_, __) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: List.generate(widget.text.length, (i) {
            final settledAt = 0.25 + (i / widget.text.length) * 0.72;
            final settled = _ac.value >= settledAt;
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 2),
              width: 22,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: settled
                    ? QuestColors.accentYellow
                    : QuestColors.pureWhite.withAlpha(12),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: settled
                      ? QuestColors.pureWhite
                      : QuestColors.pureWhite
                          .withAlpha(QuestColors.alphaHairline),
                  width: 1.2,
                ),
              ),
              child: Text(
                _charAt(i),
                style: QuestTypography.headlineMedium.copyWith(
                  color: settled
                      ? QuestColors.accentYellowInk
                      : QuestColors.textPrimary,
                  fontSize: 16,
                  height: 1,
                  letterSpacing: 0,
                ),
              ),
            );
          }),
        );
      },
    );
  }
}

class _QuestChoiceCard extends StatelessWidget {
  const _QuestChoiceCard({
    required this.quest,
    required this.onPick,
    required this.index,
    required this.disabled,
  });

  final QuestModel quest;
  final VoidCallback onPick;
  final int index;
  final bool disabled;

  Color _tint() {
    switch (index % 3) {
      case 0:
        return QuestColors.osRed;
      case 1:
        return QuestColors.accentYellow;
      default:
        return QuestColors.osPrimary;
    }
  }

  /// Difficulty chip color for the quest row.
  (Color, String) _difficultyStyle() {
    switch (quest.difficulty.toLowerCase()) {
      case 'easy':
        return (QuestColors.successGreen, 'EASY');
      case 'hard':
        return (QuestColors.osRed, 'HARD');
      case 'medium':
      default:
        return (QuestColors.accentYellow, 'MEDIUM');
    }
  }

  @override
  Widget build(BuildContext context) {
    final ink = QuestColors.text(context);
    final tint = _tint();
    final onTint = QuestColors.onAccent(tint);
    final (diffColor, diffLabel) = _difficultyStyle();
    // Tap and long-press both open the preview sheet — no auto-pick. The
    // sheet's PICK THIS QUEST button is the actual commit step, with
    // CLOSE giving an obvious back-out. Players were being assigned
    // quests on a stray tap; the explicit confirm prevents that.
    void openPreview() {
      HapticFeedback.selectionClick();
      _showQuestPreview(
        context,
        quest: quest,
        tint: tint,
        onPick: onPick,
      );
    }

    return GestureDetector(
      onTap: disabled ? null : openPreview,
      onLongPress: disabled ? null : openPreview,
      behavior: HitTestBehavior.opaque,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 150),
        opacity: disabled ? 0.55 : 1.0,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: tint,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: ink, width: 2),
            boxShadow: [
              BoxShadow(
                color: ink,
                offset: const Offset(3, 3),
                blurRadius: 0,
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title row with icon + chevron
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: QuestColors.pureWhite.withAlpha(40),
                      borderRadius: BorderRadius.circular(11),
                      border: Border.all(color: onTint, width: 1.5),
                    ),
                    alignment: Alignment.center,
                    child: Icon(Icons.flag_rounded, color: onTint, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      quest.title,
                      style: QuestTypography.headlineSmall.copyWith(
                        color: onTint,
                        fontSize: 14,
                        letterSpacing: 0.4,
                        height: 1.2,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(Icons.chevron_right_rounded, color: onTint, size: 22),
                ],
              ),
              if (quest.description.trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  quest.description,
                  style: QuestTypography.bodySmall.copyWith(
                    color: QuestColors.onAccentSoft(tint),
                    fontSize: 12,
                    height: 1.3,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  // Difficulty chip
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: diffColor,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: ink, width: 1.3),
                    ),
                    child: Text(
                      diffLabel,
                      style: QuestTypography.labelSmall.copyWith(
                        color: QuestColors.onAccent(diffColor),
                        fontSize: 10,
                        letterSpacing: 1.1,
                      ),
                    ),
                  ),
                  // XP chip
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: QuestColors.pureWhite.withAlpha(36),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: onTint, width: 1.3),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.bolt_rounded, color: onTint, size: 12),
                        const SizedBox(width: 3),
                        Text(
                          '+${quest.xpReward} XP',
                          maxLines: 1,
                          style: QuestTypography.labelSmall.copyWith(
                            color: onTint,
                            fontSize: 10,
                            letterSpacing: 1,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Modal list that shows every submission still awaiting admin review.
/// Reached by tapping the pending-review card on the home page when there
/// is more than one pending submission.
class _PendingListDialog extends StatelessWidget {
  const _PendingListDialog({required this.pending});
  final List<UserQuestModel> pending;

  @override
  Widget build(BuildContext context) {
    final ink = QuestColors.text(context);
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Container(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
          decoration: BoxDecoration(
            color: QuestColors.cardBg(context),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: ink, width: 2),
            boxShadow: [
              BoxShadow(color: ink, offset: const Offset(3, 5), blurRadius: 0),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: QuestColors.accentYellow,
                      borderRadius: BorderRadius.circular(11),
                      border: Border.all(color: ink, width: 2),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(Icons.hourglass_top_rounded,
                        color: QuestColors.accentYellowInk, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'IN REVIEW',
                          style: QuestTypography.labelSmall.copyWith(
                            color: ink.withAlpha(QuestColors.alphaInkMuted),
                            letterSpacing: 1.4,
                            fontSize: 10,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${pending.length} SUBMISSIONS',
                          style: QuestTypography.headlineSmall.copyWith(
                            color: ink,
                            fontSize: 16,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    behavior: HitTestBehavior.opaque,
                    child: BsMinTouch(
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: QuestColors.cardBg(context),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: ink, width: 1.6),
                        ),
                        alignment: Alignment.center,
                        child: Icon(Icons.close_rounded, color: ink, size: 16),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              // Submissions list — scrollable if long
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      for (var i = 0; i < pending.length; i++) ...[
                        _PendingRow(
                          quest: pending[i],
                          onTap: () {
                            Navigator.of(context).pop();
                            context.pushNamed(
                              RouteNames.questDetails,
                              pathParameters: {
                                'id': pending[i].questId,
                              },
                            );
                          },
                        ),
                        if (i < pending.length - 1) const SizedBox(height: 8),
                      ],
                    ],
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

class _PendingRow extends StatelessWidget {
  const _PendingRow({required this.quest, required this.onTap});
  final UserQuestModel quest;
  final VoidCallback onTap;

  String _when(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'JUST NOW';
    if (diff.inMinutes < 60) return '${diff.inMinutes}M AGO';
    if (diff.inHours < 24) return '${diff.inHours}H AGO';
    return '${diff.inDays}D AGO';
  }

  @override
  Widget build(BuildContext context) {
    final ink = QuestColors.text(context);
    final ts = quest.completedAt ?? quest.assignedAt;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: QuestColors.surfaceBg(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: ink, width: 1.8),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: QuestColors.accentYellow.withAlpha(60),
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: QuestColors.accentYellow, width: 1.4),
              ),
              alignment: Alignment.center,
              child: const Icon(Icons.hourglass_top_rounded,
                  color: QuestColors.accentYellowInk, size: 16),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    quest.quest?.title ?? 'Submission',
                    style: QuestTypography.headlineSmall.copyWith(
                      color: ink,
                      fontSize: 13,
                      height: 1.2,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _when(ts),
                    style: QuestTypography.labelSmall.copyWith(
                      color: ink.withAlpha(QuestColors.alphaInkMuted),
                      fontSize: 10,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                color: ink.withAlpha(QuestColors.alphaInkMuted), size: 20),
          ],
        ),
      ),
    );
  }
}

// ── Recent quests card ──────────────────────────────────────────────────────
//
// Shows the 5 most recently touched user_quests grouped by status
// (approved / rejected / expired / pending / appealed). Tap "SEE MORE" to
// push to the full Quest History page.

class _RecentQuestsCard extends StatelessWidget {
  const _RecentQuestsCard({required this.quests, required this.onSeeMore});
  final List<UserQuestModel> quests;
  final VoidCallback onSeeMore;

  @override
  Widget build(BuildContext context) {
    final ink = QuestColors.text(context);
    final sorted = [...quests]..sort((a, b) {
        final at = a.completedAt ?? a.assignedAt;
        final bt = b.completedAt ?? b.assignedAt;
        return bt.compareTo(at);
      });
    final latest = sorted.take(5).toList();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: QuestColors.cardBg(context),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: ink, width: 2),
        boxShadow: [
          BoxShadow(color: ink, offset: const Offset(3, 3), blurRadius: 0),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Section header — full-width hairline, no SEE MORE here
          Row(
            children: [
              Container(width: 20, height: 2, color: ink),
              const SizedBox(width: 8),
              Text(
                'RECENT QUESTS',
                style: QuestTypography.headlineSmall.copyWith(
                  color: ink,
                  fontSize: 14,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  height: 2,
                  color: ink.withAlpha(QuestColors.alphaWhisper),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < latest.length; i++) ...[
            _RecentQuestRow(q: latest[i]),
            if (i < latest.length - 1) const SizedBox(height: 6),
          ],
          const SizedBox(height: 12),
          // SEE MORE button — centered at the bottom of the card
          Center(
            child: GestureDetector(
              onTap: onSeeMore,
              behavior: HitTestBehavior.opaque,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: QuestColors.osPrimary,
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(color: ink, width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: ink,
                      offset: const Offset(0, 2),
                      blurRadius: 0,
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'SEE MORE',
                      style: QuestTypography.labelMedium.copyWith(
                        color: QuestColors.osTextOnPrimary,
                        fontSize: 11,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.chevron_right_rounded,
                        color: QuestColors.osTextOnPrimary, size: 16),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RecentQuestRow extends StatelessWidget {
  const _RecentQuestRow({required this.q});
  final UserQuestModel q;

  (String, Color) _statusStyle(BuildContext context) {
    switch (q.status) {
      case UserQuestStatus.approved:
        return ('ACCEPTED', QuestColors.successGreen);
      case UserQuestStatus.rejected:
        return ('REJECTED', QuestColors.osRed);
      case UserQuestStatus.expired:
        return ('TIMED OUT', QuestColors.osTextMuted);
      case UserQuestStatus.submitted:
        return ('PENDING', QuestColors.accentYellow);
      case UserQuestStatus.assigned:
        return ('ACTIVE', QuestColors.osPrimary);
      default:
        return (q.status.toUpperCase(), QuestColors.osTextMuted);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ink = QuestColors.text(context);
    final (statusText, statusColor) = _statusStyle(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      decoration: BoxDecoration(
        // The frame draws these as white cards with a full 2px outline, not
        // warm surface behind a hairline.
        color: QuestColors.osCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ink, width: 2),
        boxShadow: [
          // The shadow carries the status. Reading a row's outcome from the
          // colour under it is faster than reading the label, which is the
          // whole reason the design tints it rather than using ink here.
          BoxShadow(
            color: statusColor,
            offset: const Offset(3, 3),
            blurRadius: 0,
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            // h10 at r5 with a square box is a circle, which is what the
            // render shows. The radius is only half the story: at width 8
            // the same radius draws a stadium, not a dot.
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: statusColor,
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: ink, width: 2),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              q.quest?.title ?? 'Quest',
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              style: QuestTypography.labelMedium.copyWith(
                color: ink,
                fontSize: 12,
                letterSpacing: 0.2,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: statusColor,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: ink, width: 1),
            ),
            child: Text(
              statusText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: QuestTypography.labelSmall.copyWith(
                color: QuestColors.onAccent(statusColor),
                fontSize: 9,
                letterSpacing: 0.8,
                height: 1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Semi-full bottom sheet that previews a quest's full brief before the
/// user commits to picking it. Triggered by long-pressing a quest card in
/// the roll picker. Caller passes [tint] so the sheet visually matches the
/// card the user pressed.
Future<void> _showQuestPreview(
  BuildContext context, {
  required QuestModel quest,
  required Color tint,
  required VoidCallback onPick,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: QuestColors.pureBlack.withAlpha(170),
    useSafeArea: true,
    builder: (sheetContext) => _QuestPreviewSheet(
      quest: quest,
      tint: tint,
      onPick: () {
        Navigator.of(sheetContext).pop();
        onPick();
      },
    ),
  );
}

class _QuestPreviewSheet extends StatelessWidget {
  const _QuestPreviewSheet({
    required this.quest,
    required this.tint,
    required this.onPick,
  });

  final QuestModel quest;
  final Color tint;
  final VoidCallback onPick;

  (Color, String) _difficultyStyle() {
    switch (quest.difficulty.toLowerCase()) {
      case 'easy':
        return (QuestColors.successGreen, 'EASY');
      case 'hard':
        return (QuestColors.osRed, 'HARD');
      case 'medium':
      default:
        return (QuestColors.accentYellow, 'MEDIUM');
    }
  }

  String _durationLabel() {
    final h = quest.durationHours;
    if (h <= 0) return 'NO LIMIT';
    if (h < 24) return '${h}H';
    final d = h ~/ 24;
    final rem = h % 24;
    return rem == 0 ? '${d}D' : '${d}D ${rem}H';
  }

  @override
  Widget build(BuildContext context) {
    final ink = QuestColors.text(context);
    final onTint = QuestColors.onAccent(tint);
    final (diffColor, diffLabel) = _difficultyStyle();
    final mediaH = MediaQuery.of(context).size.height;

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: QuestColors.bg(context),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border.all(color: ink, width: 2),
            boxShadow: [
              BoxShadow(color: ink, offset: const Offset(0, -3), blurRadius: 0),
            ],
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 10, bottom: 6),
                child: Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: ink.withAlpha(60),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: tint,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: ink, width: 2),
                          boxShadow: [
                            BoxShadow(
                                color: ink,
                                offset: const Offset(4, 4),
                                blurRadius: 0),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: QuestColors.pureWhite.withAlpha(40),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: onTint, width: 1.5),
                                ),
                                alignment: Alignment.center,
                                child: Icon(Icons.flag_rounded,
                                    color: onTint, size: 22),
                              ),
                              const SizedBox(width: 12),
                              if (quest.category.trim().isNotEmpty)
                                Flexible(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 9, vertical: 4),
                                    decoration: BoxDecoration(
                                      color:
                                          QuestColors.pureWhite.withAlpha(36),
                                      borderRadius: BorderRadius.circular(8),
                                      border:
                                          Border.all(color: onTint, width: 1.3),
                                    ),
                                    child: Text(
                                      quest.category.toUpperCase(),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style:
                                          QuestTypography.labelSmall.copyWith(
                                        color: onTint,
                                        fontSize: 10,
                                        letterSpacing: 1.2,
                                      ),
                                    ),
                                  ),
                                ),
                            ]),
                            const SizedBox(height: 14),
                            Text(
                              quest.title,
                              style: QuestTypography.headlineLarge.copyWith(
                                color: onTint,
                                fontSize: 22,
                                height: 1.2,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(children: [
                        _PreviewStat(
                          label: 'DIFFICULTY',
                          value: diffLabel,
                          tint: diffColor,
                        ),
                        const SizedBox(width: 10),
                        _PreviewStat(
                          label: 'REWARD',
                          value: '+${quest.xpReward} XP',
                          tint: QuestColors.osPrimary,
                        ),
                        const SizedBox(width: 10),
                        _PreviewStat(
                          label: 'TIME',
                          value: _durationLabel(),
                          tint: QuestColors.accentYellow,
                        ),
                      ]),
                      const SizedBox(height: 20),
                      Text(
                        'THE BRIEF',
                        style: QuestTypography.labelSmall.copyWith(
                          color: ink.withAlpha(140),
                          fontSize: 11,
                          letterSpacing: 1.4,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        quest.description.trim().isEmpty
                            ? 'No further details. Pick it and find out.'
                            : quest.description,
                        style: QuestTypography.bodyMedium.copyWith(
                          color: ink,
                          fontSize: 15,
                          height: 1.45,
                        ),
                      ),
                      SizedBox(height: mediaH * 0.04),
                    ],
                  ),
                ),
              ),
              Container(
                padding: EdgeInsets.fromLTRB(
                  16,
                  10,
                  16,
                  10 + MediaQuery.of(context).padding.bottom * 0.4,
                ),
                decoration: BoxDecoration(
                  color: QuestColors.bg(context),
                  border: Border(
                      top: BorderSide(color: ink.withAlpha(40), width: 1)),
                ),
                child: Row(children: [
                  Expanded(
                    flex: 1,
                    child: GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      behavior: HitTestBehavior.opaque,
                      child: Container(
                        height: 48,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: QuestColors.bg(context),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: ink, width: 2),
                          boxShadow: [
                            BoxShadow(
                                color: ink,
                                offset: const Offset(3, 3),
                                blurRadius: 0),
                          ],
                        ),
                        child: Text(
                          'CLOSE',
                          style: QuestTypography.labelMedium.copyWith(
                            color: ink,
                            fontSize: 12,
                            letterSpacing: 1.4,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: GestureDetector(
                      onTap: onPick,
                      behavior: HitTestBehavior.opaque,
                      child: Container(
                        height: 48,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: tint,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: ink, width: 2),
                          boxShadow: [
                            BoxShadow(
                                color: ink,
                                offset: const Offset(3, 3),
                                blurRadius: 0),
                          ],
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.bolt_rounded, color: onTint, size: 18),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                'PICK THIS QUEST',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: QuestTypography.labelLarge.copyWith(
                                  color: onTint,
                                  fontSize: 13,
                                  letterSpacing: 1.2,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ]),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PreviewStat extends StatelessWidget {
  const _PreviewStat({
    required this.label,
    required this.value,
    required this.tint,
  });

  final String label;
  final String value;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    final ink = QuestColors.text(context);
    // Full-opacity on-ground colour: alpha-muting type on an accent fill
    // drops it back under AA, so size and weight carry the hierarchy.
    final onTint = QuestColors.onAccent(tint);
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        decoration: BoxDecoration(
          color: tint,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: ink, width: 2),
          boxShadow: [
            BoxShadow(color: ink, offset: const Offset(3, 3), blurRadius: 0),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: QuestTypography.labelSmall.copyWith(
                color: onTint,
                fontSize: 9,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 3),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: QuestTypography.headlineSmall.copyWith(
                  color: onTint,
                  fontSize: 16,
                  letterSpacing: 0.4,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
