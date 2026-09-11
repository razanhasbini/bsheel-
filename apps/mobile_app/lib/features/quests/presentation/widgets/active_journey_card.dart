import 'package:app_core/app_core.dart';
import 'package:app_models/app_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../../core/backend/app_backend.dart';
import '../providers/journey_providers.dart';

/// A journey in progress, on Home.
///
/// This card is the answer to the bug that started all of this: an approved
/// checkpoint used to take the whole journey off the screen, because the
/// only thing Home could show was a single assigned quest. A journey is the
/// parent of its checkpoints and outlives every one of them, so it stays
/// here until the last one is verified.
///
/// It renders two genuinely different shapes. A sequential journey is a
/// route with a position on it — stage 2 of 3. An any-order journey has no
/// such position, so counting down what is left is the honest framing and
/// "next stage" would be a lie.
class ActiveJourneyCard extends ConsumerStatefulWidget {
  const ActiveJourneyCard({super.key, required this.run, this.onOpenMap});

  final JourneyRun run;
  final VoidCallback? onOpenMap;

  @override
  ConsumerState<ActiveJourneyCard> createState() => _ActiveJourneyCardState();
}

class _ActiveJourneyCardState extends ConsumerState<ActiveJourneyCard> {
  bool _starting = false;
  String? _error;

  Future<void> _continue(JourneyStage stage) async {
    setState(() {
      _starting = true;
      _error = null;
    });
    try {
      await AppBackend.repositories.journeys.continueJourney(
        widget.run.runId,
        // Only meaningful on an any-order journey, where the player picks
        // which open checkpoint to take on.
        questId: widget.run.orderMatters ? null : stage.questId,
      );
      ref.invalidate(activeJourneysProvider);
    } catch (error) {
      if (mounted) setState(() => _error = _readable(error));
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  /// The server refuses with one code for "not yours", "not unlocked" and
  /// "already started", so the message stays general rather than guessing
  /// which it was.
  String _readable(Object error) {
    final raw = error.toString().toLowerCase();
    if (raw.contains('no_checkpoint_available')) {
      return 'That checkpoint is not ready for you right now.';
    }
    if (raw.contains('cooldown')) return 'Hold on a moment, then try again.';
    if (raw.contains('one_active') || raw.contains('conflict')) {
      return 'Finish or drop your current quest first.';
    }
    return 'Could not start that checkpoint. Try again.';
  }

  @override
  Widget build(BuildContext context) {
    final run = widget.run;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: QuestSpacing.sm),
      padding: const EdgeInsets.all(QuestSpacing.md),
      decoration: BoxDecoration(
        color: QuestColors.cardBg(context),
        borderRadius: BorderRadius.circular(QuestSpacing.radiusHero),
        border: Border.all(color: QuestColors.osTextPrimary, width: 2),
        boxShadow: const [
          BoxShadow(color: QuestColors.osTextPrimary, offset: Offset(0, 5)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  run.title.toUpperCase(),
                  style: QuestTypography.osHeadlineSmall.copyWith(
                    fontSize: 17,
                    color: QuestColors.text(context),
                  ),
                ),
              ),
              if (run.isRelay)
                const _Chip(label: 'RELAY', tint: QuestColors.osAccent),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            run.orderMatters
                ? 'STAGE ${run.completedSteps + 1} OF ${run.totalSteps}'
                : '${run.remaining} CHECKPOINT${run.remaining == 1 ? '' : 'S'} REMAINING',
            style: QuestTypography.osLabelSmall.copyWith(
              fontSize: 10,
              letterSpacing: 1.0,
              color: QuestColors.osPrimary,
            ),
          ),
          const SizedBox(height: QuestSpacing.sm),
          _ProgressBar(progress: run.progress),
          const SizedBox(height: QuestSpacing.md),
          for (final stage in run.stages) _StageRow(stage: stage, run: run),
          if (_error != null) ...[
            const SizedBox(height: QuestSpacing.sm),
            Text(
              _error!,
              style: QuestTypography.osBodySmall.copyWith(
                fontSize: 12,
                color: QuestColors.osRedText,
              ),
            ),
          ],
          const SizedBox(height: QuestSpacing.sm),
          _action(run),
        ],
      ),
    );
  }

  Widget _action(JourneyRun run) {
    // Waiting on a decision is a real state and deserves saying so. Showing
    // CONTINUE here would offer something the server will refuse.
    if (run.isUnderReview && !run.canContinue) {
      return Row(
        children: [
          const Icon(Icons.hourglass_top_rounded,
              size: 15, color: QuestColors.osAccentText),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'CHECKPOINT UNDER REVIEW',
              style: QuestTypography.osLabelSmall.copyWith(
                fontSize: 10,
                letterSpacing: 0.9,
                color: QuestColors.osAccentText,
              ),
            ),
          ),
        ],
      );
    }

    final next = run.nextForViewer;
    if (next == null) {
      // A relay whose ball is in somebody else's court. Naming them is the
      // difference between "nothing is happening" and "it is Tayseer's turn".
      final waitingOn = run.stages
          .where((s) => s.state == StageState.available && !s.isYours)
          .map((s) => s.targetUsername)
          .whereType<String>()
          .toList();
      return Text(
        waitingOn.isEmpty
            ? 'Nothing to do on this journey right now.'
            : '@${waitingOn.first} is up next.',
        style: QuestTypography.osBodySmall.copyWith(
          fontSize: 12,
          color: QuestColors.textDim(context),
        ),
      );
    }

    return Row(
      children: [
        Expanded(
          child: ArcadeButton(
            label: _starting ? 'STARTING…' : 'CONTINUE JOURNEY',
            isLoading: _starting,
            onTap: _starting ? null : () => _continue(next),
          ),
        ),
        if (widget.onOpenMap != null && next.hasCoordinates) ...[
          const SizedBox(width: QuestSpacing.sm),
          GestureDetector(
            onTap: widget.onOpenMap,
            behavior: HitTestBehavior.opaque,
            child: Container(
              width: 52,
              height: 52,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: QuestColors.osSurface,
                borderRadius: BorderRadius.circular(QuestSpacing.radiusControl),
                border: Border.all(color: QuestColors.osTextPrimary, width: 2),
              ),
              child: const Icon(Icons.map_rounded,
                  size: 20, color: QuestColors.osTextPrimary),
            ),
          ),
        ],
      ],
    );
  }
}

