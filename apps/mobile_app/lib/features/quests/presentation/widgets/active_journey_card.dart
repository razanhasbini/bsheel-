import 'package:app_core/app_core.dart';
import 'package:app_models/app_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../../core/backend/app_backend.dart';
import '../providers/journey_providers.dart';
import 'checkpoint_rail.dart';

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
  const ActiveJourneyCard({
    super.key,
    required this.run,
    this.onOpenMap,
    this.onOpen,
    this.onUnlockShown,
    this.advanceFrom,
  });

  final JourneyRun run;
  final VoidCallback? onOpenMap;

  /// Opens the journey detail page. The card is tappable as a whole.
  final VoidCallback? onOpen;

  /// Called once the rail's unlock transition has finished playing.
  final VoidCallback? onUnlockShown;

  /// Completed-count to animate from, when an unlock is still unseen.
  final int? advanceFrom;

  @override
  ConsumerState<ActiveJourneyCard> createState() => _ActiveJourneyCardState();
}

class _ActiveJourneyCardState extends ConsumerState<ActiveJourneyCard> {
  int? get _advanceFrom => widget.advanceFrom;
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
    final current = run.nextForViewer ??
        run.stages
            .where((s) => s.state == StageState.underReview)
            .firstOrNull ??
        run.stages.where((s) => s.state == StageState.available).firstOrNull;
    // The whole card opens the journey, not just the button: somebody with
    // nothing to tap still wants to know what is going on.
    return GestureDetector(
      onTap: widget.onOpen,
      behavior: HitTestBehavior.opaque,
      child: Container(
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
            // Three stages means three checkpoints, evenly spaced. A
            // percentage bar at 66% says nothing about which one you are
            // standing on, which is the only thing a player needs from a
            // glance at Home.
            if (run.orderMatters)
              CheckpointRail(
                stages: run.stages,
                advanceFrom: _advanceFrom,
                height: 52,
                onFinished: widget.onUnlockShown,
              )
            else
              _AnyOrderSummary(run: run),
            const SizedBox(height: QuestSpacing.md),
            // Only the checkpoint that matters right now. The rest of the
            // journey lives on the detail page, where there is room for it.
            if (current != null) _CurrentSummary(stage: current, run: run),
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
      ),
    );
  }

  /// The button says what is actually true of this journey right now.
  ///
  /// A single CONTINUE label lies in most of these states: it would offer to
  /// start something a moderator is still holding, or something that belongs
  /// to a teammate, and the server would refuse either.
  Widget _action(JourneyRun run) {
    if (run.isCompleted) {
      return _Secondary(label: 'VIEW COMPLETED JOURNEY', onTap: widget.onOpen);
    }
    if (run.canContinue) {
      return Row(
        children: [
          Expanded(
            child: ArcadeButton(
              label: _starting ? 'STARTING…' : 'CONTINUE JOURNEY',
              isLoading: _starting,
              onTap: _starting ? null : () => _continue(run.nextForViewer!),
            ),
          ),
          if (widget.onOpenMap != null &&
              (run.nextForViewer?.hasCoordinates ?? false)) ...[
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
                  borderRadius:
                      BorderRadius.circular(QuestSpacing.radiusControl),
                  border:
                      Border.all(color: QuestColors.osTextPrimary, width: 2),
                ),
                child: const Icon(Icons.map_rounded,
                    size: 20, color: QuestColors.osTextPrimary),
              ),
            ),
          ],
        ],
      );
    }
    if (run.isUnderReview) {
      return _Secondary(
        label: 'UNDER REVIEW',
        icon: Icons.hourglass_top_rounded,
        tint: QuestColors.osAccentText,
        onTap: widget.onOpen,
      );
    }
    // A relay waiting on somebody else. Naming them is the difference
    // between "nothing is happening" and "it is Tayseer's turn".
    final waiting = run.stages
        .where((s) => s.state == StageState.available && !s.isYours)
        .map((s) => s.targetUsername)
        .whereType<String>()
        .toList();
    return _Secondary(
      label: waiting.isEmpty
          ? 'VIEW JOURNEY'
          : 'WAITING FOR @${waiting.first.toUpperCase()}',
      onTap: widget.onOpen,
    );
  }
}

/// The one checkpoint that matters right now, on Home.
class _CurrentSummary extends StatelessWidget {
  const _CurrentSummary({required this.stage, required this.run});

  final JourneyStage stage;
  final JourneyRun run;

  @override
  Widget build(BuildContext context) {
    final context_ = <String>[
      if (stage.placeName != null) stage.placeName!,
      if (run.isRelay && stage.targetUsername != null)
        '@${stage.targetUsername}',
      if (stage.stepOrder == run.totalSteps) 'Final checkpoint',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          // Null means the server withheld it; the card names the mystery
          // rather than inventing a title for it.
          (stage.title ?? 'A checkpoint waiting to be found').toUpperCase(),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: QuestTypography.osLabelLarge.copyWith(
            fontSize: 14,
            color: QuestColors.text(context),
          ),
        ),
        if (context_.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            context_.join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: QuestTypography.osBodySmall.copyWith(
              fontSize: 12,
              color: QuestColors.textDim(context),
            ),
          ),
        ],
      ],
    );
  }
}

/// An any-order journey has no rail to draw, because it has no order.
class _AnyOrderSummary extends StatelessWidget {
  const _AnyOrderSummary({required this.run});

  final JourneyRun run;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final stage in run.stages)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                switch (stage.state) {
                  StageState.completed => Icons.check_circle_rounded,
                  StageState.underReview => Icons.hourglass_top_rounded,
                  StageState.available => Icons.radio_button_checked,
                  StageState.locked => Icons.lock_rounded,
                },
                size: 14,
                color: switch (stage.state) {
                  StageState.completed => QuestColors.osSuccess,
                  StageState.underReview => QuestColors.osAccent,
                  StageState.available => QuestColors.osPrimary,
                  StageState.locked => QuestColors.osTextMuted,
                },
              ),
              const SizedBox(width: 4),
              Text(
                stage.title ?? 'Mystery',
                style: QuestTypography.osBodySmall.copyWith(
                  fontSize: 12,
                  color: QuestColors.textDim(context),
                ),
              ),
            ],
          ),
      ],
    );
  }
}

/// A non-primary action: a state to read, and a way into the journey.
class _Secondary extends StatelessWidget {
  const _Secondary({required this.label, this.onTap, this.icon, this.tint});

  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final colour = tint ?? QuestColors.osPrimary;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 46,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: QuestColors.osSurface,
          borderRadius: BorderRadius.circular(QuestSpacing.radiusControl),
          border: Border.all(color: QuestColors.osTextPrimary, width: 2),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 15, color: colour),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: QuestTypography.osLabelSmall.copyWith(
                fontSize: 11,
                letterSpacing: 0.9,
                color: colour,
              ),
            ),
          ],
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
