import 'package:app_repositories/app_repositories.dart' show ApiException;
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:app_core/app_core.dart';
import 'package:app_models/app_models.dart';
import 'package:app_contracts/app_contracts.dart' show UserQuestStatus;
import 'package:shared_ui/shared_ui.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../../core/providers/account_status_provider.dart';
import '../../../../core/providers/auth_session_provider.dart';
import '../../../../core/providers/current_profile_provider.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/providers/streak_provider.dart';
import '../../../../core/utils/streak_utils.dart';
import '../../../notifications/presentation/providers/notifications_provider.dart';
import '../../../collab/presentation/pages/collab_page.dart';
import '../../../submissions/data/submission_providers.dart';
import '../../data/quest_providers.dart';
import '../widgets/arcade_page_chrome.dart';
import '../widgets/home_arcade_widgets.dart';
import '../widgets/home_extras.dart';
import '../widgets/discovery_shelves.dart';
import '../../../../core/backend/app_backend.dart';
import '../widgets/active_journey_card.dart';
import '../providers/journey_providers.dart';

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

class _HomePageState extends ConsumerState<HomePage> {
  // Realtime for user_quests + submissions lives in `BottomNavShell` —
  // having a duplicate subscription here meant every DB event triggered
  // two parallel refetch waves. The shell sub invalidates the same
  // providers HomePage cares about (activeQuest, questHistory,
  // userSubmissions) and stays alive across tab switches, which is
  // strictly better.
  StreamSubscription<List<Map<String, dynamic>>>? _questStream;

  @override
  void dispose() {
    _questStream?.cancel();
    super.dispose();
  }

  bool _rolling = false;

  Future<void> _rollWheel() async {
    if (_rolling) return;
    _rolling = true;
    try {
      await showRollPicker(context);
    } finally {
      _rolling = false;
    }
  }

