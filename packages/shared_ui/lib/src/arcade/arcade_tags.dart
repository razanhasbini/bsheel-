import 'package:flutter/material.dart';
import 'package:app_core/app_core.dart';

/// Category tags and status pills.
///
/// These two are deliberately different *shapes*, not just different colours:
/// a category tag is a soft square, a status pill is fully round. The shape
/// tells them apart before the text does, which matters on a feed row where
/// both appear side by side and colour is already carrying meaning.
///
/// They were previously open-coded per page, so the distinction drifted and
/// the same status rendered with a different radius in two places.

/// Radius that makes a tag read as a square rather than a pill.
const double kArcadeTagRadius = 8;

/// A quest category, tinted by its own colour. Soft square.
class ArcadeCategoryTag extends StatelessWidget {
  const ArcadeCategoryTag({
    super.key,
    required this.label,
    required this.tint,
    this.compact = false,
  });

  /// The category name. Rendered upper case — it is a label, not a sentence.
  final String label;

  /// The category's tint, normally from `QuestColors.category(...)`.
  final Color tint;

  /// Tighter padding for dense rows.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 8,
        vertical: compact ? 2 : 4,
      ),
      decoration: BoxDecoration(
        color: tint,
        borderRadius: BorderRadius.circular(kArcadeTagRadius),
        border: Border.all(color: QuestColors.osTextPrimary, width: 2),
      ),
      child: Text(
        label.toUpperCase(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: QuestTypography.labelSmall.copyWith(
          // The tint is the ground, so the helper decides the ink. Coral and
          // jade in particular look dark enough for white and are not.
          color: QuestColors.onAccent(tint),
          fontSize: compact ? 9 : 10,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

/// A review or account status. Fully round.
class ArcadeStatusPill extends StatelessWidget {
  const ArcadeStatusPill({
    super.key,
    required this.label,
    required this.tint,
    this.compact = false,
  });

  final String label;

  /// The status colour — jade approved, coral rejected, gold waiting,
  /// violet in-progress. Colour carries meaning here, never decoration.
  final Color tint;

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 2 : 4,
      ),
      decoration: BoxDecoration(
        color: tint,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: QuestColors.osTextPrimary, width: 2),
      ),
      child: Text(
        label.toUpperCase(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: QuestTypography.labelSmall.copyWith(
          color: QuestColors.onAccent(tint),
          fontSize: compact ? 9 : 10,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}
