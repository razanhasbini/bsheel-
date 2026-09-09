import 'package:flutter/material.dart';
import 'package:app_core/app_core.dart';

import 'arcade_primitives.dart' show kArcadeMinTouchTarget;

/// Controls from section 09 of the design handoff, at the exact values drawn
/// there. Every number below is read off the component sheet rather than
/// chosen — if one looks arbitrary, that is because it is a measurement.
///
/// These live here, in `shared_ui`, because the app previously carried a
/// second private set in `lib/design/bs_widgets.dart`. Two component sets
/// means the look drifts and no single edit changes it.

// ── Toggle ────────────────────────────────────────────────────────────────
// 52 x 30, 16px radius, 22px knob inset 2, jade when on, lavender when off.

class ArcadeToggle extends StatelessWidget {
  const ArcadeToggle({super.key, required this.value, this.onChanged});

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final enabled = onChanged != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? () => onChanged!(!value) : null,
      // The painted switch is 30 tall; the hit area is 44.
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minHeight: kArcadeMinTouchTarget,
          minWidth: kArcadeMinTouchTarget,
        ),
        child: Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOut,
            width: 52,
            height: 30,
            decoration: BoxDecoration(
              color: value ? QuestColors.osSuccess : QuestColors.textSecondary,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: QuestColors.osTextPrimary, width: 2),
            ),
            child: Stack(
              children: [
                AnimatedAlign(
                  duration: const Duration(milliseconds: 140),
                  curve: Curves.easeOut,
                  alignment:
                      value ? Alignment.centerRight : Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: QuestColors.osBg,
                        borderRadius: BorderRadius.circular(11),
                        border: Border.all(
                          color: QuestColors.osTextPrimary,
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Meter ─────────────────────────────────────────────────────────────────
// 16 tall, 9px radius, 2px inner padding, gold fill at 5px radius.

class ArcadeMeter extends StatelessWidget {
  const ArcadeMeter({
    super.key,
    required this.progress,
    this.fill = QuestColors.osAccent,
    this.height = 16,
  });

  /// 0..1. Clamped, because a server total can exceed a client-side goal.
  final double progress;
  final Color fill;

  /// 16 is the sheet's meter. Overridable for the compact case — a badge
  /// row wants a slimmer bar — and the radii scale with it so a short bar
  /// does not end up looking like a rounded rectangle.
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: QuestColors.osCard,
        borderRadius: BorderRadius.circular(height / 16 * 9),
        border: Border.all(color: QuestColors.osTextPrimary, width: 2),
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: progress.clamp(0.0, 1.0),
          child: Container(
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(height / 16 * 5),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Segment meter ─────────────────────────────────────────────────────────
// Discrete version: 28 tall, 5px radius, 4px gaps. Used for rerolls.

class ArcadeSegments extends StatelessWidget {
  const ArcadeSegments({
    super.key,
    required this.total,
    required this.filled,
    this.fill = QuestColors.osPrimary,
  });

  final int total;
  final int filled;
  final Color fill;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < total; i++) ...[
          if (i > 0) const SizedBox(width: 4),
          Expanded(
            child: Container(
              height: 28,
              decoration: BoxDecoration(
                // Spent segments read lavender, never empty — an empty box
                // looks like a rendering fault next to a filled one.
                color: i < filled
                    ? fill
                    : (i == filled
                        ? QuestColors.textSecondary
                        : QuestColors.osSurface),
                borderRadius: BorderRadius.circular(5),
                border: Border.all(color: QuestColors.osTextPrimary, width: 2),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// ── Timer ─────────────────────────────────────────────────────────────────
// Mono, tabular, 30px. Under five minutes it becomes a coral chip: mono
// 13px/700 on coral, 8px radius, 5/10 padding.

class ArcadeTimer extends StatelessWidget {
  const ArcadeTimer({super.key, required this.remaining, this.urgentUnder});

  final Duration remaining;

  /// Below this, the timer switches to the coral chip. Defaults to 5 minutes,
  /// which is what the design draws.
  final Duration? urgentUnder;

  static String format(Duration d) {
    final t = d.isNegative ? Duration.zero : d;
    final h = t.inHours.toString().padLeft(2, '0');
    final m = (t.inMinutes % 60).toString().padLeft(2, '0');
    final s = (t.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final threshold = urgentUnder ?? const Duration(minutes: 5);
    final urgent = remaining <= threshold;
    // padLeft keeps the width stable as it ticks, so nothing reflows.
    final text = format(remaining);

    if (!urgent) {
      return Text(
        text,
        style: QuestTypography.labelSmall.copyWith(
          color: QuestColors.osTextPrimary,
          fontSize: 30,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
          height: 1,
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: QuestColors.osRed,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: QuestColors.osTextPrimary, width: 2),
      ),
      child: Text(
        text,
        style: QuestTypography.labelSmall.copyWith(
          color: QuestColors.onAccent(QuestColors.osRed),
          fontSize: 13,
          fontWeight: FontWeight.w700,
          height: 1,
        ),
      ),
    );
  }
}
