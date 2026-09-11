import 'dart:math' as math;

import 'package:app_core/app_core.dart';
import 'package:app_models/app_models.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Remembers how far along each chain a player had got the last time they
/// looked, so the app can tell "a step was approved since you were last
/// here" from "this is simply where you are".
///
/// It has to be persisted rather than held in memory: approval happens while
/// the app is closed — a moderator decides at their own pace — so the
/// comparison that matters spans launches. SharedPreferences, because losing
/// it costs one missed celebration, not correctness.
///
/// Keyed by chain and not by quest: the same advance is the same event
/// whichever step of the chain the player opens it from.
abstract final class CheckpointMemory {
  static String _key(String chainId) => 'journey_progress_$chainId';

  /// The advance to celebrate, or null when nothing moved.
  ///
  /// Returns null the very first time a chain is seen even if steps are
  /// already complete — a player who joins a relay mid-way did not just
  /// clear those steps, and congratulating them for someone else's work is
  /// worse than saying nothing.
  static Future<int?> advanceSince(QuestJourney journey) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final seen = prefs.getInt(_key(journey.chainId));
      await prefs.setInt(_key(journey.chainId), journey.completedSteps);
      if (seen == null) return null;
      return journey.completedSteps > seen ? journey.completedSteps : null;
    } catch (_) {
      // A device that cannot read prefs still gets a working journey; it
      // just never gets the fanfare.
      return null;
    }
  }
}

/// The moment a step is approved and the next one opens.
///
/// Shown as a full-screen overlay rather than folded into the timeline
/// because that is the shape of the event: a checkpoint on a route is
/// something you arrive at, and the line drawing itself forward is the whole
/// payload. Inline, it would be a number quietly changing from 1 to 2.
///
/// Everything here is driven by server state. The client never decides a step
/// opened — it is told, and this draws what it was told.
class CheckpointReachedOverlay extends StatefulWidget {
  const CheckpointReachedOverlay({
    super.key,
    required this.journey,
    required this.reachedStep,
  });

  final QuestJourney journey;

  /// How many steps are complete now. The node that just filled.
  final int reachedStep;

