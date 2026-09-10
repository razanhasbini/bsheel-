import 'package:app_core/app_core.dart';
import 'package:app_models/app_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/backend/app_backend.dart';

/// The milestone line for a multi-step quest.
///
/// Drawn as a route rather than a checklist because that is what it is: a
/// player is somewhere along it, with ground behind them and one place they
/// can go next. A list of tickboxes would lose the thing that makes a
/// three-stop journey feel worth starting.
///
/// Every state here comes from the server. Whether a step is reachable
/// depends on *approved* proof, which only the backend has seen, so this
/// widget never decides — it draws.
final journeyProvider =
    FutureProvider.family<QuestJourney?, String>((ref, questId) async {
  return AppBackend.repositories.discovery.journey(questId);
});

class JourneyTimeline extends ConsumerWidget {
  const JourneyTimeline({super.key, required this.questId});

  final String questId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final journey = ref.watch(journeyProvider(questId));
    return journey.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      // Most quests are not part of a chain, and for those this contributes
      // nothing at all rather than an empty heading.
      data: (data) =>
          data == null ? const SizedBox.shrink() : _Timeline(journey: data),
    );
  }
}

class _Timeline extends StatelessWidget {
  const _Timeline({required this.journey});

  final QuestJourney journey;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: QuestSpacing.md),
      padding: const EdgeInsets.all(QuestSpacing.md),
      decoration: BoxDecoration(
        color: QuestColors.cardBg(context),
        borderRadius: BorderRadius.circular(QuestSpacing.radiusCard),
        border: Border.all(color: QuestColors.osTextPrimary, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  journey.name.toUpperCase(),
                  style: QuestTypography.osLabelLarge.copyWith(
                    fontSize: 14,
                    color: QuestColors.text(context),
                  ),
                ),
              ),
              Text(
                '${journey.completedSteps}/${journey.totalSteps}',
                style: QuestTypography.osLabelSmall.copyWith(
                  fontSize: 12,
                  color: QuestColors.osPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            // The two rules read very differently to a player, so they are
            // spelled out rather than left to be discovered by a refusal.
            journey.orderMatters
                ? (journey.isRelay
                    ? 'A relay. Each step opens when the one before it is approved — for whoever in the group did it.'
                    : 'Each step opens when the one before it is approved.')
                : 'Take these in any order. The journey finishes when all of them are approved.',
            style: QuestTypography.osBodySmall.copyWith(
              fontSize: 12,
              height: 1.45,
              color: QuestColors.textDim(context),
            ),
          ),
          const SizedBox(height: QuestSpacing.md),
          for (var i = 0; i < journey.milestones.length; i++)
            _MilestoneRow(
              milestone: journey.milestones[i],
              isLast: i == journey.milestones.length - 1,
            ),
        ],
      ),
    );
  }
}

class _MilestoneRow extends StatelessWidget {
  const _MilestoneRow({required this.milestone, required this.isLast});

  final JourneyMilestone milestone;
  final bool isLast;

  Color _tint() => switch (milestone.state) {
        MilestoneState.complete => QuestColors.osSuccess,
        MilestoneState.inReview => QuestColors.osAccent,
        MilestoneState.current => QuestColors.osPrimary,
        MilestoneState.locked => QuestColors.osTextMuted,
      };

  String _label() => switch (milestone.state) {
        MilestoneState.complete => 'DONE',
        MilestoneState.inReview => 'IN REVIEW',
        MilestoneState.current => 'YOU ARE HERE',
        MilestoneState.locked => 'LOCKED',
      };