/// One checkpoint on the card: ✓ done, ● yours, ○ locked or somebody else's.
class _StageRow extends StatelessWidget {
  const _StageRow({required this.stage, required this.run});

  final JourneyStage stage;
  final JourneyRun run;

  @override
  Widget build(BuildContext context) {
    final (icon, tint) = switch (stage.state) {
      StageState.completed => (
          Icons.check_circle_rounded,
          QuestColors.osSuccess
        ),
      StageState.underReview => (
          Icons.hourglass_top_rounded,
          QuestColors.osAccent
        ),
      StageState.available => (
          stage.isYours
              ? Icons.play_circle_fill_rounded
              : Icons.circle_outlined,
          stage.isYours ? QuestColors.osPrimary : QuestColors.osTextMuted,
        ),
      StageState.locked => (Icons.lock_rounded, QuestColors.osTextMuted),
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: tint),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  // Null means the server withheld it, so the card says the
                  // checkpoint exists without inventing what it is.
                  stage.title ?? 'A checkpoint waiting to be found',
                  style: QuestTypography.osBodySmall.copyWith(
                    fontSize: 13,
                    fontStyle: stage.title == null
                        ? FontStyle.italic
                        : FontStyle.normal,
                    color: stage.state == StageState.locked
                        ? QuestColors.textDim(context)
                        : QuestColors.text(context),
                  ),
                ),
                if (stage.placeName != null || stage.targetUsername != null)
                  Text(
                    [
                      if (stage.placeName != null) stage.placeName!,
                      if (run.isRelay && stage.targetUsername != null)
                        '@${stage.targetUsername}',
                    ].join(' · '),
                    style: QuestTypography.osLabelSmall.copyWith(
                      fontSize: 10,
                      color: QuestColors.textDim(context),
                    ),
                  ),
              ],
            ),
          ),
          if (stage.requiresLocationVerification &&
              stage.state != StageState.completed)
            const Icon(Icons.cell_tower_rounded,
                size: 12, color: QuestColors.osCool),
        ],
      ),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(QuestSpacing.radiusFull),
      child: Container(
        height: 8,
        color: QuestColors.textDim(context).withAlpha(40),
        alignment: Alignment.centerLeft,
        child: AnimatedFractionallySizedBox(
          duration: const Duration(milliseconds: 520),
          curve: Curves.easeOutCubic,
          widthFactor: progress.clamp(0.0, 1.0),
          child: Container(color: QuestColors.osSuccess),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.tint});

  final String label;
  final Color tint;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: tint,
          borderRadius: BorderRadius.circular(QuestSpacing.radiusChip),
          border: Border.all(color: QuestColors.osTextPrimary, width: 1.5),
        ),
        child: Text(
          label,
          style: QuestTypography.osLabelSmall.copyWith(
            fontSize: 9,
            letterSpacing: 0.8,
            color: QuestColors.onAccent(tint),
          ),
        ),
      );
}