  /// Plays the celebration over whatever is on screen, and returns when the
  /// player dismisses it.
  static Future<void> show(
    BuildContext context, {
    required QuestJourney journey,
    required int reachedStep,
  }) {
    return Navigator.of(context, rootNavigator: true).push(
      PageRouteBuilder<void>(
        opaque: false,
        barrierColor: QuestColors.osTextPrimary.withAlpha(214),
        barrierDismissible: true,
        transitionDuration: const Duration(milliseconds: 260),
        pageBuilder: (_, __, ___) => CheckpointReachedOverlay(
          journey: journey,
          reachedStep: reachedStep,
        ),
        transitionsBuilder: (_, animation, __, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  @override
  State<CheckpointReachedOverlay> createState() =>
      _CheckpointReachedOverlayState();
}

class _CheckpointReachedOverlayState extends State<CheckpointReachedOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2100),
  )..forward();

  /// The line runs first, then the node lands, then the text arrives. Three
  /// beats rather than one, so the eye follows the route instead of being
  /// shown a finished picture.
  late final Animation<double> _line = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.0, 0.45, curve: Curves.easeInOutCubic),
  );
  late final Animation<double> _land = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.42, 0.68, curve: Curves.elasticOut),
  );
  late final Animation<double> _burst = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.5, 0.95, curve: Curves.easeOutCubic),
  );
  late final Animation<double> _copy = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.62, 0.9, curve: Curves.easeOut),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// The step that just opened, when there is one. Null on the last
  /// checkpoint, where the honest headline is that the journey is finished.
  JourneyMilestone? get _next {
    for (final m in widget.journey.milestones) {
      if (m.stepOrder == widget.reachedStep + 1) return m;
    }
    return null;
  }

  bool get _isFinale => widget.reachedStep >= widget.journey.totalSteps;

  @override
  Widget build(BuildContext context) {
    final next = _next;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(QuestSpacing.lg),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedBuilder(
                    animation: _controller,
                    builder: (context, _) => SizedBox(
                      height: 132,
                      child: CustomPaint(
                        size: const Size(double.infinity, 132),
                        painter: _CheckpointPainter(
                          totalSteps: widget.journey.totalSteps,
                          reachedStep: widget.reachedStep,
                          lineProgress: _line.value,
                          landProgress: _land.value.clamp(0.0, 1.6),
                          burstProgress: _burst.value,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: QuestSpacing.lg),
                  FadeTransition(
                    opacity: _copy,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, 0.24),
                        end: Offset.zero,
                      ).animate(_copy),
                      child: Column(
                        children: [
                          Text(
                            _isFinale
                                ? 'JOURNEY COMPLETE'
                                : 'CHECKPOINT REACHED',
                            textAlign: TextAlign.center,
                            style: QuestTypography.osDisplayLarge.copyWith(
                              fontSize: 30,
                              height: 1.0,
                              letterSpacing: -1.0,
                              color: QuestColors.osBg,
                            ),
                          ),
                          const SizedBox(height: QuestSpacing.sm),
                          Text(
                            widget.journey.name.toUpperCase(),
                            textAlign: TextAlign.center,
                            style: QuestTypography.osLabelSmall.copyWith(
                              fontSize: 11,
                              letterSpacing: 1.2,
                              color: QuestColors.osAccent,
                            ),
                          ),
                          const SizedBox(height: QuestSpacing.md),
                          Text(
                            _isFinale
                                ? 'Every step verified. That is the whole route walked.'
                                : next?.title != null
                                    ? 'Step ${widget.reachedStep} approved. '
                                        'Next up: ${next!.title}'
                                    : 'Step ${widget.reachedStep} approved. '
                                        'The next one just opened.',
                            textAlign: TextAlign.center,
                            style: QuestTypography.osBodyMedium.copyWith(
                              height: 1.5,
                              color: QuestColors.osBg.withAlpha(214),
                            ),
                          ),
                          if (!_isFinale &&
                              next != null &&
                              next.requiresLocationVerification) ...[
                            const SizedBox(height: QuestSpacing.sm),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.cell_tower_rounded,
                                    size: 13, color: QuestColors.osCool),
                                const SizedBox(width: 5),
                                Text(
                                  'YOUR CARRIER VERIFIES THIS ONE',
                                  style: QuestTypography.osLabelSmall.copyWith(
                                    fontSize: 9,
                                    letterSpacing: 0.8,
                                    color: QuestColors.osCool,
                                  ),
                                ),
                              ],
                            ),
                          ],
                          const SizedBox(height: QuestSpacing.xl),
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: Text(
                              _isFinale ? 'NICE' : 'KEEP GOING',
                              style: QuestTypography.osHeadlineSmall.copyWith(
                                fontSize: 15,
                                letterSpacing: 1.0,
                                color: QuestColors.osAccent,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The route, drawn horizontally: nodes for every step, and the line running
/// forward into the one just reached.
class _CheckpointPainter extends CustomPainter {
  const _CheckpointPainter({
    required this.totalSteps,
    required this.reachedStep,
    required this.lineProgress,
    required this.landProgress,
    required this.burstProgress,
  });

  final int totalSteps;
  final int reachedStep;

  /// 0 → 1 as the line grows from the previous node to the reached one.
  final double lineProgress;

  /// The elastic settle of the node itself, overshooting past 1.
  final double landProgress;

  /// 0 → 1 as the ring expands and fades outward.
  final double burstProgress;

  @override
  void paint(Canvas canvas, Size size) {
    if (totalSteps <= 0) return;
    final y = size.height / 2;
    // Margins keep the end nodes off the edges at any width, including the
    // 400px-wide phone this has to survive on.
    const margin = 26.0;
    final usable = math.max(size.width - margin * 2, 1.0);
    double x(int step) => totalSteps == 1
        ? size.width / 2
        : margin + usable * ((step - 1) / (totalSteps - 1));

    final dim = QuestColors.osBg.withAlpha(64);
    const done = QuestColors.osSuccess;

    // Everything behind the reached node is already walked, and is drawn
    // flat — the animation belongs to the one segment that just changed.
    final track = Paint()
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..color = dim;
    canvas.drawLine(Offset(x(1), y), Offset(x(totalSteps), y), track);

    final walked = Paint()
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..color = done;
    if (reachedStep > 1) {
      final from = x(1);
      final settled = x(reachedStep - 1);
      canvas.drawLine(Offset(from, y), Offset(settled, y), walked);
      // The growing segment: from the previous checkpoint to this one.
      final to = settled + (x(reachedStep) - settled) * lineProgress;
      canvas.drawLine(Offset(settled, y), Offset(to, y), walked);
    } else {
      canvas.drawLine(
        Offset(x(1) - 10, y),
        Offset(x(1), y),
        walked,
      );
    }

    // The burst: a ring leaving the node as it lands.
    if (burstProgress > 0) {
      final ring = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3 * (1 - burstProgress)
        ..color = QuestColors.osAccent
            .withAlpha((160 * (1 - burstProgress)).round().clamp(0, 255));
      canvas.drawCircle(
          Offset(x(reachedStep), y), 14 + 30 * burstProgress, ring);
    }

    for (var step = 1; step <= totalSteps; step++) {
      final reached = step <= reachedStep;
      final isThisOne = step == reachedStep;
      final scale = isThisOne ? landProgress.clamp(0.0, 1.5) : 1.0;
      final radius = (step == reachedStep + 1 ? 9.0 : 8.0) * scale;
      if (radius <= 0) continue;
      canvas.drawCircle(
        Offset(x(step), y),
        radius + 2.5,
        Paint()..color = QuestColors.osTextPrimary,
      );
      canvas.drawCircle(
        Offset(x(step), y),
        radius,
        Paint()
          ..color = reached
              ? done
              : (step == reachedStep + 1 ? QuestColors.osAccent : dim),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CheckpointPainter old) =>
      old.lineProgress != lineProgress ||
      old.landProgress != landProgress ||
      old.burstProgress != burstProgress ||
      old.reachedStep != reachedStep;
}
