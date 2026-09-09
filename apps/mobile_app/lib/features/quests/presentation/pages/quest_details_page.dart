import '../../../../design/bs_widgets.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:app_core/app_core.dart';
import 'package:app_contracts/app_contracts.dart';
import '../../../../core/providers/auth_session_provider.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/router/safe_back.dart';
import '../../../../core/utils/account_lock_guard.dart';
import '../../data/quest_providers.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../reactions/presentation/widgets/bsheeel_dialog.dart';

/// Arcade Pop quest details. Logic unchanged: reads quest + active quest,
/// detects if this is the active quest, shows submit CTA. Visuals fully
/// refreshed with chunky ink-bordered cards, gradient hero, pulsing submit.
class QuestDetailsPage extends ConsumerStatefulWidget {
  const QuestDetailsPage({super.key, required this.questId});
  final String questId;

  @override
  ConsumerState<QuestDetailsPage> createState() => _QuestDetailsPageState();
}

class _QuestDetailsPageState extends ConsumerState<QuestDetailsPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat(reverse: true);

  // Ticks the build every 30s so the "Xh Ym" badge in the hero card
  // (computed via _timeRemaining at build) doesn't stay frozen at the
  // value it had when the page opened.
  Timer? _tick;

  // Guards onTake against double-tap stacking two assign-quest dialogs.
  bool _taking = false;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _pulse.dispose();
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final questAsync = ref.watch(questDetailsProvider(widget.questId));
    final activeQuestAsync = ref.watch(activeQuestProvider);
    final l = AppLocalizations.of(context)!;
    final ink = QuestColors.text(context);

    return Scaffold(
      backgroundColor: QuestColors.bg(context),
      body: SafeArea(
        child: questAsync.when(
          loading: () => const Center(
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          error: (e, _) => Center(
            child: Text(
              'Failed to load quest: $e',
              style: QuestTypography.bodyMedium
                  .copyWith(color: QuestColors.softRed),
            ),
          ),
          data: (quest) {
            final activeQuest = activeQuestAsync.valueOrNull;
            final isActiveQuest = activeQuest?.questId == widget.questId;
            final activeQuestId = activeQuest?.id;
            final isSubmitted = isActiveQuest &&
                activeQuest?.status == UserQuestStatus.submitted;
            final statusStr = isActiveQuest
                ? (activeQuest?.status ?? UserQuestStatus.assigned)
                : 'available';
            final timeLeft = isActiveQuest
                ? _timeRemaining(activeQuest?.expiresAt)
                : 'Not assigned';

            return Column(
              children: [
                _TopBar(ink: ink),
                Expanded(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.symmetric(
                        horizontal: QuestSpacing.screenPadding),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 8),
                        // ── Hero gradient card ─────────────────────
                        _HeroCard(
                          title: quest.title,
                          category: quest.category,
                          status: statusStr,
                          isActive: isActiveQuest,
                        ),
                        const SizedBox(height: 16),

                        // ── Stat row ────────────────────────────────
                        Row(
                          children: [
                            Expanded(
                              child: _StatTile(
                                icon: Icons.whatshot_rounded,
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
                              child: _StatTile(
                                icon: Icons.bolt_rounded,
                                label: l.reward,
                                value: '+${quest.xpReward} XP',
                                tint: QuestColors.osPrimary,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _StatTile(
                                icon: Icons.timer_rounded,
                                label: l.timeLeft,
                                value: timeLeft,
                                // Gold while a quest is live - the design
                                // uses gold for "waiting on you". Coral is
                                // the under-five-minutes state and belongs to
                                // ArcadeTimer, not to the chip's ground.
                                tint: isActiveQuest
                                    ? QuestColors.osAccent
                                    : QuestColors.osTextMuted,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 22),

                        // ── Mission briefing ───────────────────────
                        _SectionHeader(
                            icon: Icons.description_rounded,
                            label: l.missionBriefing),
                        const SizedBox(height: 10),
                        _BriefingCard(description: quest.description),
                        const SizedBox(height: 22),

                        // ── Acceptance criteria ────────────────────
                        _SectionHeader(
                            icon: Icons.verified_rounded,
                            label: l.acceptanceCriteria),
                        const SizedBox(height: 10),
                        _CriteriaItem(text: l.criteriaProof),
                        const SizedBox(height: 8),
                        _CriteriaItem(text: l.criteriaQuality),
                        const SizedBox(height: 8),
                        _CriteriaItem(text: l.criteriaCaption),
                        const SizedBox(height: 22),

                        // ── Submission requirements ────────────────
                        _SectionHeader(
                            icon: Icons.upload_file_rounded,
                            label: l.submissionRequirements),
                        const SizedBox(height: 10),
                        _RequirementItem(
                          index: 1,
                          text: l.reqGenerateFirst,
                          isComplete: isActiveQuest,
                        ),
                        const SizedBox(height: 8),
                        _RequirementItem(
                          index: 2,
                          text: l.reqCaptureProof,
                          isComplete: isSubmitted,
                        ),
                        const SizedBox(height: 8),
                        _RequirementItem(
                          index: 3,
                          text: l.reqUploadProof,
                          isComplete: isSubmitted,
                        ),
                        const SizedBox(height: 22),

                        // ── Rewards ─────────────────────────────────
                        _SectionHeader(
                            icon: Icons.stars_rounded, label: l.rewardsLabel),
                        const SizedBox(height: 10),
                        _RewardsCard(
                          xpReward: quest.xpReward,
                          difficulty: quest.difficulty,
                        ),
                        const SizedBox(height: 32),
                      ],
                    ),
                  ),
                ),

                // ── Sticky CTA ─────────────────────────────────────
                _BottomActionBar(
                  isActiveQuest: isActiveQuest,
                  isSubmitted: isSubmitted,
                  activeQuestId: activeQuestId,
                  pulse: _pulse,
                  onTake: () async {
                    if (_taking) return;
                    if (guardAccountAction(context, ref)) return;
                    final user = ref.read(authSessionProvider);
                    if (user == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('Sign in to take a quest')),
                      );
                      return;
                    }
                    setState(() => _taking = true);
                    try {
                      await assignQuestFlow(
                        context: context,
                        ref: ref,
                        questId: widget.questId,
                        questTitle: quest.title,
                        userId: user.id,
                      );
                    } finally {
                      if (mounted) setState(() => _taking = false);
                    }
                  },
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  static String _timeRemaining(DateTime? expiresAt) {
    if (expiresAt == null) return 'No timer';
    final diff = expiresAt.difference(DateTime.now());
    if (diff.isNegative) return 'Expired';
    if (diff.inHours > 0) {
      final minutes = diff.inMinutes.remainder(60);
      return '${diff.inHours}h ${minutes}m';
    }
    return '${diff.inMinutes}m';
  }
}

// ── Top bar ────────────────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  const _TopBar({required this.ink});
  final Color ink;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          QuestSpacing.screenPadding, 14, QuestSpacing.screenPadding, 4),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => safeBack(context),
            behavior: HitTestBehavior.opaque,
            child: BsMinTouch(
              child: Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: QuestColors.cardBg(context),
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
                child: Icon(Icons.arrow_back_rounded, color: ink, size: 20),
              ),
            ),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: QuestColors.cardBg(context),
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: ink, width: 1.8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.auto_stories_rounded, color: ink, size: 14),
                const SizedBox(width: 6),
                Text(
                  'QUEST LOG',
                  style: QuestTypography.labelSmall.copyWith(
                    color: ink,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          const SizedBox(width: 42),
        ],
      ),
    );
  }
}

