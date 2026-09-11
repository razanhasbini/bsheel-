import 'package:app_core/app_core.dart';
import 'package:app_models/app_models.dart';
import 'package:flutter/material.dart';

/// Completions per day across the window.
///
/// Every day the server returned is drawn, including the zeroes — that is
/// the whole reason the endpoint fills them. Omitting empty days would
/// connect last Tuesday to this Friday with a line that reads as steady
/// traffic through a week when nobody came.
///
/// Hand-drawn bars rather than a charting package: one series of at most
/// 365 integers does not justify a dependency, and a bar per day is
/// honest about granularity in a way a smoothed line is not.
class CompletionChart extends StatelessWidget {
  const CompletionChart({super.key, required this.points});

  final List<BusinessDailyPoint> points;

  @override
  Widget build(BuildContext context) {
    final peak = points.fold<int>(
        0, (max, p) => p.completions > max ? p.completions : max);
    final total = points.fold<int>(0, (sum, p) => sum + p.completions);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('$total completed',
                style: QuestTypography.osBodyMedium.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()])),
            const Spacer(),
            Text('peak $peak/day',
                style: QuestTypography.osBodySmall
                    .copyWith(color: QuestColors.textDim(context))),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 90,
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Bar heights are computed in pixels from the box we were
              // given, rather than with FractionallySizedBox.
              //
              // That is not a style choice: a fractional box inside this Row
              // is handed an unbounded height (a Row does not constrain its
              // children on the cross axis unless told to stretch), and
              // `heightFactor` against infinity throws. The chart therefore
              // crashed for any business that actually had data — which no
              // test caught while they all passed empty point lists, and
              // which compiling the web bundle cannot catch either.
              final available = constraints.maxHeight;
              // A 365-day window makes the bars hairlines; dropping the gap
              // keeps them visible rather than letting padding eat them.
              final gap = points.length > 90 ? 0.0 : 2.0;
              return Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final point in points)
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: gap / 2),
                        child: _Bar(
                          // A day with activity always draws something: a
                          // sub-pixel bar rounds away and reads as a day
                          // when nobody came.
                          height: point.completions > 0
                              ? (peak == 0
                                      ? available
                                      : available * (point.completions / peak))
                                  .clamp(3.0, available)
                              : 2.0,
                          hasActivity: point.completions > 0,
                          tooltip:
                              '${point.date}: ${point.completions} completed, '
                              '${point.visitors} visitor'
                              '${point.visitors == 1 ? '' : 's'}',
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Text(points.isEmpty ? '' : points.first.date,
                style: QuestTypography.osBodySmall
                    .copyWith(color: QuestColors.textDim(context))),
            const Spacer(),
            Text(points.isEmpty ? '' : points.last.date,
                style: QuestTypography.osBodySmall
                    .copyWith(color: QuestColors.textDim(context))),
          ],
        ),
      ],
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({
    required this.height,
    required this.hasActivity,
    required this.tooltip,
  });

  /// An explicit pixel height, already clamped by the caller against the box
  /// it measured. See the note at the call site for why this is not a
  /// fraction: a fractional box here is handed an unbounded height and
  /// throws.
  final double height;
  final bool hasActivity;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color:
              hasActivity ? QuestColors.osAccent : QuestColors.borderC(context),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
        ),
      ),
    );
  }
}