  Future<void> _acceptQuestOfTheDay(QuestOfTheDayModel qotd) async {
    // Reject early only on a live quest — assigning a second 'assigned'
    // quest would fail on user_quests_one_assigned_idx or overwrite the
    // current attempt depending on timing. A submitted-but-unreviewed quest
    // no longer blocks this: migration 0021 narrowed that index to
    // 'assigned', so the server accepts the roll.
    final existing = ref.read(activeQuestProvider).valueOrNull;
    if (existing != null && existing.status == UserQuestStatus.assigned) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'You already have an active quest. Finish or cancel it first.',
          ),
        ),
      );
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

  /// The completed-count a journey card should animate from, if the server
  /// still owes this player an unlock moment.
  ///
  /// Captured once per run: the server stops reporting the unlock as soon as
  /// it is acknowledged, and the transition must not vanish halfway through
  /// because its own trigger was cleared.
  final Map<String, int> _advanceFrom = {};

  int? _captureAdvance(JourneyRun run) {
    if (run.unseenUnlock == null) return _advanceFrom[run.runId];
    return _advanceFrom.putIfAbsent(run.runId, () => run.completedSteps);
  }

  /// Marks the unlock seen once the card has actually shown the transition.
  ///
  /// Show first, acknowledge after: if the app dies mid-animation the server
  /// should still owe the moment rather than having forgotten it. The
  /// richer celebration lives on the journey page — here the card simply
  /// moves from the old state to the new one and stays there, which is the
  /// part that was missing when this was a modal that appeared and left.
  Future<void> _acknowledge(String runId) async {
    try {
      await AppBackend.repositories.journeys.acknowledgeUnlock(runId);
      if (mounted) ref.invalidate(activeJourneysProvider);
    } catch (_) {
      // Worst case the moment is offered again.
    }
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

    // Server-derived (#46). The client calculation this replaces counted
    // whatever history page was loaded, treated rejected attempts as activity,
    // and bucketed by local date while the reminder sweep runs in UTC.
    final serverStreak = ref.watch(streakProvider).valueOrNull;
    final streak = serverStreak?.current ?? 0;

    final bool locked =
        accountStatus == 'suspended' || accountStatus == 'banned';

    return Scaffold(
      backgroundColor: QuestColors.bg(context),
      body: Stack(
        children: [
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
                            // The greeting is the whole header: no wordmark,
                            // no headline — HELLO, then the player's name.
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    'HELLO,',
                                    style:
                                        QuestTypography.osLabelMedium.copyWith(
                                      color: QuestColors.osTextSecondary,
                                      letterSpacing: 1.6,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    displayName.toUpperCase(),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style:
                                        QuestTypography.displayLarge.copyWith(
                                      // Same navy ink as the bottom nav pill.
                                      color: QuestColors.osTextPrimary,
                                      fontSize: 28,
                                      fontWeight: FontWeight.w800,
                                      height: 1,
                                      letterSpacing: -0.3,
                                    ),
                                  ),
                                ],
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
                          loading: () => const _HeroSkeleton(),
                          error: (_, __) => const _HeroSkeleton(),
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

                            // The pending card and the generator now coexist.
                            // Review latency is not something a player can
                            // clear themselves, so hiding the generator behind
                            // it left them with nothing to do for hours. The
                            // card stays on screen so they can still check on
                            // what is in review — see migration 0021, which
                            // narrowed the unique index to 'assigned' only.

                            // A journey outlives its checkpoints. Approving
                            // stage 1 clears the assigned quest, and before
                            // this the whole journey vanished with it —
                            // leaving the player to rediscover stage 2 on
                            // Home as if it were a stranger. The card sits
                            // above the hero so the parent stays visible
                            // whatever the child quest is doing.
                            final journey = ref.watch(featuredJourneyProvider);

                            return Column(
                              children: [
                                if (pendingList.isNotEmpty) ...[
                                  _PendingReviewCard(
                                    pending: pendingList,
                                    onOpen: () => _showPendingList(pendingList),
                                  ),
                                  const SizedBox(height: 14),
                                ],
                                if (journey != null) ...[
                                  ActiveJourneyCard(
                                    run: journey,
                                    advanceFrom: _captureAdvance(journey),
                                    onUnlockShown: () =>
                                        _acknowledge(journey.runId),
                                    onOpen: () => context.pushNamed(
                                      RouteNames.journeyDetail,
                                      pathParameters: {'runId': journey.runId},
                                    ),
                                    onOpenMap: () =>
                                        context.pushNamed(RouteNames.map),
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
                                else if (journey == null ||
                                    !journey.canContinue)
                                  // Offered only when there is nothing else
                                  // to do. Rolling a fresh quest while a
                                  // checkpoint waits would pull the player
                                  // off a journey they already started.
                                  _SlotMachineZone(onGenerate: _rollWheel),
                              ],
                            );
                          },
                        ),
                      ),
                    ),

                    // ── Group quests — right under the generator, where a
                    // player deciding what to do next is already looking.
                    if (!locked)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(
                              QuestSpacing.screenPadding,
                              0,
                              QuestSpacing.screenPadding,
                              16),
                          child: ArcadeCard(
                            padding: EdgeInsets.zero,
                            borderRadius: QuestSpacing.radiusCard,
                            shadowOffset: 3,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(
                                  QuestSpacing.inner(QuestSpacing.radiusCard,
                                      QuestSpacing.cardBorderWidth)),
                              child: ExpansionTile(
                                tilePadding:
                                    const EdgeInsets.symmetric(horizontal: 14),
                                leading: const Icon(Icons.groups_rounded,
                                    color: QuestColors.osTextPrimary),
                                title: Text('GROUP QUESTS',
                                    style: QuestTypography.osHeadlineSmall),
                                subtitle: Text(
                                  'Create a group, invite friends or join by code',
                                  style: QuestTypography.osBodySmall.copyWith(
                                      color: QuestColors.osTextSecondary),
                                ),
                                children: const [CollabPage(embedded: true)],
                              ),
                            ),
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

                    // ── Discovery shelves ──
                    // Below the roll and the hero, deliberately: the
                    // spontaneous "give me something now" loop stays the top
                    // of this screen, and discovery is what you scroll into
                    // once that is answered. The server chooses which
                    // shelves exist, so this renders nothing at all when
                    // there is nothing worth showing.
                    const SliverToBoxAdapter(child: DiscoveryShelves()),

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
                          longestStreak: serverStreak?.longest ?? longestStreak,
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
    // Ink on gold, never white: white on gold measures 1.6:1.
    final fg = QuestColors.onAccent(QuestColors.osAccent);
    final count = pending.length;
    final multiple = count > 1;
    final headline = multiple
        ? '$count SUBMISSIONS WAITING FOR A MODERATOR'
        : (pending.isNotEmpty
            ? (pending.first.quest?.title ?? 'Your submission').toUpperCase()
            : 'YOUR SUBMISSION');

    return GestureDetector(
      onTap: onOpen,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: QuestColors.osAccent,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: ink, width: 2),
          boxShadow: QuestSpacing.shadowMd,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              multiple
                  ? AppLocalizations.of(context)!.inReviewTapToSeeAll
                  : 'IN REVIEW',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: QuestTypography.osLabelMedium.copyWith(
                color: fg,
                fontSize: 10,
                letterSpacing: 1.1,
              ),
            ),
            const SizedBox(height: 9),
            Text(
              headline,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: QuestTypography.osHeadlineLarge.copyWith(
                color: fg,
                fontSize: 19,
                height: 1.15,
                letterSpacing: -0.48,
              ),
            ),
            const SizedBox(height: 9),
            Text(
              'Tap to check on these. You can start a new quest '
              'while they wait.',
              style: QuestTypography.osBodySmall.copyWith(
                color: fg,
                fontSize: 13,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Slot machine zone ─────────────────────────────────────────────────────

class _SlotMachineZone extends ConsumerWidget {
  const _SlotMachineZone({required this.onGenerate});
  final VoidCallback onGenerate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ink = QuestColors.text(context);
    final budgetAsync = ref.watch(rerollBudgetProvider);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 18),
      decoration: BoxDecoration(
        // The design draws this as a white card, not an ink panel: it is
        // the one thing to do on an empty home, so it should read as the
        // bright surface rather than recede.
        color: QuestColors.osCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: ink, width: 2),
        // A *coloured* shadow marks the single most important thing on
        // screen; everything else takes ink. With no active quest, that is
        // this card. 6px, coral, per the frame.
        boxShadow: QuestSpacing.hardShadow(6, color: QuestColors.osRed),
      ),
      child: Column(
        children: [
          const _Reels(),
          const SizedBox(height: 16),
          // Jade, 56pt, r14, no icon — the frame's GENERATE A QUEST. It
          // was gold and 48pt with a die glyph, which made the one action
          // on an empty home read as a secondary control.
          ArcadeButton(
            label: AppLocalizations.of(context)!.generateAQuest,
            variant: ArcadeButtonVariant.positive,
            onTap: onGenerate,
          ),
          const SizedBox(height: 16),
          // The frame's `5 REROLLS LEFT · RESETS IN 6H`. A wrong count is
          // worse than none, so a failed read prints nothing rather than
          // guessing or sitting on a spinner forever.
          if (budgetAsync.hasValue || budgetAsync.isLoading)
            Text(
              _rerollLine(budgetAsync.valueOrNull),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: QuestTypography.osLabelSmall.copyWith(
                color: QuestColors.osTextSecondary,
                fontSize: 10,
                letterSpacing: 0.9,
              ),
            ),
        ],
      ),
    );
  }

  /// `5 REROLLS LEFT · RESETS IN 6H`. The reset half only appears once the
  /// budget is spent, because that is the only time it is a real number.
  static String _rerollLine(RerollBudget? budget) {
    if (budget == null) return 'CHECKING YOUR REROLLS';
    final left = '${budget.remaining} REROLLS LEFT';
    final refill = budget.refillIn;
    if (refill == null) return left;
    final hours = refill.inHours;
    return hours >= 1
        ? '$left · RESETS IN ${hours}H'
        : '$left · RESETS IN ${refill.inMinutes}M';
  }
}