// ── Hero card ──────────────────────────────────────────────────────────────

class _HeroCard extends StatelessWidget {
  const _HeroCard({
    required this.title,
    required this.category,
    required this.status,
    required this.isActive,
  });

  final String title;
  final String category;
  final String status;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final ink = QuestColors.text(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: ink, width: 2),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isActive
              ? [QuestColors.softRed, QuestColors.osPrimary]
              : [QuestColors.osPrimary, QuestColors.softRed.withAlpha(204)],
        ),
        boxShadow: [
          BoxShadow(
            color: ink,
            offset: const Offset(4, 4),
            blurRadius: 0,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: QuestColors.osCard,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: ink, width: 1.5),
                ),
                child: Text(
                  status.toUpperCase(),
                  style: QuestTypography.labelSmall.copyWith(
                    color: ink,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: QuestColors.pureBlack.withAlpha(64),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: QuestColors.osTextOnPrimary, width: 1.5),
                  ),
                  child: Text(
                    category.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: QuestTypography.labelSmall.copyWith(
                      color: QuestColors.osTextOnPrimary,
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            title,
            style: QuestTypography.headlineLarge.copyWith(
              color: QuestColors.osTextOnPrimary,
              fontSize: 24,
              fontWeight: FontWeight.w800,
              height: 1.2,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Stat tile ──────────────────────────────────────────────────────────────

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.tint,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    final ink = QuestColors.text(context);
    // Derived from the fill: coral, jade and sky take ink, gold takes
    // osAccentInk, violet takes white. Never alpha-muted on an accent.
    final fgOnTint = QuestColors.onAccent(tint);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: tint,
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
      child: Column(
        children: [
          Icon(icon, size: 18, color: fgOnTint),
          const SizedBox(height: 6),
          Text(
            label.toUpperCase(),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: QuestTypography.labelSmall.copyWith(
              color: QuestColors.onAccentSoft(tint),
              fontSize: 8.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: QuestTypography.headlineSmall.copyWith(
              color: fgOnTint,
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.3,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

// ── Section header ─────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final ink = QuestColors.text(context);
    // Mission/Quest log section labels — kept small so the content stays
    // prominent. Replaces the old "MISSION"-prefixed labels with "QUEST".
    final cleaned = label
        .replaceAll(RegExp(r'\bmission\b', caseSensitive: false), 'Quest')
        .replaceAll(RegExp(r'\bMISSION\b'), 'QUEST');
    return Row(
      children: [
        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: QuestColors.accentYellow,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: ink, width: 1.4),
          ),
          child: Icon(icon, size: 12, color: ink),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            cleaned.toUpperCase(),
            overflow: TextOverflow.ellipsis,
            style: QuestTypography.headlineSmall.copyWith(
              color: ink,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Container(height: 1.5, color: ink.withAlpha(60)),
        ),
      ],
    );
  }
}

// ── Briefing card ──────────────────────────────────────────────────────────

class _BriefingCard extends StatelessWidget {
  const _BriefingCard({required this.description});
  final String description;

  @override
  Widget build(BuildContext context) {
    final ink = QuestColors.text(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: QuestColors.cardBg(context),
        borderRadius: BorderRadius.circular(14),
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
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: QuestColors.softRed,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: ink, width: 1.2),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.terminal_rounded,
                    color: QuestColors.onAccent(QuestColors.softRed), size: 11),
                const SizedBox(width: 5),
                Text(
                  '> DECRYPTED INTEL',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: QuestTypography.labelSmall.copyWith(
                    color: QuestColors.onAccent(QuestColors.softRed),
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            description,
            style: QuestTypography.bodyMedium.copyWith(
              color: ink.withAlpha(210),
              height: 1.6,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Criteria & requirement ─────────────────────────────────────────────────

class _CriteriaItem extends StatelessWidget {
  const _CriteriaItem({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final ink = QuestColors.text(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: QuestColors.cardBg(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ink, width: 1.8),
      ),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: QuestColors.softRed,
              shape: BoxShape.circle,
              border: Border.all(color: ink, width: 1.5),
            ),
            child: Icon(Icons.check_rounded,
                color: QuestColors.onAccent(QuestColors.softRed), size: 15),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: QuestTypography.bodyMedium.copyWith(
                color: ink.withAlpha(210),
                height: 1.45,
                fontSize: 13.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RequirementItem extends StatelessWidget {
  const _RequirementItem({
    required this.index,
    required this.text,
    required this.isComplete,
  });

  final int index;
  final String text;
  final bool isComplete;

  @override
  Widget build(BuildContext context) {
    final ink = QuestColors.text(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: QuestColors.cardBg(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ink, width: 1.8),
      ),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: isComplete
                  ? QuestColors.successGreen
                  : QuestColors.accentYellow,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: ink, width: 1.8),
            ),
            alignment: Alignment.center,
            child: isComplete
                ? Icon(Icons.check_rounded,
                    color: QuestColors.onAccent(QuestColors.successGreen),
                    size: 17)
                : Text(
                    '$index',
                    style: QuestTypography.labelMedium.copyWith(
                      color: ink,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: QuestTypography.bodyMedium.copyWith(
                color: isComplete ? ink.withAlpha(130) : ink.withAlpha(210),
                fontSize: 13.5,
                height: 1.4,
                decoration: isComplete ? TextDecoration.lineThrough : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Rewards card ──────────────────────────────────────────────────────────

class _RewardsCard extends StatelessWidget {
  const _RewardsCard({required this.xpReward, required this.difficulty});
  final int xpReward;
  final String difficulty;

  @override
  Widget build(BuildContext context) {
    final ink = QuestColors.text(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: QuestColors.accentYellow,
        borderRadius: BorderRadius.circular(14),
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
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: ink,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: const Icon(Icons.stars_rounded,
                    color: QuestColors.textPrimary, size: 24),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '+$xpReward XP',
                    style: QuestTypography.headlineMedium.copyWith(
                      color: ink,
                      fontWeight: FontWeight.w800,
                      fontSize: 22,
                      height: 1,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'EXPERIENCE POINTS',
                    style: QuestTypography.labelSmall.copyWith(
                      color: ink.withAlpha(180),
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: ink,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  difficulty.toUpperCase(),
                  style: QuestTypography.labelSmall.copyWith(
                    color: QuestColors.textPrimary,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            height: 8,
            decoration: BoxDecoration(
              color: QuestColors.pureWhite,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: ink, width: 1.2),
            ),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: 0.7,
              child: Container(
                decoration: BoxDecoration(
                  color: QuestColors.softRed,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Sticky action bar ──────────────────────────────────────────────────────

class _BottomActionBar extends StatelessWidget {
  const _BottomActionBar({
    required this.isActiveQuest,
    required this.isSubmitted,
    required this.activeQuestId,
    required this.pulse,
    required this.onTake,
  });

  final bool isActiveQuest;
  final bool isSubmitted;
  final String? activeQuestId;
  final AnimationController pulse;
  final VoidCallback onTake;

  @override
  Widget build(BuildContext context) {
    final ink = QuestColors.text(context);
    final String label;
    final IconData icon;
    final bool enabled;
    final Color fill;
    final Color fg;
    final VoidCallback? onTap;

    if (isSubmitted) {
      label = 'AWAITING REVIEW';
      icon = Icons.hourglass_top_rounded;
      enabled = false;
      fill = QuestColors.accentYellow;
      fg = ink;
      onTap = null;
    } else if (isActiveQuest && activeQuestId != null) {
      label = 'SUBMIT PROOF';
      icon = Icons.camera_alt_rounded;
      enabled = true;
      fill = QuestColors.softRed;
      fg = QuestColors.osTextOnPrimary;
      onTap = () => context.pushNamed(
            RouteNames.submitProof,
            pathParameters: {'userQuestId': activeQuestId!},
          );
    } else {
      // No longer "QUEST NOT ACTIVE" — let the user take it on. The
      // assignQuestFlow already handles the "another active quest" case
      // gracefully with its own snackbar.
      label = 'TAKE QUEST';
      icon = Icons.flag_rounded;
      enabled = true;
      fill = QuestColors.accentYellow;
      fg = ink;
      onTap = onTake;
    }

    final body = GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        height: 58,
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: ink, width: 2),
          boxShadow: [
            BoxShadow(
              color: ink,
              offset: const Offset(4, 4),
              blurRadius: 0,
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 20, color: fg),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: QuestTypography.buttonText.copyWith(
                  color: fg,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );

    return Container(
      width: double.infinity,
      padding: EdgeInsets.only(
        left: QuestSpacing.screenPadding,
        right: QuestSpacing.screenPadding,
        top: 14,
        bottom: MediaQuery.of(context).padding.bottom > 0
            ? MediaQuery.of(context).padding.bottom
            : 14,
      ),
      decoration: BoxDecoration(
        color: QuestColors.bg(context),
        border: Border(top: BorderSide(color: ink, width: 2)),
      ),
      child: enabled
          ? AnimatedBuilder(
              animation: pulse,
              builder: (_, child) {
                final s = 1 + 0.015 * pulse.value;
                return Transform.scale(scale: s, child: child);
              },
              child: body,
            )
          : body,
    );
  }
}