  @override
  Widget build(BuildContext context) {
    final tint = _tint();
    final isCurrent = milestone.state == MilestoneState.current;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The rail: a node, and the line running down to the next one. The
          // line is dashed while it leads somewhere still locked, so the
          // route reads as unfinished at a glance.
          Column(
            children: [
              _Node(tint: tint, state: milestone.state, pulsing: isCurrent),
              if (!isLast)
                Expanded(
                  child: _Connector(
                    solid: milestone.state == MilestoneState.complete,
                    tint: milestone.state == MilestoneState.complete
                        ? QuestColors.osSuccess
                        : QuestColors.osTextMuted,
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
                      Text(
                        _label(),
                        style: QuestTypography.osLabelSmall.copyWith(
                          fontSize: 9,
                          letterSpacing: 0.8,
                          color: tint,
                        ),
                      ),
                      if (milestone.requiresLocationVerification) ...[
                        const SizedBox(width: 6),
                        Icon(Icons.cell_tower_rounded,
                            size: 11, color: QuestColors.textDim(context)),
                        const SizedBox(width: 2),
                        Text(
                          'NETWORK VERIFIED',
                          style: QuestTypography.osLabelSmall.copyWith(
                            fontSize: 9,
                            letterSpacing: 0.6,
                            color: QuestColors.textDim(context),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    // A locked step of a hidden chain keeps its secret —
                    // knowing there is another milestone is the tease.
                    milestone.title ?? 'Something waiting to be found',
                    style: QuestTypography.osBodySmall.copyWith(
                      fontSize: 13,
                      height: 1.35,
                      fontStyle: milestone.title == null
                          ? FontStyle.italic
                          : FontStyle.normal,
                      color: milestone.state == MilestoneState.locked
                          ? QuestColors.textDim(context)
                          : QuestColors.text(context),
                    ),
                  ),
                  if (milestone.placeName != null ||
                      milestone.completedBy != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        [
                          if (milestone.placeName != null) milestone.placeName!,
                          if (milestone.completedBy != null)
                            'by @${milestone.completedBy}',
                        ].join(' · '),
                        style: QuestTypography.osBodySmall.copyWith(
                          fontSize: 11,
                          color: QuestColors.textDim(context),
                        ),
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

/// The node on the rail. The current one breathes, so the eye lands on the
/// single step the player can actually act on.
class _Node extends StatefulWidget {
  const _Node({required this.tint, required this.state, required this.pulsing});

  final Color tint;
  final MilestoneState state;
  final bool pulsing;

  @override
  State<_Node> createState() => _NodeState();
}

class _NodeState extends State<_Node> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void initState() {
    super.initState();
    // Only the reachable step animates. Everything moving at once would say
    // nothing; one thing moving says "here".
    if (widget.pulsing) _controller.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant _Node old) {
    super.didUpdateWidget(old);
    if (widget.pulsing && !_controller.isAnimating) {
      _controller.repeat(reverse: true);
    } else if (!widget.pulsing && _controller.isAnimating) {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final halo = widget.pulsing ? 3.0 + _controller.value * 5.0 : 0.0;
        return SizedBox(
          width: 30,
          height: 30,
          child: Center(
            child: Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: widget.state == MilestoneState.locked
                    ? QuestColors.osSurface
                    : widget.tint,
                shape: BoxShape.circle,
                border: Border.all(color: QuestColors.osTextPrimary, width: 2),
                boxShadow: halo == 0
                    ? null
                    : [
                        BoxShadow(
                          color: widget.tint.withAlpha(90),
                          blurRadius: halo,
                          spreadRadius: halo / 2,
                        ),
                      ],
              ),
              child: Icon(
                switch (widget.state) {
                  MilestoneState.complete => Icons.check_rounded,
                  MilestoneState.inReview => Icons.hourglass_top_rounded,
                  MilestoneState.current => Icons.play_arrow_rounded,
                  MilestoneState.locked => Icons.lock_rounded,
                },
                size: 12,
                color: widget.state == MilestoneState.locked
                    ? QuestColors.osTextMuted
                    : QuestColors.onAccent(widget.tint),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The line between two nodes. Solid where the route has been walked, dashed
/// where it has not — so an unfinished journey looks unfinished.
class _Connector extends StatelessWidget {
  const _Connector({required this.solid, required this.tint});

  final bool solid;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 30,
      child: Center(
        child: CustomPaint(
          size: const Size(3, double.infinity),
          painter: _ConnectorPainter(solid: solid, tint: tint),
        ),
      ),
    );
  }
}

class _ConnectorPainter extends CustomPainter {
  const _ConnectorPainter({required this.solid, required this.tint});

  final bool solid;
  final Color tint;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = tint
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    if (solid) {
      canvas.drawLine(Offset(size.width / 2, 0),
          Offset(size.width / 2, size.height), paint);
      return;
    }
    const dash = 5.0;
    const gap = 4.0;
    for (var y = 0.0; y < size.height; y += dash + gap) {
      canvas.drawLine(
        Offset(size.width / 2, y),
        Offset(size.width / 2, (y + dash).clamp(0, size.height)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ConnectorPainter old) =>
      old.solid != solid || old.tint != tint;
}
