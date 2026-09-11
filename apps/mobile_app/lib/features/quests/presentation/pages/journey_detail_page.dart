import 'package:app_core/app_core.dart';
import 'package:app_models/app_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../../core/backend/app_backend.dart';
import '../../../../core/router/route_names.dart';
import '../providers/journey_providers.dart';
import '../widgets/checkpoint_rail.dart';
import '../widgets/detail_primitives.dart';

/// One journey, in full — and the place progression is celebrated.
///
/// This is where a notification lands, which is deliberate: a tap that
/// opened Home and threw a modal left people asking what had actually
/// changed. Here the timeline itself transitions, and when the animation
/// finishes the new state is simply the state of the page.
///
/// Two levels, per the brief: the journey (progress, every checkpoint and
/// what happened at it) and the current checkpoint (what you actually have
/// to go and do).
final journeyDetailProvider =
    FutureProvider.autoDispose.family<JourneyRun, String>((ref, runId) async {
  return AppBackend.repositories.journeys.detail(runId);
});

class JourneyDetailPage extends ConsumerStatefulWidget {
  const JourneyDetailPage({super.key, required this.runId});

  final String runId;

  @override
  ConsumerState<JourneyDetailPage> createState() => _JourneyDetailPageState();
}

class _JourneyDetailPageState extends ConsumerState<JourneyDetailPage> {
  /// The completed-count to animate from, captured once on arrival.
  ///
  /// Held in state rather than read from the run each build: the server
  /// stops reporting the unlock the moment it is acknowledged, and the
  /// animation must not vanish halfway through because its own trigger was
  /// cleared.
  int? _advanceFrom;
  bool _captured = false;
  bool _starting = false;
  bool _choosingFeedMode = false;
  String? _error;
  int? _expandedStep;

  void _captureUnlock(JourneyRun run) {
    if (_captured) return;
    _captured = true;
    if (run.unseenUnlock == null) return;
    // Rewind by one: the rail draws the state before this checkpoint opened
    // and then runs forward into the present.
    setState(() => _advanceFrom = run.completedSteps);
  }

  /// Records how the route should reach the feed, once.
  ///
  /// Asked on this page rather than at the moment of posting, because by the
  /// time a player is staring at a submit screen the question is already too
  /// late for the checkpoints behind it — and the server refuses the change
  /// then for exactly that reason.
  Future<void> _chooseFeedMode(JourneyRun run, {required bool oneRoutePost}) async {
    setState(() => _choosingFeedMode = true);
    try {
      await AppBackend.repositories.journeys
          .chooseFeedMode(run.runId, oneRoutePost: oneRoutePost);
    } catch (_) {
      // The run is re-read either way: whatever the server decided is what
      // the page should show, including "too late".
    } finally {
      ref
        ..invalidate(journeyDetailProvider(widget.runId))
        ..invalidate(activeJourneysProvider);
      if (mounted) setState(() => _choosingFeedMode = false);
    }
  }

  Future<void> _acknowledge() async {
    // Only after it has played. A crash mid-transition should leave the
    // server still owing the moment, not having forgotten it.
    try {
      await AppBackend.repositories.journeys.acknowledgeUnlock(widget.runId);
      ref.invalidate(activeJourneysProvider);
    } catch (_) {
      // Nothing to do: the worst case is the celebration offered again.
    }
  }

