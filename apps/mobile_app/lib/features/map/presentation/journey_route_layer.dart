import 'dart:math' as math;

import 'package:app_core/app_core.dart';
import 'package:app_models/app_models.dart';
import 'package:flutter/material.dart';

import '../domain/map_geometry.dart';

/// Draws a journey's checkpoints and the route between them on the map.
///
/// An overview of progression, NOT navigation: it is a line between two
/// places on a world map, so it says where the next checkpoint is in
/// relation to the last, and nothing about how to get there. Claiming
/// otherwise would be claiming turn-by-turn, which this cannot do.
///
/// Only checkpoints the server sent coordinates for are drawn. A hidden
/// checkpoint arrives without them precisely so a route cannot give away
/// where it is, and inventing a position would undo that.
class JourneyRouteLayer extends StatelessWidget {
  const JourneyRouteLayer({
    super.key,
    required this.run,
    required this.projection,
    required this.size,
    required this.progress,
  });

  final JourneyRun run;
  final MapProjection projection;
  final Size size;

  /// 0 → 1 as the newly opened leg draws itself forward.
  final double progress;

  @override
  Widget build(BuildContext context) {
    final points = <({Offset at, StageState state, bool isNext})>[];
    for (final stage in run.stages) {
      if (!stage.hasCoordinates) continue;
      points.add((
        at: projection.project(Offset(stage.longitude!, stage.latitude!)),
        state: stage.state,
        isNext: stage.isYours && stage.state == StageState.available,
      ));
    }
    // One point is not a route, and zero is not a map worth drawing on.
    if (points.length < 2) return const SizedBox.shrink();
    return CustomPaint(
      size: size,
      painter: _RoutePainter(points: points, progress: progress),
    );
  }
}

class _RoutePainter extends CustomPainter {
  const _RoutePainter({required this.points, required this.progress});

  final List<({Offset at, StageState state, bool isNext})> points;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final walked = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..color = QuestColors.osSuccess;
    final ahead = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..color = QuestColors.osTextMuted.withAlpha(120);

    for (var i = 0; i < points.length - 1; i++) {
      final from = points[i].at;
      final to = points[i + 1].at;
      final done = points[i].state == StageState.completed;
      if (!done) {
        _dashed(canvas, from, to, ahead);
        continue;
      }
      // The leg INTO the newly opened checkpoint animates; everything
      // behind it is settled history and is drawn flat.
      final growing = points[i + 1].isNext;
      final end = growing ? Offset.lerp(from, to, progress.clamp(0, 1))! : to;
      canvas.drawLine(from, end, walked);
    }

    for (final point in points) {
      final tint = switch (point.state) {
        StageState.completed => QuestColors.osSuccess,
        StageState.underReview => QuestColors.osAccent,
        StageState.available =>
          point.isNext ? QuestColors.osPrimary : QuestColors.osTextMuted,
        StageState.locked => QuestColors.osTextMuted,
      };
      // The checkpoint that just opened gets a halo, so the eye lands on the
      // one place the player can go.
      if (point.isNext) {
        canvas.drawCircle(
          point.at,
          11 + 6 * progress,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2 * (1 - progress).clamp(0.2, 1)
            ..color = QuestColors.osPrimary.withAlpha(140),
        );
      }
      canvas.drawCircle(
          point.at, 7.5, Paint()..color = QuestColors.osTextPrimary);
      canvas.drawCircle(point.at, 5.5, Paint()..color = tint);
    }
  }

  void _dashed(Canvas canvas, Offset from, Offset to, Paint paint) {
    const dash = 6.0;
    const gap = 5.0;
    final total = (to - from).distance;
    if (total == 0) return;
    final step = (to - from) / total;
    for (var travelled = 0.0; travelled < total; travelled += dash + gap) {
      final end = math.min(travelled + dash, total);
      canvas.drawLine(from + step * travelled, from + step * end, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _RoutePainter old) =>
      old.progress != progress || old.points.length != points.length;
}
