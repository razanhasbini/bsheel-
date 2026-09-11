import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

/// One headline figure.
///
/// [note] carries the caveat that belongs to the number rather than to the
/// screen — "5 not disclosed", "below reporting threshold". A figure whose
/// limits live in a legend somewhere else gets quoted without them.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    this.note,
    this.tint,
  });

  final String label;
  final String value;
  final String? note;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    return ArcadeCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label.toUpperCase(),
              style: QuestTypography.osLabelSmall
                  .copyWith(color: QuestColors.textDim(context))),
          const SizedBox(height: 8),
          Text(
            value,
            // Tabular figures so a column of these lines up instead of
            // shifting with every digit.
            style: QuestTypography.osHeadlineMedium.copyWith(
              color: tint ?? QuestColors.text(context),
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          if (note != null) ...[
            const SizedBox(height: 6),
            Text(note!,
                style: QuestTypography.osBodySmall
                    .copyWith(color: QuestColors.textDim(context))),
          ],
        ],
      ),
    );
  }
}

/// A section heading with an optional one-line explanation of what the
/// figures below it do and do not include.
class SectionHeading extends StatelessWidget {
  const SectionHeading({super.key, required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title.toUpperCase(), style: QuestTypography.osLabelSmall),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(subtitle!,
              style: QuestTypography.osBodySmall
                  .copyWith(color: QuestColors.textDim(context))),
        ],
        const SizedBox(height: 12),
      ],
    );
  }
}

/// What a section shows when it has nothing yet — distinct from an error,
/// and worded so an owner can tell which it is.
class EmptyNote extends StatelessWidget {
  const EmptyNote({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(text,
          style: QuestTypography.osBodySmall
              .copyWith(color: QuestColors.textDim(context))),
    );
  }
}

/// A failed read, with the retry that fixes it.
///
/// Every section owns one of these rather than the page owning a single
/// error state: one endpoint failing must not blank the other five, which
/// is what a page-level error does.
class SectionError extends StatelessWidget {
  const SectionError({super.key, required this.onRetry, this.message});

  final VoidCallback onRetry;
  final String? message;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            message ?? 'Could not load this section.',
            style:
                QuestTypography.osBodySmall.copyWith(color: QuestColors.osRed),
          ),
        ),
        const SizedBox(width: 12),
        ArcadeButton(
          label: 'RETRY',
          variant: ArcadeButtonVariant.ghost,
          size: ArcadeButtonSize.small,
          expand: false,
          onTap: onRetry,
        ),
      ],
    );
  }
}
