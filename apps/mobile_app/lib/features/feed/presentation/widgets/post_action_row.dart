import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:app_core/app_core.dart';

/// The four post actions, drawn once for both surfaces that need them.
///
/// `09-feed.jpg` and `20-post-detail.jpg` draw the identical row — upvote,
/// downvote, comment, then `BSHEEEL` pushed to the right edge — so it lives
/// in one widget rather than being open-coded twice and drifting apart,
/// which is exactly what happened to the old reels rail and the detail
/// page's `_ActionPill` bar (different radii, different active colours).
///
/// Grounds, from the render:
///
/// | Chip     | Idle              | Active                        |
/// |----------|-------------------|-------------------------------|
/// | upvote   | white, flat       | violet + white label + 3px    |
/// | downvote | white, flat       | violet + white label + 3px    |
/// | comment  | white, flat       | —                             |
/// | BSHEEEL  | gold + ink + 3px  | gold, pressed-in              |
///
/// Every chip is 44pt tall and at least 44pt wide, which the spec calls out
/// as a miss on the old vote buttons.
class PostActionRow extends StatelessWidget {
  const PostActionRow({
    super.key,
    required this.upvotes,
    required this.downvotes,
    required this.commentCount,
    required this.isUpvoted,
    required this.isDownvoted,
    required this.isSaved,
    this.showVotes = true,
    this.onUpvote,
    this.onDownvote,
    this.onComment,
    this.onSave,
  });

  final int upvotes;
  final int downvotes;
  final int commentCount;
  final bool isUpvoted;
  final bool isDownvoted;
  final bool isSaved;

  /// Collab / versus posts vote per member in the participants header, so
  /// the global up/down pair is hidden there rather than duplicated.
  final bool showVotes;

  final VoidCallback? onUpvote;
  final VoidCallback? onDownvote;
  final VoidCallback? onComment;
  final VoidCallback? onSave;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (showVotes) ...[
          ArcadePostChip(
            icon: Icons.arrow_drop_up,
            label: formatCount(upvotes),
            ground: isUpvoted ? QuestColors.osPrimary : QuestColors.osCard,
            elevated: isUpvoted,
            semanticLabel: 'UPVOTE',
            onTap: onUpvote,
          ),
          const SizedBox(width: 8),
          ArcadePostChip(
            icon: Icons.arrow_drop_down,
            label: downvotes > 0 ? formatCount(downvotes) : null,
            ground: isDownvoted ? QuestColors.osPrimary : QuestColors.osCard,
            elevated: isDownvoted,
            semanticLabel: 'DOWNVOTE',
            onTap: onDownvote,
          ),
          const SizedBox(width: 8),
        ],
        ArcadePostChip(
          icon: Icons.mode_comment_outlined,
          label: commentCount > 0 ? formatCount(commentCount) : null,
          ground: QuestColors.osCard,
          semanticLabel: 'COMMENTS',
          onTap: onComment,
        ),
        const Spacer(),
        const SizedBox(width: 8),
        // Gold ground takes ink type, never white — `onAccent` decides it
        // inside the chip. Gold with white measures 1.6:1.
        Flexible(
          child: ArcadePostChip(
            label: 'BSHEEEL',
            ground: QuestColors.osAccent,
            elevated: true,
            pressedIn: isSaved,
            semanticLabel: 'BSHEEEL',
            onTap: onSave,
          ),
        ),
      ],
    );
  }
}

/// One action chip: 44pt tall, `r11`, 2px ink border, optional 3px hard
/// shadow. The ground decides the foreground via [QuestColors.onAccent] —
/// white on violet, ink on gold and on white.
class ArcadePostChip extends StatefulWidget {
  const ArcadePostChip({
    super.key,
    this.icon,
    this.label,
    required this.ground,
    required this.semanticLabel,
    this.elevated = false,
    this.pressedIn = false,
    this.onTap,
  });

  final IconData? icon;
  final String? label;
  final Color ground;

  /// Read out for the icon-only chips, which have no visible text.
  final String semanticLabel;

  /// Draws the 3px hard shadow. The render reserves it for the chips that
  /// are carrying state (an upvote you cast) or weight (`BSHEEEL`).
  final bool elevated;

  /// Already-saved `BSHEEEL` sits down on its shadow, so a post you have
  /// already bsheeeled reads as latched rather than merely tinted.
  final bool pressedIn;

  final VoidCallback? onTap;

  @override
  State<ArcadePostChip> createState() => _ArcadePostChipState();
}

class _ArcadePostChipState extends State<ArcadePostChip> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    const ink = QuestColors.osTextPrimary;
    final fg = QuestColors.onAccent(widget.ground);
    final enabled = widget.onTap != null;
    final down = _pressed || widget.pressedIn;
    final hasLabel = widget.label != null && widget.label!.isNotEmpty;

    final chip = AnimatedContainer(
      duration: const Duration(milliseconds: 70),
      transform: Matrix4.translationValues(
        0,
        widget.elevated && down ? 3 : 0,
        0,
      ),
      height: QuestSpacing.minTouchTarget,
      constraints: const BoxConstraints(
        minWidth: QuestSpacing.minTouchTarget,
      ),
      padding: EdgeInsets.symmetric(horizontal: hasLabel ? 10 : 8),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: widget.ground,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: ink, width: 2),
        boxShadow: widget.elevated && !down
            ? const [
                BoxShadow(color: ink, offset: Offset(3, 3), blurRadius: 0),
              ]
            : const [],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.icon != null) Icon(widget.icon, size: 18, color: fg),
          if (widget.icon != null && hasLabel) const SizedBox(width: 4),
          if (hasLabel)
            Flexible(
              child: Text(
                widget.label!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: QuestTypography.osLabelMedium.copyWith(
                  color: fg,
                  fontSize: 12,
                  letterSpacing: 0.6,
                ),
              ),
            ),
        ],
      ),
    );

    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
        onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
        onTapUp: enabled
            ? (_) {
                setState(() => _pressed = false);
                HapticFeedback.lightImpact();
                widget.onTap?.call();
              }
            : null,
        child: chip,
      ),
    );
  }
}

/// `1240` → `1.2K`. Counts live in a fixed-width chip, so a viral post must
/// not be the thing that overflows the action row.
String formatCount(int n) {
  if (n < 1000) return '$n';
  if (n < 10000) return '${(n / 1000).toStringAsFixed(1)}K';
  if (n < 1000000) return '${(n / 1000).round()}K';
  return '${(n / 1000000).toStringAsFixed(1)}M';
}