  Future<void> _continue(JourneyRun run) async {
    final next = run.nextForViewer;
    if (next == null) return;
    setState(() {
      _starting = true;
      _error = null;
    });
    try {
      await AppBackend.repositories.journeys.continueJourney(
        run.runId,
        questId: run.orderMatters ? null : next.questId,
      );
      ref
        ..invalidate(journeyDetailProvider(widget.runId))
        ..invalidate(activeJourneysProvider);
      if (mounted && next.questId != null) {
        context.pushNamed(RouteNames.questDetails,
            pathParameters: {'id': next.questId!});
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error =
            error.toString().toLowerCase().contains('cooldown')
                ? 'Hold on a moment, then try again.'
                : 'Could not start that checkpoint. Try again.');
      }
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(journeyDetailProvider(widget.runId));
    return Scaffold(
      backgroundColor: QuestColors.bg(context),
      body: SafeArea(
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => _Message(
            text: 'Could not load this journey.',
            onBack: () => _back(context),
          ),
          data: (run) {
            _captureUnlock(run);
            return _body(run);
          },
        ),
      ),
    );
  }

  void _back(BuildContext context) =>
      context.canPop() ? context.pop() : context.goNamed(RouteNames.home);

  Widget _body(JourneyRun run) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      children: [
        Row(
          children: [
            ArcadeBackButton(onTap: () => _back(context)),
            const Spacer(),
            if (run.isRelay)
              const _Tag(label: 'RELAY', tint: QuestColors.osAccent),
          ],
        ),
        const SizedBox(height: QuestSpacing.md),
        Text(
          run.title.toUpperCase(),
          style: QuestTypography.osDisplayLarge.copyWith(
            fontSize: 28,
            height: 1.0,
            letterSpacing: -1.0,
            color: QuestColors.text(context),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          run.isCompleted
              ? '${run.totalSteps} / ${run.totalSteps} CHECKPOINTS — COMPLETE'
              : run.orderMatters
                  ? '${run.completedSteps} / ${run.totalSteps} CHECKPOINTS COMPLETED'
                  : '${run.completedSteps} / ${run.totalSteps} COMPLETED · ANY ORDER',
          style: QuestTypography.osLabelSmall.copyWith(
            fontSize: 11,
            letterSpacing: 1.0,
            color: run.isCompleted
                ? QuestColors.osSuccessText
                : QuestColors.osPrimary,
          ),
        ),
        const SizedBox(height: QuestSpacing.md),
        // A rail only means something where there is an order to walk. An
        // any-order journey has none, so it gets a tally and a list instead
        // of a line implying a sequence that does not exist.
        if (run.orderMatters)
          CheckpointRail(
            stages: run.stages,
            advanceFrom: _advanceFrom,
            height: 60,
            onFinished: _acknowledge,
          ),
        if (!run.orderMatters && run.unseenUnlock != null)
          _UnlockBanner(onShown: _acknowledge),
        // Asked once, before anything has been submitted, and then never
        // again — `needsFeedModeChoice` is false the moment it is answered
        // or the moment answering stops changing anything.
        if (run.needsFeedModeChoice) ...[
          const SizedBox(height: QuestSpacing.lg),
          _FeedModeChoice(
            busy: _choosingFeedMode,
            onChoose: (oneRoutePost) =>
                _chooseFeedMode(run, oneRoutePost: oneRoutePost),
          ),
        ] else if (run.postsAsOneRoute && !run.isCompleted) ...[
          const SizedBox(height: QuestSpacing.lg),
          const _FeedModeNote(),
        ],
        const SizedBox(height: QuestSpacing.lg),
        const BlockLabel('JOURNEY TIMELINE'),
        const SizedBox(height: QuestSpacing.sm),
        for (final stage in run.stages)
          _VerticalStage(
            stage: stage,
            run: run,
            isLast: stage.stepOrder == run.stages.last.stepOrder,
            expanded: _expandedStep == stage.stepOrder,
            onTap: () => setState(() => _expandedStep =
                _expandedStep == stage.stepOrder ? null : stage.stepOrder),
          ),
        if (run.nextForViewer != null) ...[
          const SizedBox(height: QuestSpacing.lg),
          const BlockLabel('CURRENT CHECKPOINT'),
          const SizedBox(height: QuestSpacing.sm),
          _CurrentCheckpoint(
            stage: run.nextForViewer!,
            starting: _starting,
            error: _error,
            onStart: () => _continue(run),
            onMap: () => context.pushNamed(RouteNames.map),
            // The appeal composer already exists on the submission screen.
            // Sending the player there rather than growing a second one
            // keeps one place where an appeal is written and reviewed.
            onAppeal: () {
              final submissionId = run.nextForViewer?.rejectedSubmissionId;
              if (submissionId == null) return;
              context.pushNamed(
                RouteNames.submissionStatus,
                pathParameters: {'id': submissionId},
              );
            },
          ),
        ],
        if (run.isCompleted) ...[
          const SizedBox(height: QuestSpacing.lg),
          _CompletedPanel(
              run: run, onMap: () => context.pushNamed(RouteNames.map)),
        ],
        if (run.nextForViewer == null && !run.isCompleted) ...[
          const SizedBox(height: QuestSpacing.lg),
          _WaitingPanel(run: run),
        ],
      ],
    );
  }
}