/// The slot-machine reels: three warm-surface tiles, per the design frame.
///
/// This replaced a hand-painted Pac-Man scene on a black strip. The frame
/// draws plain 78pt reels — `#FFF1D6` ground, 2px ink border, 12px radius,
/// a 26px glyph — and the black strip could not survive inside the white
/// card the frame specifies anyway: its pale dot palette was chosen for
/// black.
class _Reels extends StatefulWidget {
  const _Reels();

  @override
  State<_Reels> createState() => _ReelsState();
}

class _ReelsState extends State<_Reels> with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    duration: const Duration(milliseconds: 1400),
    vsync: this,
  )..repeat();

  /// The reels idle rather than sit dead: each cycles its glyph on its own
  /// phase, so the zone reads as a machine waiting to be pulled.
  static const List<String> _glyphs = ['\u25C7', '\u25C8', '\u25C6'];

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
    if (!mounted || confirmed != true || _canceling) return;

    setState(() => _canceling = true);
    try {
      // abandonQuest, not markQuestExpired: the server only accepts the
      // expiry route once the timer has run out, and this button only shows
      // while the quest is still running — so it always failed with
      // QUEST_NOT_EXPIRABLE.
      await ref
          .read(questsRepositoryProvider)
          .abandonQuest(widget.activeQuest.id);
      ref.invalidate(activeQuestProvider);
      ref.invalidate(questHistoryProvider);
      ref.invalidate(rerollBudgetProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Quest canceled')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _canceling = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(mapDbError(e, action: 'cancel quest'))),
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
        onGenerate: () => showRollPicker(context),
      );
    }

    final ink = QuestColors.text(context);
    // The panel is ink; white on it is correct and must stay.
    const panel = QuestColors.osTextPrimary;
    const onPanel = QuestColors.pureWhite;
    const onPanelSoft = QuestColors.textSecondary; // #C7C0E0
    const rule = QuestColors.border; // #2A2450

    // Gold while the timer is live. Coral is the under-five-minutes state,
    // and it is the only thing that changes this number's colour.
    final urgent = _left <= const Duration(minutes: 5);
    final category = quest?.category ?? '';
    final elapsed = _elapsedFraction();

    return GestureDetector(
      // Long press remains a shortcut; the labelled action below is primary.
      onLongPress: _canceling ? null : _confirmCancelQuest,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: panel,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: ink, width: 2),
          // The hero stays an ink panel, but its shadow is violet rather
          // than ink: a coloured shadow marks the single most important
          // thing on screen, and while a quest is running that is this.
          // 6px is the spec's depth for hero panels.
          boxShadow: QuestSpacing.hardShadow(6, color: QuestColors.osPrimary),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    AppLocalizations.of(context)!.activeQuest.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: QuestTypography.labelMedium.copyWith(
                      color: onPanelSoft,
                      fontSize: 10,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
                if (category.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  // On the ink panel the tag's outline is cream, not ink —
                  // an ink border on an ink ground is invisible.
                  _PanelTag(
                    label: category,
                    tint: QuestColors.category(category),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 14),
            Text(
              (quest?.title ?? 'Quest').toUpperCase(),
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: QuestTypography.displayMedium.copyWith(
                color: onPanel,
                fontSize: 26,
                height: 1.08,
                letterSpacing: -0.78,
              ),
            ),
            const SizedBox(height: 14),
            Container(
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: rule, width: 2)),
              ),
              padding: const EdgeInsets.only(top: 13),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          AppLocalizations.of(context)!.timeLeft.toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: QuestTypography.labelMedium.copyWith(
                            color: onPanelSoft,
                            fontSize: 10,
                            letterSpacing: 1.1,
                          ),
                        ),
                        const SizedBox(height: 2),
                        // Mono and zero-padded, so the width is identical on
                        // every tick and nothing beside it reflows.
                        Text(
                          ArcadeTimer.format(_left),
                          maxLines: 1,
                          style: QuestTypography.labelMedium.copyWith(
                            color: urgent
                                ? QuestColors.osRed
                                : QuestColors.osAccent,
                            fontSize: 32,
                            letterSpacing: 0,
                            height: 1,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        AppLocalizations.of(context)!.reward.toUpperCase(),
                        maxLines: 1,
                        style: QuestTypography.labelMedium.copyWith(
                          color: onPanelSoft,
                          fontSize: 10,
                          letterSpacing: 1.1,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${quest?.xpReward ?? 0} XP',
                        maxLines: 1,
                        style: QuestTypography.displaySmall.copyWith(
                          color: QuestColors.osSuccess,
                          fontSize: 24,
                          height: 1,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            // 12pt track with a cream outline and a gold fill, draining as
            // the timer runs down.
            Container(
              height: 12,
              padding: const EdgeInsets.all(1),
              decoration: BoxDecoration(
                borderRadius:
                    BorderRadius.circular(QuestSpacing.radiusMeterTrack),
                border: Border.all(color: QuestColors.osBg, width: 2),
              ),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: FractionallySizedBox(
                  widthFactor: elapsed,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: QuestColors.osAccent,
                      // Concentric with the track above: 2px border + 1px
                      // padding in, so 3px off the track's radius.
                      borderRadius: BorderRadius.circular(
                        QuestSpacing.inner(QuestSpacing.radiusMeterTrack, 3),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _PanelButton(
                    label: 'SUBMIT PROOF',
                    fill: QuestColors.osRed,
                    fg: QuestColors.onAccent(QuestColors.osRed),
                    fontSize: 15,
                    onTap: widget.onSubmit,
                  ),
                ),
                const SizedBox(width: 9),
                _PanelButton(
                  label: 'DETAILS',
                  fill: null,
                  fg: onPanel,
                  fontSize: 14,
                  onTap: widget.onOpen,
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              style: TextButton.styleFrom(
                foregroundColor: onPanelSoft,
                minimumSize: const Size(44, 44),
              ),
              onPressed: _canceling ? null : _confirmCancelQuest,
              icon: const Icon(Icons.close_rounded, size: 18),
              label: Text(_canceling ? 'CANCELING…' : 'CANCEL QUEST'),
            ),
          ],
        ),
      ),
    );
  }

  /// How much of the window has been used, 0..1. Drives the gold meter.
  /// Falls back to full when the server sent no assignment window.
  double _elapsedFraction() {
    final expires = widget.activeQuest.expiresAt;
    if (expires == null) return 1;
    final total = expires.difference(widget.activeQuest.assignedAt);
    if (total.inSeconds <= 0) return 1;
    final used = total - _left;
    return (used.inSeconds / total.inSeconds).clamp(0.0, 1.0);
  }
}

