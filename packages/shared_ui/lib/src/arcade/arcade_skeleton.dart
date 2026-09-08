import 'package:flutter/material.dart';
import 'package:app_core/app_core.dart';

/// Loading placeholders.
///
/// The design spec is specific about this: **skeletons, never a spinner**, and
/// they keep the 2px border so the page's structure is already correct before
/// the data lands. A spinner tells you to wait; a skeleton tells you what is
/// coming and stops the layout jumping when it arrives.
///
/// That last part is the reason these are shared rather than open-coded. There
/// were four separate skeleton implementations across the two apps, and a
/// placeholder whose shape does not match the real row reintroduces exactly
/// the jump it exists to prevent.

/// A single skeleton block: bordered, muted, gently pulsing.
class ArcadeSkeleton extends StatefulWidget {
  const ArcadeSkeleton({
    super.key,
    this.width,
    this.height = 16,
    this.radius = 8,
    this.bordered = true,
  });

  /// Null means "fill the available width".
  final double? width;
  final double height;
  final double radius;

  /// Row- and card-shaped placeholders keep the 2px outline. Small inline
  /// blocks standing in for a word or a number do not, since a border around
  /// a text-sized block reads as a control rather than as text.
  final bool bordered;

  @override
  State<ArcadeSkeleton> createState() => _ArcadeSkeletonState();
}

class _ArcadeSkeletonState extends State<ArcadeSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    duration: const Duration(milliseconds: 1100),
    vsync: this,
  )..repeat(reverse: true);

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
        // A slow opacity pulse, not a shimmer sweep: the sweep is a gradient
        // animation on every frame for every block, and it competes with the
        // hard-edged look of everything around it.
        final t = Curves.easeInOut.transform(_controller.value);
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            // Muted violet-grey, per the spec — a neutral grey reads as a
            // disabled control on this cream ground.
            color: QuestColors.osTextMuted.withAlpha((60 + 40 * t).round()),
            borderRadius: BorderRadius.circular(widget.radius),
            border: widget.bordered
                ? Border.all(
                    color: QuestColors.osTextMuted.withAlpha(140),
                    width: 2,
                  )
                : null,
          ),
        );
      },
    );
  }
}

/// A list of card-shaped skeletons, for a list that has not loaded.
///
/// [itemHeight] should match the real row so nothing shifts on load.
class ArcadeSkeletonList extends StatelessWidget {
  const ArcadeSkeletonList({
    super.key,
    this.itemCount = 4,
    this.itemHeight = 76,
    this.spacing = 10,
    this.padding = EdgeInsets.zero,
  });

  final int itemCount;
  final double itemHeight;
  final double spacing;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Column(
        children: [
          for (var i = 0; i < itemCount; i++) ...[
            if (i > 0) SizedBox(height: spacing),
            ArcadeSkeleton(height: itemHeight, radius: 12),
          ],
        ],
      ),
    );
  }
}