/// How this route reaches the feed, asked before the first checkpoint.
///
/// Two buttons rather than a switch because there is no default worth
/// pre-selecting: a player who walked a route may well want the three stops
/// as they happen, and a player collecting a country may well want the route.
/// A switch would make one of those an opinion the app already had.
class _FeedModeChoice extends StatelessWidget {
  const _FeedModeChoice({required this.busy, required this.onChoose});

  final bool busy;
  final void Function(bool oneRoutePost) onChoose;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(QuestSpacing.lg),
        decoration: BoxDecoration(
          color: QuestColors.cardBg(context),
          borderRadius: BorderRadius.circular(QuestSpacing.radiusHero),
          border: Border.all(color: QuestColors.osTextPrimary, width: 2),
          boxShadow: const [
            BoxShadow(color: QuestColors.osTextPrimary, offset: Offset(0, 5)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const BlockLabel('HOW SHOULD THIS POST?'),
            const SizedBox(height: 6),
            Text(
              'Pick now — it applies to the whole route, and it cannot change '
              'once you have submitted a checkpoint.',
              style: QuestTypography.osBodySmall.copyWith(
                  fontSize: 12, color: QuestColors.osTextSecondary),
            ),
            const SizedBox(height: QuestSpacing.md),
            ArcadeButton(
              label: 'ONE POST FOR THE ROUTE',
              isLoading: busy,
              onTap: busy ? null : () => onChoose(true),
            ),
            const SizedBox(height: 6),
            Text(
              'Nothing shows in the feed until the last checkpoint clears, '
              'then the whole route posts together.',
              style: QuestTypography.osBodySmall.copyWith(
                  fontSize: 11, color: QuestColors.osTextSecondary),
            ),
            const SizedBox(height: QuestSpacing.md),
            ArcadeButton(
              label: 'A POST PER STOP',
              variant: ArcadeButtonVariant.secondary,
              onTap: busy ? null : () => onChoose(false),
            ),
            const SizedBox(height: 6),
            Text(
              'Each checkpoint posts on its own as it is approved.',
              style: QuestTypography.osBodySmall.copyWith(
                  fontSize: 11, color: QuestColors.osTextSecondary),
            ),
          ],
        ),
      );
}

/// The standing reminder, for a route already set to post as one.
///
/// Worth saying plainly on every visit: a player who submits a checkpoint
/// and then cannot find it in the feed should not have to wonder whether it
/// failed. It is being held, on purpose, and this says so.
class _FeedModeNote extends StatelessWidget {
  const _FeedModeNote();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(
            horizontal: QuestSpacing.md, vertical: QuestSpacing.sm),
        decoration: BoxDecoration(
          color: QuestColors.osSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: QuestColors.osTextPrimary, width: 2),
        ),
        child: Text(
          'POSTING AS ONE ROUTE — your checkpoints stay out of the feed until '
          'the last one clears, then post together.',
          style: QuestTypography.osBodySmall
              .copyWith(fontSize: 11, color: QuestColors.osTextSecondary),
        ),
      );
}

/// One checkpoint on the vertical timeline, with room for what happened.
class _VerticalStage extends StatelessWidget {
  const _VerticalStage({
    required this.stage,
    required this.run,
    required this.isLast,
    required this.expanded,
    required this.onTap,
  });