/// A category tag drawn *on* the ink hero: the fill is the category, the
/// outline is cream. Ink on ink would vanish, which is why this is not
/// `ArcadeCategoryTag`.
class _PanelTag extends StatelessWidget {
  const _PanelTag({required this.label, required this.tint});
  final String label;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: tint,
        borderRadius: BorderRadius.circular(QuestSpacing.radiusMeterTrack),
        border: Border.all(color: QuestColors.osBg, width: 2),
      ),
      child: Text(
        label.toUpperCase(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: QuestTypography.labelMedium.copyWith(
          // The tint is the ground, so the helper decides the ink.
          color: QuestColors.onAccent(tint),
          fontSize: 10,
          letterSpacing: 1.1,
        ),
      ),
    );
  }
}

/// The hero's own button: 52pt, `r13`, a 2px **cream** outline, no shadow.
///
/// Not `ArcadeButton`, which is 56pt with an ink outline and an ink
/// shadow — both invisible against the ink panel this sits on.
class _PanelButton extends StatelessWidget {
  const _PanelButton({
    required this.label,
    required this.fill,
    required this.fg,
    required this.fontSize,
    required this.onTap,
  });

  final String label;

  /// Null means transparent — the frame's DETAILS button.
  final Color? fill;
  final Color fg;
  final double fontSize;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(QuestSpacing.radiusPanel),
          border: Border.all(color: QuestColors.osBg, width: 2),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: QuestTypography.buttonText.copyWith(
            color: fg,
            fontSize: fontSize,
            letterSpacing: 0.75,
            height: 1,
          ),
        ),
      ),
    );
  }
}

/// Shown when the quest expired without a submission./// Shown when the quest expired without a submission. Coral-red card with
/// big TIME OVER label and a single "GENERATE NEW QUEST" button.
class _TimeOverCard extends StatelessWidget {
  const _TimeOverCard({required this.title, required this.onGenerate});
  final String title;
  final VoidCallback onGenerate;

