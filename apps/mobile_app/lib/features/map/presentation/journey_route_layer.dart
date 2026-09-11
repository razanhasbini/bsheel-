import 'package:app_core/app_core.dart';
import 'package:app_models/app_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

/// Draws the visible part of a journey over the live map.
///
/// This is deliberately an overview, not turn-by-turn navigation. Hidden
/// checkpoints arrive without coordinates and therefore cannot leak through
/// the route overlay.
class JourneyRouteLayer extends StatelessWidget {
  const JourneyRouteLayer({
    super.key,
    required this.run,
    this.progress = 1,
  });

  final JourneyRun run;

  /// 0 → 1 as the newly opened leg draws itself forward.
  final double progress;

  @override
  Widget build(BuildContext context) {
    final stages = run.stages.where((stage) => stage.hasCoordinates).toList();
    if (stages.length < 2) return const SizedBox.shrink();

    final lines = <Polyline>[];
    for (var index = 0; index < stages.length - 1; index++) {
      final fromStage = stages[index];
      final toStage = stages[index + 1];
      final from = LatLng(fromStage.latitude!, fromStage.longitude!);
      final destination = LatLng(toStage.latitude!, toStage.longitude!);
      final isNewLeg = fromStage.state == StageState.completed &&
          toStage.isYours &&
          toStage.state == StageState.available;
      final fraction = isNewLeg ? progress.clamp(0.0, 1.0) : 1.0;
      final to = LatLng(
        from.latitude + (destination.latitude - from.latitude) * fraction,
        from.longitude + (destination.longitude - from.longitude) * fraction,
      );
      final completed = fromStage.state == StageState.completed;
      lines.add(Polyline(
        points: [from, to],
        strokeWidth: completed ? 3 : 2.5,
        color: completed
            ? QuestColors.osSuccess
            : QuestColors.osTextMuted.withAlpha(120),
      ));
    }

    return Stack(
      children: [
        PolylineLayer(polylines: lines),
        MarkerLayer(
          markers: [
            for (final stage in stages)
              Marker(
                point: LatLng(stage.latitude!, stage.longitude!),
                width: 34,
                height: 34,
                child: _CheckpointMarker(
                  state: stage.state,
                  isNext: stage.isYours && stage.state == StageState.available,
                  progress: progress,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _CheckpointMarker extends StatelessWidget {
  const _CheckpointMarker({
    required this.state,
    required this.isNext,
    required this.progress,
  });

  final StageState state;
  final bool isNext;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final tint = switch (state) {
      StageState.completed => QuestColors.osSuccess,
      StageState.underReview => QuestColors.osAccent,
      // A checkpoint under way is the one to walk to, so it reads like the
      // next one rather than like a pin you have not reached.
      StageState.inProgress => QuestColors.osPrimary,
      StageState.available =>
        isNext ? QuestColors.osPrimary : QuestColors.osTextMuted,
      StageState.locked => QuestColors.osTextMuted,
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isNext
            ? QuestColors.osPrimary.withAlpha(
                (40 + 80 * progress.clamp(0.0, 1.0)).round(),
              )
            : Colors.transparent,
      ),
      child: Center(
        child: Container(
          width: 15,
          height: 15,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: tint,
            border: Border.all(color: QuestColors.osTextPrimary, width: 2),
          ),
        ),
      ),
    );
  }
}