  final JourneyStage stage;
  final JourneyRun run;
  final bool isLast;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (icon, tint, label) = switch (stage.state) {
      StageState.completed => (
          Icons.check_rounded,
          QuestColors.osSuccess,
          'COMPLETED'
        ),
      StageState.inProgress => (
          Icons.play_arrow_rounded,
          QuestColors.osPrimary,
          'IN PROGRESS'
        ),
      StageState.underReview => (
          Icons.hourglass_top_rounded,
          QuestColors.osAccent,
          // An appeal is a different wait from a first review, and the one
          // the player is anxious about. Saying only "under review" left
          // them unsure the appeal had been sent at all.
          stage.appealed ? 'APPEAL UNDER REVIEW' : 'UNDER REVIEW',
        ),
      StageState.rejected => (
          Icons.refresh_rounded,
          QuestColors.osRed,
          stage.appealed ? 'APPEAL SENT' : 'REJECTED',
        ),
      StageState.available => (
          Icons.play_arrow_rounded,
          stage.isYours ? QuestColors.osPrimary : QuestColors.osTextMuted,
          stage.isYours ? 'CURRENT' : 'THEIR TURN',
        ),
      StageState.locked => (
          Icons.lock_rounded,
          QuestColors.osTextMuted,
          'LOCKED'
        ),
    };

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: stage.state == StageState.locked
                        ? QuestColors.osSurface
                        : tint,
                    shape: BoxShape.circle,
                    border:
                        Border.all(color: QuestColors.osTextPrimary, width: 2),
                  ),
                  child: Icon(icon,
                      size: 14,
                      color: stage.state == StageState.locked
                          ? QuestColors.osTextMuted
                          : QuestColors.onAccent(tint)),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 3,
                      color: stage.state == StageState.completed
                          ? QuestColors.osSuccess
                          : QuestColors.osTextMuted.withAlpha(70),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: QuestSpacing.sm),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(bottom: isLast ? 0 : QuestSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text('STAGE ${stage.stepOrder}',
                            style: QuestTypography.osLabelSmall.copyWith(
                                fontSize: 9, letterSpacing: 0.9, color: tint)),
                        const SizedBox(width: 8),
                        Text(label,
                            style: QuestTypography.osLabelSmall.copyWith(
                                fontSize: 9,
                                letterSpacing: 0.9,
                                color: QuestColors.textDim(context))),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      // A locked checkpoint of a hidden chain keeps its
                      // secret; the server never sent the title, so there is
                      // nothing here that could reveal it.
                      stage.title ?? 'Mystery checkpoint',
                      style: QuestTypography.osBodyMedium.copyWith(
                        fontSize: 15,
                        fontStyle: stage.title == null
                            ? FontStyle.italic
                            : FontStyle.normal,
                        color: stage.state == StageState.locked
                            ? QuestColors.textDim(context)
                            : QuestColors.text(context),
                      ),
                    ),
                    if (run.isRelay && stage.targetUsername != null)
                      Text('@${stage.targetUsername}',
                          style: QuestTypography.osLabelSmall.copyWith(
                              fontSize: 10,
                              color: QuestColors.textDim(context))),
                    if (expanded) _expansion(context),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _expansion(BuildContext context) {
    final lines = <String>[
      if (stage.completedAt != null) 'Approved ${_time(stage.completedAt!)}',
      if (stage.xpReward != null) '+${stage.xpReward} XP',
      if (stage.placeName != null) stage.placeName!,
      if (stage.difficulty != null) stage.difficulty!.toUpperCase(),
    ];
    if (lines.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(
          'This checkpoint opens when the one before it is approved.',
          style: QuestTypography.osBodySmall
              .copyWith(fontSize: 12, color: QuestColors.textDim(context)),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(lines.join(' · '),
          style: QuestTypography.osBodySmall
              .copyWith(fontSize: 12, color: QuestColors.textDim(context))),
    );
  }

  String _time(DateTime at) {
    final local = at.toLocal();
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    return '$hour:$minute ${local.hour < 12 ? 'AM' : 'PM'}';
  }
}

/// What the player actually has to go and do.
/// Why the last attempt was rejected, in the words the player was given.
class _RejectionBlock extends StatelessWidget {
  const _RejectionBlock({required this.stage});

  final JourneyStage stage;

  @override
  Widget build(BuildContext context) {
    final note = stage.rejectionNote?.trim();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(QuestSpacing.md),
      decoration: BoxDecoration(
        color: QuestColors.osRed.withAlpha(30),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: QuestColors.osRed, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            stage.appealed ? 'APPEAL SENT' : 'THIS CHECKPOINT WAS REJECTED',
            style: QuestTypography.osLabelSmall.copyWith(
                fontSize: 10,
                letterSpacing: 1.0,
                color: QuestColors.osRedText),
          ),
          const SizedBox(height: 6),
          Text(
            note != null && note.isNotEmpty
                ? note
                // A rejection with no reason recorded is rare and is still
                // not a blank space: say that plainly rather than leaving
                // the player to guess what they did wrong.
                : 'No reason was recorded. If that seems wrong, appeal it and '
                    'a person will look again.',
            style: QuestTypography.osBodySmall
                .copyWith(fontSize: 13, color: QuestColors.text(context)),
          ),
        ],
      ),
    );
  }
}

class _CurrentCheckpoint extends StatelessWidget {
  const _CurrentCheckpoint({
    required this.stage,
    required this.starting,
    required this.error,
    required this.onStart,
    required this.onMap,
    required this.onAppeal,
  });

