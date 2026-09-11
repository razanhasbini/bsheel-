import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:app_core/app_core.dart';
import 'package:app_contracts/app_contracts.dart';
import 'package:app_models/app_models.dart';
import 'package:shared_ui/shared_ui.dart';
import '../../../../core/providers/auth_session_provider.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/router/safe_back.dart';
import '../../../../core/utils/account_lock_guard.dart';
import '../../data/quest_providers.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../reactions/presentation/widgets/bsheeel_dialog.dart';
import '../widgets/arcade_page_chrome.dart';
import '../widgets/journey_timeline.dart';
import '../widgets/detail_primitives.dart';

/// Quest details, drawn to `export/mobile/06-quest-detail.jpg`.
///
/// The frame is deliberately flat: a category tag, a very large Syne title,
/// three stat chips (white / violet / gold), then two label-and-list blocks
/// on the bare cream page. There is no gradient hero, no per-section card
/// and no rewards panel — the earlier build had all three, and they buried
/// the one thing the screen is for, which is reading the brief before you
/// commit to the timer.
class QuestDetailsPage extends ConsumerStatefulWidget {
  const QuestDetailsPage({super.key, required this.questId});
  final String questId;

  @override
  ConsumerState<QuestDetailsPage> createState() => _QuestDetailsPageState();
}

class _QuestDetailsPageState extends ConsumerState<QuestDetailsPage> {
  // Ticks the build every second so the gold TIME LEFT chip counts down
  // rather than freezing at whatever it read when the page opened.
  Timer? _tick;

