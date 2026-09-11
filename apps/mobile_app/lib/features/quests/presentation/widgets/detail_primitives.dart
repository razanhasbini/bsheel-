import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';

/// The shared vocabulary of a detail screen.
///
/// Lifted out of `quest_details_page.dart` when the journey page needed the
/// same furniture. They were private, and the alternative was a second set
/// that looked almost-but-not-quite the same — which is how one app ends up
/// with two detail systems that drift apart a tweak at a time.

class BlockLabel extends StatelessWidget {
  const BlockLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: QuestTypography.osLabelMedium.copyWith(
        color: QuestColors.osTextSecondary,
        fontSize: 11,
        letterSpacing: 1.32,
      ),
    );
  }
}

// ── Stat chip ──────────────────────────────────────────────────────────────

/// `r12`, 2px ink, 3px ink shadow, 10/11 padding. Label mono 8, value
/// Syne 700 15 — or mono 14 for the countdown, which must not reflow.

class StatChip extends StatelessWidget {
  const StatChip({
    super.key,
    required this.label,
    required this.value,
    required this.tint,
    this.mono = false,
  });

  final String label;
  final String value;
  final Color tint;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    final ink = QuestColors.text(context);
    // Derived from the fill: violet takes white, gold takes osAccentInk,
    // everything else ink. Never alpha-muted on an accent ground.
    final fg = QuestColors.onAccent(tint);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
      decoration: BoxDecoration(
        color: tint,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ink, width: 2),
        boxShadow: QuestSpacing.shadowSm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: QuestTypography.osLabelSmall.copyWith(
              color: fg,
              fontSize: 8,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 1),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              value,
              maxLines: 1,
              style: mono
                  ? QuestTypography.osLabelMedium.copyWith(
                      color: fg,
                      fontSize: 14,
                      letterSpacing: 0,
                      height: 1.2,
                    )
                  : QuestTypography.osHeadlineMedium.copyWith(
                      color: fg,
                      fontSize: 15,
                      height: 1.2,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Criteria / requirement row ─────────────────────────────────────────────

/// An 18pt square with a 5px radius and a 2px ink outline, jade when the
/// item is satisfied and warm cream when it is not, then the sentence in
/// normal case. The frame draws no card around these.

class CheckRow extends StatelessWidget {
  const CheckRow({super.key, required this.text, required this.met});
  final String text;
  final bool met;

  @override
  Widget build(BuildContext context) {
    final ink = QuestColors.text(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color: met ? QuestColors.osSuccess : QuestColors.osSurface,
              borderRadius: BorderRadius.circular(QuestSpacing.radiusDot),
              border: Border.all(color: ink, width: 2),
            ),
          ),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            text,
            style: QuestTypography.osBodyMedium.copyWith(
              color:
                  met ? QuestColors.osTextPrimary : QuestColors.osTextSecondary,
              fontSize: 14,
              height: 1.5,
            ),
          ),
        ),
      ],
    );
  }
}

// ── Loading skeleton ───────────────────────────────────────────────────────