  final JourneyStage stage;
  final bool starting;
  final String? error;
  final VoidCallback onStart;
  final VoidCallback onMap;
  final VoidCallback onAppeal;

  @override
  Widget build(BuildContext context) {
    return Container(
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
          Text(stage.title ?? 'Mystery checkpoint',
              style: QuestTypography.osHeadlineSmall
                  .copyWith(fontSize: 19, color: QuestColors.text(context))),
          if (stage.placeName != null) ...[
            const SizedBox(height: 4),
            Text(
              [stage.placeName, stage.countryName]
                  .whereType<String>()
                  .join(' · '),
              style: QuestTypography.osLabelSmall
                  .copyWith(fontSize: 10, color: QuestColors.textDim(context)),
            ),
          ],
          if (stage.description != null) ...[
            const SizedBox(height: QuestSpacing.sm),
            Text(stage.description!,
                style: QuestTypography.osBodyMedium.copyWith(
                    fontSize: 14,
                    height: 1.5,
                    color: QuestColors.textDim(context))),
          ],
          const SizedBox(height: QuestSpacing.md),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (stage.xpReward != null)
                StatChip(
                    label: 'XP',
                    value: '${stage.xpReward}',
                    tint: QuestColors.osAccent),
              if (stage.durationHours != null)
                StatChip(
                    label: 'TIME',
                    value: '${stage.durationHours}H',
                    tint: QuestColors.osCool,
                    mono: true),
              if (stage.difficulty != null)
                StatChip(
                    label: 'LEVEL',
                    value: stage.difficulty!.toUpperCase(),
                    tint: QuestColors.osSurface),
            ],
          ),
          const SizedBox(height: QuestSpacing.md),
          const CheckRow(text: 'Photo or video proof', met: true),
          if (stage.requiresLocationVerification)
            const CheckRow(
              // Said plainly because the timing is what people get wrong:
              // presence is checked when you submit, not when you start.
              text: 'Your carrier confirms you are there when you submit',
              met: true,
            ),
          if (error != null) ...[
            const SizedBox(height: QuestSpacing.sm),
            Text(error!,
                style: QuestTypography.osBodySmall
                    .copyWith(fontSize: 12, color: QuestColors.osRedText)),
          ],
          // What actually happened, before what to do about it. A player
          // looking at a rejected checkpoint has one question, and a button
          // is not the answer to it.
          if (stage.state == StageState.rejected) ...[
            const SizedBox(height: QuestSpacing.md),
            _RejectionBlock(stage: stage),
          ],
          const SizedBox(height: QuestSpacing.md),
          ArcadeButton(
            label: switch (stage.state) {
              StageState.inProgress => 'GO TO CHECKPOINT',
              // Not "start": the player has been here, and the word that
              // matters is that the attempt is not spent.
              StageState.rejected => starting ? 'STARTING…' : 'TRY THIS AGAIN',
              _ => starting ? 'STARTING…' : 'START CHECKPOINT',
            },
            isLoading: starting && stage.state != StageState.inProgress,
            onTap: starting ? null : onStart,
          ),
          // Offered only while it is still possible. An appeal already sent
          // is reported by the state above, and a second one is refused by
          // the server — a button that can only fail is worse than none.
          if (stage.state == StageState.rejected &&
              !stage.appealed &&
              stage.rejectedSubmissionId != null) ...[
            const SizedBox(height: 8),
            ArcadeButton(
              label: 'APPEAL THIS DECISION',
              variant: ArcadeButtonVariant.secondary,
              onTap: onAppeal,
            ),
          ],
          if (stage.hasCoordinates) ...[
            const SizedBox(height: QuestSpacing.sm),
            GestureDetector(
              onTap: onMap,
              behavior: HitTestBehavior.opaque,
              child: SizedBox(
                height: 44,
                child: Center(
                  child: Text('VIEW ON MAP',
                      style: QuestTypography.osLabelSmall.copyWith(
                          fontSize: 11,
                          letterSpacing: 1.0,
                          color: QuestColors.osPrimary)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CompletedPanel extends StatelessWidget {
  const _CompletedPanel({required this.run, required this.onMap});

  final JourneyRun run;
  final VoidCallback onMap;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(QuestSpacing.lg),
        decoration: BoxDecoration(
          color: QuestColors.osSuccess,
          borderRadius: BorderRadius.circular(QuestSpacing.radiusHero),
          border: Border.all(color: QuestColors.osTextPrimary, width: 2),
        ),
        child: Column(
          children: [
            Text('JOURNEY COMPLETE',
                style: QuestTypography.osDisplayLarge.copyWith(
                    fontSize: 24,
                    letterSpacing: -0.8,
                    color: QuestColors.onAccent(QuestColors.osSuccess))),
            const SizedBox(height: 6),
            Text('Every checkpoint verified. That is the whole route walked.',
                textAlign: TextAlign.center,
                style: QuestTypography.osBodyMedium.copyWith(
                    fontSize: 13,
                    color: QuestColors.onAccent(QuestColors.osSuccess))),
            const SizedBox(height: QuestSpacing.md),
            GestureDetector(
              onTap: onMap,
              behavior: HitTestBehavior.opaque,
              child: SizedBox(
                height: 44,
                child: Center(
                  child: Text('VIEW ON MAP',
                      style: QuestTypography.osLabelSmall.copyWith(
                          fontSize: 11,
                          letterSpacing: 1.0,
                          color: QuestColors.onAccent(QuestColors.osSuccess))),
                ),
              ),
            ),
          ],
        ),
      );
}

/// A relay whose ball is in somebody else's court.
class _WaitingPanel extends StatelessWidget {
  const _WaitingPanel({required this.run});

  final JourneyRun run;

  @override
  Widget build(BuildContext context) {
    final waiting = run.stages
        .where((s) => s.state == StageState.available && !s.isYours)
        .map((s) => s.targetUsername)
        .whereType<String>()
        .toList();
    final reviewing = run.stages.any((s) => s.state == StageState.underReview);
    return Container(
      padding: const EdgeInsets.all(QuestSpacing.md),
      decoration: BoxDecoration(
        color: QuestColors.osSurface,
        borderRadius: BorderRadius.circular(QuestSpacing.radiusCard),
        border: Border.all(color: QuestColors.osTextPrimary, width: 2),
      ),
      child: Row(
        children: [
          Icon(reviewing ? Icons.hourglass_top_rounded : Icons.people_rounded,
              size: 18, color: QuestColors.osAccentText),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              reviewing
                  ? 'Your checkpoint is with a reviewer. You will be told the moment it clears.'
                  : waiting.isEmpty
                      ? 'Nothing to do on this journey right now.'
                      : 'You cleared your checkpoint. @${waiting.first} is up next.',
              style: QuestTypography.osBodyMedium
                  .copyWith(fontSize: 13, color: QuestColors.text(context)),
            ),
          ),
        ],
      ),
    );
  }
}

/// The any-order equivalent of the rail's transition.
class _UnlockBanner extends StatefulWidget {
  const _UnlockBanner({required this.onShown});
  final VoidCallback onShown;

  @override
  State<_UnlockBanner> createState() => _UnlockBannerState();
}

class _UnlockBannerState extends State<_UnlockBanner> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => widget.onShown());
  }

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(QuestSpacing.sm),
        decoration: BoxDecoration(
          color: QuestColors.osAccent,
          borderRadius: BorderRadius.circular(QuestSpacing.radiusCard),
          border: Border.all(color: QuestColors.osTextPrimary, width: 2),
        ),
        child: Row(
          children: [
            const Icon(Icons.lock_open_rounded,
                size: 16, color: QuestColors.osAccentInk),
            const SizedBox(width: 8),
            Text('NEW CHECKPOINT UNLOCKED',
                style: QuestTypography.osLabelSmall.copyWith(
                    fontSize: 10,
                    letterSpacing: 1.0,
                    color: QuestColors.osAccentInk)),
          ],
        ),
      );
}

class _Tag extends StatelessWidget {
  const _Tag({required this.label, required this.tint});
  final String label;
  final Color tint;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: tint,
          borderRadius: BorderRadius.circular(QuestSpacing.radiusChip),
          border: Border.all(color: QuestColors.osTextPrimary, width: 1.5),
        ),
        child: Text(label,
            style: QuestTypography.osLabelSmall.copyWith(
                fontSize: 9,
                letterSpacing: 0.8,
                color: QuestColors.onAccent(tint))),
      );
}

class _Message extends StatelessWidget {
  const _Message({required this.text, required this.onBack});
  final String text;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(text, style: QuestTypography.osBodyMedium),
            const SizedBox(height: QuestSpacing.md),
            ArcadeBackButton(onTap: onBack),
          ],
        ),
      );
}
