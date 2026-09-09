import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:app_core/app_core.dart';
import 'package:app_contracts/app_contracts.dart';
import 'package:shared_ui/shared_ui.dart';
import '../../../../core/providers/auth_session_provider.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/router/safe_back.dart';
import '../../../../core/utils/account_lock_guard.dart';
import '../../data/quest_providers.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../reactions/presentation/widgets/bsheeel_dialog.dart';
import '../widgets/arcade_page_chrome.dart';

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
                        if (quest.category.trim().isNotEmpty) ...[
                          Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: ArcadeCategoryTag(
                              label: quest.category,
                              tint: QuestColors.category(quest.category),
                            ),
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
                        IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(
                                child: _StatChip(
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
                                child: _StatChip(
                                  label: l.reward,
                                  value: '${quest.xpReward} XP',
                                  tint: QuestColors.osPrimary,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _StatChip(
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
                        _BlockLabel(l.missionBriefing),
                        const SizedBox(height: 7),
                        Text(
                          quest.description,
                          style: QuestTypography.osBodyLarge.copyWith(
                            fontSize: 15,
                            height: 1.6,
                          ),
                        ),
                        const SizedBox(height: 14),

                        // ── Acceptance criteria ────────────────────
                        _BlockLabel(l.acceptanceCriteria),
                        const SizedBox(height: 8),
                        _CheckRow(text: l.criteriaProof, met: true),
                        const SizedBox(height: 8),
                        _CheckRow(text: l.criteriaQuality, met: true),
                        const SizedBox(height: 8),
                        _CheckRow(text: l.criteriaCaption, met: true),
                        const SizedBox(height: 14),

                        // ── Submission requirements ────────────────
                        _BlockLabel(l.submissionRequirements),
                        const SizedBox(height: 8),
                        _CheckRow(text: l.reqCaptureProof, met: isSubmitted),
                        const SizedBox(height: 8),
                        _CheckRow(text: l.reqUploadProof, met: isSubmitted),
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
class _BlockLabel extends StatelessWidget {
  const _BlockLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: QuestTypography.osLabelMedium.copyWith(
        color: QuestColors.osTextSecondary,
        fontSize: 11,
        letterSpacing: 1.32,
      ),
    );
  }
}

// ── Stat chip ──────────────────────────────────────────────────────────────

/// `r12`, 2px ink, 3px ink shadow, 10/11 padding. Label mono 8, value
/// Syne 700 15 — or mono 14 for the countdown, which must not reflow.
class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.label,
    required this.value,
    required this.tint,
    this.mono = false,
  });

  final String label;
  final String value;
  final Color tint;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    final ink = QuestColors.text(context);
    // Derived from the fill: violet takes white, gold takes osAccentInk,
    // everything else ink. Never alpha-muted on an accent ground.
    final fg = QuestColors.onAccent(tint);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
      decoration: BoxDecoration(
        color: tint,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ink, width: 2),
        boxShadow: QuestSpacing.shadowSm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: QuestTypography.osLabelSmall.copyWith(
              color: fg,
              fontSize: 8,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 1),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              value,
              maxLines: 1,
              style: mono
                  ? QuestTypography.osLabelMedium.copyWith(
                      color: fg,
                      fontSize: 14,
                      letterSpacing: 0,
                      height: 1.2,
                    )
                  : QuestTypography.osHeadlineMedium.copyWith(
                      color: fg,
                      fontSize: 15,
                      height: 1.2,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Criteria / requirement row ─────────────────────────────────────────────

/// An 18pt square with a 5px radius and a 2px ink outline, jade when the
/// item is satisfied and warm cream when it is not, then the sentence in
/// normal case. The frame draws no card around these.
class _CheckRow extends StatelessWidget {
  const _CheckRow({required this.text, required this.met});
  final String text;
  final bool met;

  @override
  Widget build(BuildContext context) {
    final ink = QuestColors.text(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color: met ? QuestColors.osSuccess : QuestColors.osSurface,
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: ink, width: 2),
            ),
          ),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            text,
            style: QuestTypography.osBodyMedium.copyWith(
              color:
                  met ? QuestColors.osTextPrimary : QuestColors.osTextSecondary,
              fontSize: 14,
              height: 1.5,
            ),
          ),
        ),
      ],
    );
  }
}

// ── Loading skeleton ───────────────────────────────────────────────────────

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
