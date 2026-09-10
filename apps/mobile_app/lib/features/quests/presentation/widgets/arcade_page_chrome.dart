import 'package:flutter/material.dart';
import 'package:app_core/app_core.dart';
import 'package:shared_ui/shared_ui.dart';

/// Page chrome shared by the quest → proof → review screens.
///
/// All four frames (`06-quest-detail`, `07-submit-proof`,
/// `08-submission-rejected`, `19-quest-history`) draw the same two pieces:
/// a 42pt white back tile beside a mono block label, and a warm-surface
/// footer with a 2px ink top rule holding one full-width button. They were
/// open-coded four times with four different radii and paddings, which is
/// why the four screens never quite lined up.

/// The back tile: 42pt painted, `r11`, white, 2px ink, 3px ink shadow.
///
/// The paint is 42 and the hit area is 44 — the floor applies to the hit
/// box, not the pixels.
class ArcadeIconTile extends StatelessWidget {
  const ArcadeIconTile({
    super.key,
    required this.icon,
    required this.onTap,
    this.semanticLabel,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final ink = QuestColors.text(context);
    return Semantics(
      button: true,
      label: semanticLabel,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minWidth: QuestSpacing.minTouchTarget,
            minHeight: QuestSpacing.minTouchTarget,
          ),
          child: Center(
            child: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: QuestColors.osCard,
                borderRadius: BorderRadius.circular(QuestSpacing.radiusButton),
                border: Border.all(color: ink, width: 2),
                boxShadow: QuestSpacing.shadowSm,
              ),
              child: Icon(icon, color: ink, size: 20),
            ),
          ),
        ),
      ),
    );
  }
}

/// Back tile + mono block label, at the frame's `14 / 20 / 12` padding.
///
/// [trailing] is the right-hand slot the submit-proof frame fills with its
/// coral countdown chip.
class ArcadePageHeader extends StatelessWidget {
  const ArcadePageHeader({
    super.key,
    required this.title,
    required this.onBack,
    this.trailing,
    this.display = false,
  });

  final String title;
  final VoidCallback? onBack;
  final Widget? trailing;

  /// `19-quest-history` uses Syne 800 23 here instead of the mono label.
  final bool display;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        QuestSpacing.screenPadding,
        14,
        QuestSpacing.screenPadding,
        12,
      ),
      child: Row(
        children: [
          ArcadeIconTile(
            icon: Icons.arrow_back_rounded,
            onTap: onBack,
            semanticLabel: 'Back',
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Text(
              title.toUpperCase(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: display
                  ? QuestTypography.osDisplaySmall.copyWith(
                      fontSize: 23,
                      height: 1.05,
                      letterSpacing: -0.64,
                    )
                  : QuestTypography.osLabelMedium.copyWith(
                      color: QuestColors.osTextSecondary,
                      fontSize: 11,
                      letterSpacing: 1.32,
                      height: 1.25,
                    ),
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 12),
            trailing!,
          ],
        ],
      ),
    );
  }
}

/// The warm footer: `#FFF1D6`, a 2px ink top rule, `14 / 20 / 28` padding.
///
/// The bottom inset grows to clear a home indicator, because 28 is the
/// frame's value on a device that has none.
class ArcadeStickyFooter extends StatelessWidget {
  const ArcadeStickyFooter({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final ink = QuestColors.text(context);
    final inset = MediaQuery.viewPaddingOf(context).bottom;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        QuestSpacing.screenPadding,
        14,
        QuestSpacing.screenPadding,
        inset > 28 ? inset : 28,
      ),
      decoration: BoxDecoration(
        color: QuestColors.osSurface,
        border: Border(top: BorderSide(color: ink, width: 2)),
      ),
      child: child,
    );
  }
}

/// Inline failure state: a mono label, a sentence, and a retry button.
///
/// Local rather than `ArcadeErrorState` because that one paints white on
/// coral, which measures 3.03:1 and fails AA. On an accent ground the text
/// is ink — `QuestColors.onAccent` — without exception.
class ArcadeInlineError extends StatelessWidget {
  const ArcadeInlineError({
    super.key,
    required this.title,
    required this.subtitle,
    required this.onRetry,
  });

  final String title;
  final String subtitle;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final ink = QuestColors.text(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: QuestColors.osRed,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: ink, width: 2),
            ),
            child: Text(
              title.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: QuestTypography.osLabelMedium.copyWith(
                color: QuestColors.onAccent(QuestColors.osRed),
                fontSize: 10,
                letterSpacing: 1.1,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: QuestTypography.osBodyMedium.copyWith(
              color: QuestColors.osTextSecondary,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 16),
          ArcadeButton(
            label: 'RETRY',
            variant: ArcadeButtonVariant.secondary,
            size: ArcadeButtonSize.small,
            expand: false,
            onTap: onRetry,
          ),
        ],
      ),
    );
  }
}

/// A 2px dashed outline in [color] around [child].
///
/// The frames use it for exactly two things — an expired quest and a
/// suspended account — so it means "inert", never "empty". Flutter has no
/// dashed [Border], hence the painter.
class ArcadeDashedBox extends StatelessWidget {
  const ArcadeDashedBox({
    super.key,
    required this.child,
    required this.radius,
    this.color = QuestColors.osTextMuted,
    this.fill = QuestColors.osSurface,
  });

  final Widget child;
  final double radius;
  final Color color;
  final Color fill;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: CustomPaint(
        painter: _DashedRRectPainter(color: color, radius: radius),
        child: child,
      ),
    );
  }
}

class _DashedRRectPainter extends CustomPainter {
  const _DashedRRectPainter({required this.color, required this.radius});

  final Color color;
  final double radius;

  /// Fixed geometry. The dashed outline means one thing, so a second
  /// rhythm would only make two inert things look like two states.
  static const double _dash = 6;
  static const double _gap = 4;
  static const double _stroke = 2;

  @override
  void paint(Canvas canvas, Size size) {
    final outline = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            _stroke / 2,
            _stroke / 2,
            size.width - _stroke,
            size.height - _stroke,
          ),
          Radius.circular(radius),
        ),
      );
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = _stroke;

    for (final metric in outline.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = (distance + _dash).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance = end + _gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedRRectPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.radius != radius;
}

/// The diagonal cream hatch the frames use behind every media placeholder.
///
/// `repeating-linear-gradient(135deg, #FFF1D6 0 10px, #FFF9EE 10px 20px)`,
/// painted rather than tiled so it stays crisp at any size.
class ArcadeHatch extends StatelessWidget {
  const ArcadeHatch({super.key, this.child});
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: const _HatchPainter(),
      child: child ?? const SizedBox.expand(),
    );
  }
}

class _HatchPainter extends CustomPainter {
  const _HatchPainter();

  /// 10px band, 20px period, at 135°. Read off the frame's gradient.
  static const double _band = 10;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = QuestColors.osBg,
    );
    final stripe = Paint()
      ..color = QuestColors.osSurface
      ..style = PaintingStyle.stroke
      ..strokeWidth = _band;

    // 135° in CSS runs top-left → bottom-right, so the bands themselves are
    // perpendicular to that: lines from bottom-left to top-right.
    final span = size.width + size.height;
    for (var d = -size.height; d < span; d += _band * 2) {
      canvas.drawLine(
        Offset(d, 0),
        Offset(d + size.height, size.height),
        stripe,
      );
    }
  }

  @override
  bool shouldRepaint(_HatchPainter oldDelegate) => false;
}