  // Guards onTake against double-tap stacking two assign-quest dialogs.
  bool _taking = false;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final questAsync = ref.watch(questDetailsProvider(widget.questId));
    final activeQuestAsync = ref.watch(activeQuestProvider);
    final l = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: QuestColors.bg(context),
      body: SafeArea(
        bottom: false,
        child: questAsync.when(
          loading: () => Column(
            children: [
              ArcadePageHeader(title: l.questDetails, onBack: null),
              const Expanded(child: _DetailsSkeleton()),
            ],
          ),
          error: (e, _) => Column(
            children: [
              ArcadePageHeader(
                title: l.questDetails,
                onBack: () => safeBack(context),
              ),
              Expanded(
                child: Center(
                  child: ArcadeInlineError(
                    title: 'QUEST UNAVAILABLE',
                    subtitle: 'We could not load this quest. Try again.',
                    onRetry: () =>
                        ref.invalidate(questDetailsProvider(widget.questId)),
                  ),
                ),
              ),
            ],
          ),
          data: (quest) {
            final activeQuest = activeQuestAsync.valueOrNull;
            final isActiveQuest = activeQuest?.questId == widget.questId;
            final activeQuestId = activeQuest?.id;
            final isSubmitted = isActiveQuest &&
                activeQuest?.status == UserQuestStatus.submitted;
            final expiresAt = isActiveQuest ? activeQuest?.expiresAt : null;

            return Column(
              children: [
                ArcadePageHeader(
                  title: l.questDetails,
                  onBack: () => safeBack(context),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(
                      QuestSpacing.screenPadding,
                      0,
                      QuestSpacing.screenPadding,
                      24,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ── Category tag + title ───────────────────
                        if (quest.category.trim().isNotEmpty ||
                            quest.sponsorName != null) ...[
                          Row(
                            children: [
                              if (quest.category.trim().isNotEmpty)
                                ArcadeCategoryTag(
                                  label: quest.category,
                                  tint: QuestColors.category(quest.category),
                                ),
                              // Sponsored quests (#51) must say who they are
                              // from. Attribution only — partner accounts are
                              // #14 — so this is a credit line, not a link.
                              if (quest.sponsorName != null) ...[
                                if (quest.category.trim().isNotEmpty)
                                  const SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    'WITH ${quest.sponsorName!.toUpperCase()}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style:
                                        QuestTypography.osLabelSmall.copyWith(
                                      color: QuestColors.osTextSecondary,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 11),
                        ],
                        Text(
                          quest.title.toUpperCase(),
                          style: QuestTypography.osDisplayMedium.copyWith(
                            fontSize: 30,
                            height: 1.05,
                            letterSpacing: -1.05,
                          ),
                        ),
                        const SizedBox(height: 14),

                        // ── Three stat chips: white / violet / gold ─
                        //
                        // IntrinsicHeight, because `stretch` on a Row whose
                        // height is unbounded (this is inside a scroll view)
                        // throws — and it threw on every frame, leaving the
                        // whole page blank.
                        // Event / time-limited quests (#51). The server
                        // refuses to assign one outside its window, so the
                        // deadline has to be visible before someone commits
                        // — otherwise the only feedback is a failed accept.
                        if (quest.isTimeLimited) ...[
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 13,
                              vertical: 11,
                            ),
                            decoration: BoxDecoration(
                              color: quest.isWindowClosed
                                  ? QuestColors.osSurface
                                  : QuestColors.osAccent,
                              borderRadius: BorderRadius.circular(
                                QuestSpacing.radiusControl,
                              ),
                              border: Border.all(
                                color: QuestColors.osTextPrimary,
                                width: QuestSpacing.cardBorderWidth,
                              ),
                              boxShadow: QuestSpacing.shadowSm,
                            ),
                            child: Text(
                              quest.isWindowClosed
                                  ? 'This event has ended.'
                                  : _eventWindowLabel(quest),
                              style: QuestTypography.osBodySmall.copyWith(
                                // Ink on gold, never white — see the
                                // contrast rule in QuestColors.onAccent.
                                color: quest.isWindowClosed
                                    ? QuestColors.osTextSecondary
                                    : QuestColors.onAccent(
                                        QuestColors.osAccent,
                                      ),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                        IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(
                                child: StatChip(
                                  label: l.difficulty,
                                  value: quest.difficulty.toUpperCase(),
                                  // White in the render: the three chips run
                                  // white / violet / gold left to right, so
                                  // difficulty is the quiet one.
                                  tint: QuestColors.osCard,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: StatChip(
                                  label: l.reward,
                                  value: '${quest.xpReward} XP',
                                  tint: QuestColors.osPrimary,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: StatChip(
                                  label: l.timeLeft,
                                  value:
                                      _timeRemaining(expiresAt, isActiveQuest),
                                  // Gold while a quest is live — the design
                                  // uses gold for "waiting on you". Coral is
                                  // the under-five-minutes state and belongs
                                  // to ArcadeTimer, not to a chip's ground.
                                  tint: isActiveQuest
                                      ? QuestColors.osAccent
                                      : QuestColors.osSurface,
                                  mono: true,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),

                        // ── Mission briefing ───────────────────────
                        BlockLabel(l.missionBriefing),
                        const SizedBox(height: 7),
                        Text(
                          quest.description,
                          style: QuestTypography.osBodyLarge.copyWith(
                            fontSize: 15,
                            height: 1.6,
                          ),
                        ),
                        const SizedBox(height: 14),

                        // ── The route, when this quest is part of one ──
                        // Renders nothing for an ordinary quest, so it costs
                        // a network call and no layout on the common case.
                        JourneyTimeline(questId: quest.id),

                        // ── Acceptance criteria ────────────────────
                        BlockLabel(l.acceptanceCriteria),
                        const SizedBox(height: 8),
                        CheckRow(text: l.criteriaProof, met: true),
                        const SizedBox(height: 8),
                        CheckRow(text: l.criteriaQuality, met: true),
                        const SizedBox(height: 8),
                        CheckRow(text: l.criteriaCaption, met: true),
                        const SizedBox(height: 14),

                        // ── Submission requirements ────────────────
                        BlockLabel(l.submissionRequirements),
                        const SizedBox(height: 8),
                        CheckRow(text: l.reqCaptureProof, met: isSubmitted),
                        const SizedBox(height: 8),
                        CheckRow(text: l.reqUploadProof, met: isSubmitted),
                      ],
                    ),
                  ),
                ),

                // ── Sticky CTA on the warm footer ─────────────────
                ArcadeStickyFooter(
                  child: _cta(context, isSubmitted, isActiveQuest,
                      activeQuestId, quest.title),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _cta(
    BuildContext context,
    bool isSubmitted,
    bool isActiveQuest,
    String? activeQuestId,
    String questTitle,
  ) {
    if (isSubmitted) {
      // Disabled ArcadeButton: dashed outline, no shadow. Reads as
      // unavailable rather than merely dim.
      return const ArcadeButton(
        label: 'AWAITING REVIEW',
        variant: ArcadeButtonVariant.secondary,
        onTap: null,
      );
    }
    if (isActiveQuest && activeQuestId != null) {
      return ArcadeButton(
        label: 'SUBMIT PROOF',
        variant: ArcadeButtonVariant.destructive,
        onTap: () => context.pushNamed(
          RouteNames.submitProof,
          pathParameters: {'userQuestId': activeQuestId},
        ),
      );
    }
    return ArcadeButton(
      label: 'TAKE QUEST',
      variant: ArcadeButtonVariant.positive,
      onTap: () => _take(questTitle),
    );
  }

  Future<void> _take(String questTitle) async {
    if (_taking) return;
    if (guardAccountAction(context, ref)) return;
    final user = ref.read(authSessionProvider);
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sign in to take a quest')),
      );
      return;
    }
    setState(() => _taking = true);
    try {
      await assignQuestFlow(
        context: context,
        ref: ref,
        questId: widget.questId,
        questTitle: questTitle,
        userId: user.id,
      );
    } finally {
      if (mounted) setState(() => _taking = false);
    }
  }

  /// `H:MM:SS`, zero-padded on the minutes and seconds so the chip's width
  /// never changes as it ticks.
  static String _timeRemaining(DateTime? expiresAt, bool isActive) {
    if (!isActive) return '—';
    if (expiresAt == null) return 'NO TIMER';
    final diff = expiresAt.difference(DateTime.now());
    if (diff.isNegative) return '0:00:00';
    final m = (diff.inMinutes % 60).toString().padLeft(2, '0');
    final s = (diff.inSeconds % 60).toString().padLeft(2, '0');
    return '${diff.inHours}:$m:$s';
  }
}

// ── Block label ────────────────────────────────────────────────────────────

/// Mono 11 / wide tracking / soft ink. The frame uses exactly one label
/// treatment for every block on the page.
class _DetailsSkeleton extends StatelessWidget {
  const _DetailsSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: QuestSpacing.screenPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ArcadeSkeleton(width: 88, height: 24, radius: 8),
          SizedBox(height: 11),
          ArcadeSkeleton(height: 32, radius: 6, bordered: false),
          SizedBox(height: 8),
          ArcadeSkeleton(height: 32, radius: 6, bordered: false),
          SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: ArcadeSkeleton(height: 56, radius: 12)),
              SizedBox(width: 8),
              Expanded(child: ArcadeSkeleton(height: 56, radius: 12)),
              SizedBox(width: 8),
              Expanded(child: ArcadeSkeleton(height: 56, radius: 12)),
            ],
          ),
          SizedBox(height: 20),
          ArcadeSkeleton(width: 140, height: 12, radius: 4, bordered: false),
          SizedBox(height: 10),
          ArcadeSkeleton(height: 14, radius: 4, bordered: false),
          SizedBox(height: 8),
          ArcadeSkeleton(height: 14, radius: 4, bordered: false),
          SizedBox(height: 8),
          ArcadeSkeleton(height: 14, radius: 4, bordered: false),
        ],
      ),
    );
  }
}

/// Human deadline for an event quest. Prefers the closing date, since that
/// is the actionable half; falls back to the opening date for one that has
/// not started.
String _eventWindowLabel(QuestModel quest) {
  final until = quest.availableUntil;
  if (until != null) {
    final left = until.difference(DateTime.now());
    if (left.inDays >= 1) return 'Available for ${left.inDays} more day(s).';
    if (left.inHours >= 1) return 'Available for ${left.inHours} more hour(s).';
    return 'Closing within the hour.';
  }
  final from = quest.availableFrom;
  if (from != null && from.isAfter(DateTime.now())) {
    return 'Opens ${from.toLocal().toString().split(' ').first}.';
  }
  return 'Limited-time quest.';
}