  @override
  Widget build(BuildContext context) {
    final ink = QuestColors.text(context);
    // Ink on coral. White on coral measures 3.03:1 and fails AA.
    final fg = QuestColors.onAccent(QuestColors.osRed);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: QuestColors.osRed,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: ink, width: 2),
        boxShadow: QuestSpacing.shadowMd,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'TIME OVER',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: QuestTypography.osLabelMedium.copyWith(
              color: fg,
              fontSize: 10,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            title.toUpperCase(),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: QuestTypography.osHeadlineLarge.copyWith(
              color: fg,
              fontSize: 19,
              height: 1.15,
              letterSpacing: -0.48,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            "The timer ran out. No XP awarded \u2014 roll again when you're "
            'ready.',
            style: QuestTypography.osBodySmall.copyWith(
              color: fg,
              fontSize: 13,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 10),
          // 44pt, r11, cream on coral — the frame's inset button, not a
          // full-width primary.
          GestureDetector(
            onTap: onGenerate,
            behavior: HitTestBehavior.opaque,
            child: Container(
              height: QuestSpacing.minTouchTarget,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: QuestColors.osBg,
                borderRadius: BorderRadius.circular(QuestSpacing.radiusButton),
                border: Border.all(color: ink, width: 2),
              ),
              child: Text(
                AppLocalizations.of(context)!.generateAQuest.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: QuestTypography.osButtonText.copyWith(
                  color: ink,
                  fontSize: 13,
                  letterSpacing: 0.65,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Hero skeleton ─────────────────────────────────────────────────────────

/// Hero-zone placeholder while the active-quest state resolves.
class _HeroSkeleton extends StatelessWidget {
  const _HeroSkeleton();

  @override
  Widget build(BuildContext context) => const ArcadeSkeleton(
        height: 232,
        radius: 18,
      );
}

/// Tile-shaped placeholder matching `ArcadeStatTile` proportions, shown
/// while the profile XP / quest counts are loading.
class _StatTileSkeleton extends StatelessWidget {
  const _StatTileSkeleton();

  @override
  Widget build(BuildContext context) => const ArcadeSkeleton(
        height: 92,
        radius: 14,
      );
}

/// Placeholder for the recent-quests rows. The heights match the real
/// rows so nothing shifts when the data lands.
class _RecentQuestsSkeleton extends StatelessWidget {
  const _RecentQuestsSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ArcadeSkeleton(width: 120, height: 11, radius: 4, bordered: false),
        SizedBox(height: 8),
        ArcadeSkeleton(height: 44, radius: 12),
        SizedBox(height: 8),
        ArcadeSkeleton(height: 44, radius: 12),
        SizedBox(height: 8),
        ArcadeSkeleton(height: 44, radius: 12),
      ],
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
    // Dashed cream, no shadow: there is nothing here to act on, and a
    // solid card with a shadow would keep implying there is.
    return ArcadeDashedBox(
      radius: 14,
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: QuestTypography.osLabelMedium.copyWith(
                color: QuestColors.osTextSecondary,
                fontSize: 10,
                letterSpacing: 1.1,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: QuestTypography.osBodyMedium.copyWith(
                color: QuestColors.osTextSecondary,
                fontSize: 14,
                height: 1.5,
              ),
            ),
          ],
        ),
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

/// Opens the PICK ONE sheet.
///
/// A bottom sheet over a 72% ink scrim, per `05-slot-machine.jpg`. It was
/// a centred dialog with a letter-spin "GENERATING" animation the frame
/// does not have; the frame shows the three options straight away, so the
/// spin is now a skeleton while the fetch is in flight.
Future<void> showRollPicker(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    // Above the shell, so the floating nav pill never covers the sheet.
    useRootNavigator: true,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: QuestColors.osBg,
    barrierColor: QuestColors.osTextPrimary.withAlpha(184), // 72%
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      side: BorderSide(color: QuestColors.osTextPrimary, width: 2),
    ),
    builder: (_) => const _RollPickerSheet(),
  );
}

class _RollPickerSheet extends ConsumerStatefulWidget {
  const _RollPickerSheet();

  @override
  ConsumerState<_RollPickerSheet> createState() => _RollPickerSheetState();
}

class _RollPickerSheetState extends ConsumerState<_RollPickerSheet> {
  /// The legacy casino spin: "GENERATING" cycles letter by letter and
  /// settles left to right over this long, whatever the fetch takes. The
  /// options appear only once both the spin and the fetch are done.
  static const _spinDuration = Duration(milliseconds: 2200);

  List<QuestModel>? _options;
  bool _spinDone = false;

  /// Which of the three is armed. The frame draws the first option on its
  /// own category ground with an ink shadow and the other two white with a
  /// category shadow — that difference *is* the selection, so it moves as
  /// the player taps.
  int _selected = 0;

  bool _assigning = false;
  bool _rerolling = false;
  String? _error;
  int _deckKey = 0; // animation key — bumps on each reroll

  @override
  void initState() {
    super.initState();
    _fetchQuests();
  }

  Future<void> _fetchQuests() async {
    try {
      // Server returns up to 3 options. If the user has a pending admin
      // injection, it is pinned at index 0 and consumed in the same call —
      // so it pops up only on this first generate, never resurfaces, and
      // never appears for any other user.
      final picks =
          await ref.read(questsRepositoryProvider).getQuestPickerOptions();
      if (!mounted) return;
      setState(() {
        _options = picks;
        _selected = 0;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'No quests available right now');
    }
  }

  Future<void> _reroll() async {
    if (_rerolling || _assigning) return;
    final budget = ref.read(rerollBudgetProvider).valueOrNull;
    if (budget != null && !budget.canReroll) {
      await _showRerollLimitDialog(budget);
      return;
    }

    setState(() {
      _rerolling = true;
      _error = null;
      // Spin again while the new deal is fetched.
      _spinDone = false;
      _deckKey++;
    });
    try {
      // The picker itself now spends the reroll, server-side, because gating
      // only the bookkeeping route left the cap bypassable by skipping it.
      // Recording one here as well would cost two per spin.
      final picks =
          await ref.read(questsRepositoryProvider).getQuestPickerOptions();
      ref.invalidate(rerollBudgetProvider);
      if (!mounted) return;
      setState(() {
        _options = picks;
        _selected = 0;
        _deckKey++;
        _rerolling = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _rerolling = false);
      // A spent budget is not an empty catalogue. This branch reported
      // "No quests available right now" for both, and left ACCEPT armed over
      // options that had been replaced by the error panel.
      if (e is ApiException && e.code == 'REROLL_LIMIT_REACHED') {
        final budget = ref.read(rerollBudgetProvider).valueOrNull;
        if (budget != null) await _showRerollLimitDialog(budget);
        return;
      }
      if (!mounted) return;
      setState(() => _error = mapDbError(e, action: 'reroll'));
    }
  }

  Future<void> _showRerollLimitDialog(RerollBudget budget) async {
    final refillIn = budget.refillIn;
    final waitText = refillIn == null
        ? 'Try again later.'
        : 'Next reroll unlocks in ${refillIn.inHours}h '
            '${refillIn.inMinutes.remainder(60)}m.';

    await showDialog<void>(
      context: context,
      barrierColor: QuestColors.osTextPrimary.withAlpha(184),
      builder: (dialogContext) => AlertDialog(
        backgroundColor: QuestColors.osCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: QuestColors.osTextPrimary, width: 2),
        ),
        title: Text(
          'REROLL LIMIT',
          style: QuestTypography.osHeadlineLarge.copyWith(letterSpacing: 0.4),
        ),
        content: Text(
          "You've used all ${RerollBudget.maxPerWindow} rerolls for this 24h "
          'window.\n\n$waitText',
          style: QuestTypography.osBodyMedium.copyWith(height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(
              'OK',
              style: QuestTypography.osLabelMedium.copyWith(
                color: QuestColors.osPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _accept() async {
    final options = _options;
    if (_assigning || options == null || options.isEmpty) return;
    final quest = options[_selected.clamp(0, options.length - 1)];
    setState(() => _assigning = true);
    try {
      final user = ref.read(authSessionProvider);
      if (user == null) throw StateError('Not logged in');
      await ref
          .read(questsRepositoryProvider)
          .assignSpecificQuest(user.id, quest.id);
      ref.invalidate(activeQuestProvider);
      ref.invalidate(questHistoryProvider);
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('NEW QUEST: ${quest.title.toUpperCase()}'),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString();
      setState(() {
        _assigning = false;
        _error = msg.contains('already has an active quest')
            ? 'You already have an active quest'
            : 'Could not assign quest';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final options = _options;
    final budget = ref.watch(rerollBudgetProvider).valueOrNull;
    final busy = _assigning || _rerolling;
    final ready = options != null && options.isNotEmpty && _spinDone;

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: QuestColors.osTextPrimary,
                  borderRadius: BorderRadius.circular(QuestSpacing.radiusPip),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'PICK ONE',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: QuestTypography.osDisplayMedium.copyWith(
                      fontSize: 30,
                      height: 1,
                      letterSpacing: -1.05,
                    ),
                  ),
                ),
                if (budget != null) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(
                      color: QuestColors.osAccent,
                      borderRadius:
                          BorderRadius.circular(QuestSpacing.radiusMeterTrack),
                      border: Border.all(
                        color: QuestColors.osTextPrimary,
                        width: 2,
                      ),
                    ),
                    child: Text(
                      '${budget.remaining} REROLLS',
                      maxLines: 1,
                      style: QuestTypography.osLabelMedium.copyWith(
                        color: QuestColors.onAccent(QuestColors.osAccent),
                        fontSize: 10,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Choosing locks the other two. The timer starts the moment you '
              'accept.',
              style: QuestTypography.osBodySmall.copyWith(
                color: QuestColors.osTextSecondary,
                fontSize: 13,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 12),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: QuestTypography.osBodyMedium.copyWith(
                    // Coral as small type on cream fails; the text twin
                    // is what passes.
                    color: QuestColors.osRedText,
                  ),
                ),
              )
            else if (options == null || !_spinDone)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 44),
                child: _GeneratingText(
                  // A fresh key per deal restarts the spin on every reroll.
                  key: ValueKey('spin-$_deckKey'),
                  duration: _spinDuration,
                  onDone: () {
                    if (mounted) setState(() => _spinDone = true);
                  },
                ),
              )
            else if (options.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Text(
                  'No quests available right now.',
                  textAlign: TextAlign.center,
                  style: QuestTypography.osBodyMedium.copyWith(
                    color: QuestColors.osTextSecondary,
                  ),
                ),
              )
            else
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 260),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                transitionBuilder: (child, anim) => SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0.12, 0),
                    end: Offset.zero,
                  ).animate(anim),
                  child: FadeTransition(opacity: anim, child: child),
                ),
                child: Column(
                  key: ValueKey(_deckKey),
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < options.length; i++) ...[
                      if (i > 0) const SizedBox(height: 12),
                      _QuestChoiceCard(
                        quest: options[i],
                        selected: i == _selected,
                        disabled: busy,
                        onSelect: () => setState(() => _selected = i),
                        onPreview: () => _showQuestPreview(
                          context,
                          quest: options[i],
                          onPick: () {
                            setState(() => _selected = i);
                            _accept();
                          },
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            const SizedBox(height: 14),
            Row(
              children: [
                _SheetButton(
                  label: 'REROLL',
                  fill: QuestColors.osSurface,
                  fontSize: 14,
                  onTap: busy ? null : _reroll,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: _SheetButton(
                    label: 'ACCEPT',
                    fill: QuestColors.osSuccess,
                    fontSize: 16,
                    expand: true,
                    onTap: (busy || !ready) ? null : _accept,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The legacy casino-style letter-spin reveal. Each column cycles through
/// random glyphs at ~14 fps and settles on its target letter in staggered
/// left-to-right order over [duration]. When the last letter lands, [onDone]
/// is invoked.
class _GeneratingText extends StatefulWidget {
  const _GeneratingText({
    super.key,
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
  final _rand = math.Random();
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

  double _settledAt(int i) => 0.25 + (i / widget.text.length) * 0.72;

  String _charAt(int i) {
    if (_ac.value >= _settledAt(i)) return widget.text[i];
    // Cycle through uppercase letters pseudo-randomly per tick.
    final code = 65 + ((_rand.nextInt(26) + _tickCount + i) % 26);
    return String.fromCharCode(code);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ac,
      builder: (_, __) {
        return FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(widget.text.length, (i) {
              final settled = _ac.value >= _settledAt(i);
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 2),
                width: 26,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: settled ? QuestColors.osAccent : QuestColors.osSurface,
                  borderRadius: BorderRadius.circular(QuestSpacing.radiusBadge),
                  border: Border.all(
                    color: settled
                        ? QuestColors.osTextPrimary
                        : QuestColors.osTextMuted,
                    width: 1.5,
                  ),
                ),
                child: Text(
                  _charAt(i),
                  style: QuestTypography.osHeadlineMedium.copyWith(
                    color: settled
                        ? QuestColors.onAccent(QuestColors.osAccent)
                        : QuestColors.osTextSecondary,
                    fontSize: 17,
                    height: 1,
                  ),
                ),
              );
            }),
          ),
        );
      },
    );
  }
}

/// The sheet's own 54pt button: `r13`, 2px ink, 4px ink shadow. Sized to
/// the frame rather than to `ArcadeButton`'s 56pt, because these two sit
/// in a row whose height the frame fixes.
class _SheetButton extends StatelessWidget {
  const _SheetButton({
    required this.label,
    required this.fill,
    required this.fontSize,
    required this.onTap,
    this.expand = false,
  });

  final String label;
  final Color fill;
  final double fontSize;
  final VoidCallback? onTap;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final ink = QuestColors.text(context);
    final enabled = onTap != null;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Opacity(
        opacity: enabled ? 1 : 0.5,
        child: Container(
          height: 54,
          width: expand ? double.infinity : null,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(QuestSpacing.radiusPanel),
            border: Border.all(color: ink, width: 2),
            boxShadow: enabled ? QuestSpacing.shadowMd : const [],
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: QuestTypography.osButtonText.copyWith(
              // The fill decides the foreground. Jade and cream both take
              // ink; neither takes white.
              color: QuestColors.onAccent(fill),
              fontSize: fontSize,
              letterSpacing: fontSize * 0.05,
            ),
          ),
        ),
      ),
    );
  }
}

/// One of the three options.
///
/// Selected: its own category colour as the ground with an ink shadow.
/// Unselected: white with a 3px… no — 5px shadow in the category colour.
/// The frame uses that inversion as the selection state, so the armed
/// card is legible without a tick or a ring.
class _QuestChoiceCard extends StatelessWidget {
  const _QuestChoiceCard({
    required this.quest,
    required this.selected,
    required this.disabled,
    required this.onSelect,
    required this.onPreview,
  });

  final QuestModel quest;
  final bool selected;
  final bool disabled;
  final VoidCallback onSelect;
  final VoidCallback onPreview;

  @override
  Widget build(BuildContext context) {
    final ink = QuestColors.text(context);
    final tint = QuestColors.category(quest.category);
    final ground = selected ? tint : QuestColors.osCard;
    final fg = QuestColors.onAccent(ground);
    final metaColor = selected ? fg : QuestColors.osTextSecondary;

    return Semantics(
      selected: selected,
      button: true,
      child: GestureDetector(
        onTap: disabled ? null : onSelect,
        onLongPress: disabled ? null : onPreview,
        behavior: HitTestBehavior.opaque,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 150),
          opacity: disabled ? 0.55 : 1,
          child: Container(
            constraints: const BoxConstraints(
              minHeight: QuestSpacing.minTouchTarget,
            ),
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: ground,
              borderRadius: BorderRadius.circular(QuestSpacing.radiusOption),
              border: Border.all(color: ink, width: 2),
              boxShadow: QuestSpacing.hardShadow(
                5,
                color: selected ? ink : tint,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // On the selected card the tag sits on its own colour,
                    // so its ground flips to cream to stay legible.
                    Flexible(
                      child: _ChoiceTag(
                        label: quest.category,
                        fill: selected ? QuestColors.osBg : tint,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        _meta(quest),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.right,
                        style: QuestTypography.osLabelMedium.copyWith(
                          color: metaColor,
                          fontSize: 10,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 9),
                Text(
                  quest.title.toUpperCase(),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: QuestTypography.osHeadlineLarge.copyWith(
                    color: fg,
                    fontSize: 19,
                    height: 1.15,
                    letterSpacing: -0.48,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// `3H · 120 XP · MED` — the frame's single meta line.
  static String _meta(QuestModel quest) {
    final hours = quest.durationHours;
    final duration = hours <= 0
        ? 'NO LIMIT'
        : hours < 24
            ? '${hours}H'
            : '${hours ~/ 24}D';
    final difficulty = switch (quest.difficulty.toLowerCase()) {
      'easy' => 'EASY',
      'hard' => 'HARD',
      _ => 'MED',
    };
    return '$duration · ${quest.xpReward} XP · $difficulty';
  }
}

class _ChoiceTag extends StatelessWidget {
  const _ChoiceTag({required this.label, required this.fill});
  final String label;
  final Color fill;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(QuestSpacing.radiusBadge),
        border: Border.all(color: QuestColors.osTextPrimary, width: 2),
      ),
      child: Text(
        label.toUpperCase(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: QuestTypography.osLabelSmall.copyWith(
          color: QuestColors.onAccent(fill),
          fontSize: 9,
          letterSpacing: 1,
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
                      borderRadius:
                          BorderRadius.circular(QuestSpacing.radiusButton),
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
                  ArcadeIconTile(
                    icon: Icons.close_rounded,
                    semanticLabel: 'Close',
                    onTap: () => Navigator.of(context).pop(),
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
                borderRadius: BorderRadius.circular(QuestSpacing.radiusGlyph),
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
    final sorted = [...quests]..sort((a, b) {
        final at = a.completedAt ?? a.assignedAt;
        final bt = b.completedAt ?? b.assignedAt;
        return bt.compareTo(at);
      });
    final latest = sorted.take(5).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // A bare label row on the page, not a wrapping white card: the
        // frame puts the rows straight on the cream, and a card around
        // them double-outlined every row.
        Row(
          children: [
            Expanded(
              child: Text(
                'RECENT QUESTS',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: QuestTypography.osLabelMedium.copyWith(
                  color: QuestColors.osTextSecondary,
                  fontSize: 11,
                  letterSpacing: 1.32,
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: onSeeMore,
              behavior: HitTestBehavior.opaque,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minHeight: QuestSpacing.minTouchTarget,
                  minWidth: QuestSpacing.minTouchTarget,
                ),
                child: Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: Text(
                    'SEE MORE',
                    maxLines: 1,
                    style: QuestTypography.osLabelMedium.copyWith(
                      color: QuestColors.osPrimary,
                      fontSize: 11,
                      letterSpacing: 1.1,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        for (var i = 0; i < latest.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          _RecentQuestRow(q: latest[i]),
        ],
      ],
    );
  }
}

class _RecentQuestRow extends StatelessWidget {
  const _RecentQuestRow({required this.q});
  final UserQuestModel q;

  (String, Color) _statusStyle() {
    switch (q.status) {
      case UserQuestStatus.approved:
        return ('DONE', QuestColors.osSuccess);
      case UserQuestStatus.rejected:
        return ('REJECTED', QuestColors.osRed);
      case UserQuestStatus.expired:
        return ('EXPIRED', QuestColors.osTextMuted);
      case UserQuestStatus.submitted:
        return ('IN REVIEW', QuestColors.osAccent);
      case UserQuestStatus.assigned:
        return ('ACTIVE', QuestColors.osPrimary);
      default:
        return (q.status.toUpperCase(), QuestColors.osTextMuted);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ink = QuestColors.text(context);
    final (statusText, statusColor) = _statusStyle();
    return Container(
      constraints: const BoxConstraints(
        minHeight: QuestSpacing.minTouchTarget,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      decoration: BoxDecoration(
        // The frame draws these as white cards with a full 2px outline,
        // not warm surface behind a hairline.
        color: QuestColors.osCard,
        borderRadius: BorderRadius.circular(12),
        // The shadow carries the status. Reading a row's outcome from the
        // colour under it is faster than reading the label, which is the
        // whole reason the design tints it rather than using ink here.
        boxShadow: QuestSpacing.hardShadow(3, color: statusColor),
        border: Border.all(color: ink, width: 2),
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
              borderRadius: BorderRadius.circular(QuestSpacing.radiusDot),
              border: Border.all(color: ink, width: 2),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              q.quest?.title ?? 'Quest',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: QuestTypography.osBodyMedium.copyWith(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                fontVariations: const [FontVariation('wght', 600)],
                height: 1.2,
              ),
            ),
          ),
          const SizedBox(width: 10),
          // Plain mono type in the frame, not a filled pill: the dot and
          // the shadow already carry the colour, and a third coloured
          // element on a 44pt row is noise.
          Text(
            statusText,
            maxLines: 1,
            style: QuestTypography.osLabelSmall.copyWith(
              color: QuestColors.osTextSecondary,
              fontSize: 9,
              letterSpacing: 0.72,
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
  required VoidCallback onPick,
}) {
  return showModalBottomSheet<void>(
    context: context,
    // Above the shell, so the floating nav pill never covers the sheet.
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: QuestColors.osTextPrimary.withAlpha(184),
    useSafeArea: true,
    builder: (sheetContext) => _QuestPreviewSheet(
      quest: quest,
      tint: QuestColors.category(quest.category),
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
        return (QuestColors.osSuccess, 'EASY');
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
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(QuestSpacing.radiusSheet)),
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
                    borderRadius: BorderRadius.circular(QuestSpacing.radiusPip),
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
                                  border: Border.all(color: onTint, width: 2),
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
