import 'package:flutter/material.dart';

import 'package:app_core/app_core.dart';

// ── Touch targets ─────────────────────────────────────────────────────────────

/// 44pt — the minimum touch target the design spec mandates (section 1,
/// "44pt minimum on every touch target").
///
/// Not a mobile-only floor, as this once assumed: the admin spec mandates the
/// same 44 for pointer input, because a moderator works a queue for hours.
/// So the value lives in [QuestSpacing.minTouchTarget] and this is an alias.
const double kMinTouchTarget = QuestSpacing.minTouchTarget;

/// Grows the hit area of [child] to at least [kMinTouchTarget] on both axes
/// while leaving the painted size untouched, so a deliberately small chip or
/// icon stays visually small but is still comfortably tappable.
///
/// Wrap the *child* of the gesture detector, not the other way round:
/// ```dart
/// GestureDetector(
///   onTap: ...,
///   behavior: HitTestBehavior.opaque,
///   child: const BsMinTouch(child: _TinyIcon()),
/// )
/// ```
class BsMinTouch extends StatelessWidget {
  const BsMinTouch({
    super.key,
    required this.child,
    this.minWidth = kMinTouchTarget,
    this.minHeight = kMinTouchTarget,
  });

  final Widget child;
  final double minWidth;
  final double minHeight;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(minWidth: minWidth, minHeight: minHeight),
      child: Center(widthFactor: 1, heightFactor: 1, child: child),
    );
  }
}

// ── Accent as type on cream ───────────────────────────────────────────────────

/// Maps an accent *fill* to the darkened twin that is legible as small type
/// on cream or white.
///
/// The Arcade Pop accents are tuned to be read as grounds with ink on top;
/// used directly as text on cream they fall under 4.5:1 (coral 2.9:1, jade
/// 2.2:1, gold 1.6:1). Violet and sky have no darkened twin in the palette,
/// so violet passes as-is and sky falls back to ink.
Color accentAsTextOnCream(Color accent) {
  if (accent == QuestColors.osRed || accent == QuestColors.osRed) {
    return QuestColors.osRedText;
  }
  if (accent == QuestColors.osSuccess || accent == QuestColors.osSuccess) {
    return QuestColors.osSuccessText;
  }
  if (accent == QuestColors.osAccent || accent == QuestColors.accentYellow) {
    return QuestColors.osAccentText;
  }
  if (accent == QuestColors.osCool) return QuestColors.osTextPrimary;
  return accent;
}

// ── ChunkyCard ────────────────────────────────────────────────────────────────

class ChunkyCard extends StatelessWidget {
  final Widget child;
  final Color? tint;
  final EdgeInsetsGeometry padding;
  final double radius;
  final bool shadow;
  final VoidCallback? onTap;

  const ChunkyCard({
    super.key,
    required this.child,
    this.tint,
    this.padding = const EdgeInsets.all(14),
    this.radius = 22,
    this.shadow = true,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final deco = BoxDecoration(
      color: tint ?? QuestColors.osCard,
      border: Border.all(
          color: QuestColors.osTextPrimary,
          width: QuestSpacing.cardBorderWidth),
      borderRadius: BorderRadius.circular(radius),
      boxShadow: shadow
          ? [
              const BoxShadow(
                  color: QuestColors.osTextPrimary,
                  offset: QuestSpacing.hardShadowOffset)
            ]
          : null,
    );
    Widget w = Container(decoration: deco, padding: padding, child: child);
    if (onTap != null) {
      w = InkWell(
          onTap: onTap, borderRadius: BorderRadius.circular(radius), child: w);
    }
    return w;
  }
}

// ── ChunkyButton ──────────────────────────────────────────────────────────────

enum ChunkyVariant { primary, accent, surface }

class ChunkyButton extends StatefulWidget {
  final String label;
  final VoidCallback? onPressed;
  final ChunkyVariant variant;
  final Widget? leading;
  final bool full;
  final double fontSize;
  final EdgeInsetsGeometry padding;

  const ChunkyButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = ChunkyVariant.primary,
    this.leading,
    this.full = false,
    this.fontSize = 16,
    this.padding = const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
  });

  @override
  State<ChunkyButton> createState() => _ChunkyButtonState();
}

class _ChunkyButtonState extends State<ChunkyButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    late Color bg, fg;
    switch (widget.variant) {
      case ChunkyVariant.primary:
        bg = QuestColors.osPrimary;
        fg = QuestColors.osTextOnPrimary;
        break;
      case ChunkyVariant.accent:
        bg = QuestColors.osAccent;
        fg = QuestColors.osAccentInk;
        break;
      case ChunkyVariant.surface:
        bg = QuestColors.osCard;
        fg = QuestColors.osTextPrimary;
        break;
    }

    final child = AnimatedContainer(
      duration: const Duration(milliseconds: 60),
      padding: widget.padding,
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(
            color: QuestColors.osTextPrimary,
            width: QuestSpacing.cardBorderWidth),
        borderRadius: BorderRadius.circular(18),
        boxShadow: _pressed
            ? []
            : [
                const BoxShadow(
                    color: QuestColors.osTextPrimary,
                    offset: QuestSpacing.hardShadowOffset)
              ],
      ),
      transform: Matrix4.translationValues(0, _pressed ? 5 : 0, 0),
      alignment: Alignment.center,
      child: Row(
        mainAxisSize: widget.full ? MainAxisSize.max : MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (widget.leading != null) ...[
            widget.leading!,
            const SizedBox(width: 10)
          ],
          Flexible(
            child: Text(
              widget.label.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Syne',
                fontVariations: const [FontVariation('wght', 800)],
                fontWeight: FontWeight.w800,
                fontSize: widget.fontSize,
                letterSpacing: 0.3,
                color: fg,
              ),
            ),
          ),
        ],
      ),
    );

    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onPressed,
      child:
          widget.full ? SizedBox(width: double.infinity, child: child) : child,
    );
  }
}

// ── BsChip ────────────────────────────────────────────────────────────────────

class BsChip extends StatelessWidget {
  final String label;
  final Widget? leading;
  final Color? bg;
  final Color? fg;
  final Color? border;
  const BsChip(
      {super.key,
      required this.label,
      this.leading,
      this.bg,
      this.fg,
      this.border});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg ?? QuestColors.osPrimary.withAlpha(30),
        borderRadius: BorderRadius.circular(999),
        border: border != null ? Border.all(color: border!, width: 1.5) : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: 6)],
          Flexible(
            child: Text(
              label.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'DMSans',
                fontVariations: const [FontVariation('wght', 500)],
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
                color: fg ?? QuestColors.osPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── XpBar ─────────────────────────────────────────────────────────────────────

class BsXpBar extends StatelessWidget {
  final double progress;
  final double height;
  final Color? fillColor;
  const BsXpBar({
    super.key,
    required this.progress,
    this.height = 12,
    this.fillColor,
  });

  @override
  Widget build(BuildContext context) {
    final fill = fillColor ?? QuestColors.osPrimary;
    return SizedBox(
      width: double.infinity,
      height: height,
      child: Stack(
        children: [
          // Fixed-size track — always spans full width regardless of progress.
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: QuestColors.osSurface,
                border: Border.all(
                    color: QuestColors.osTextPrimary,
                    width: QuestSpacing.cardBorderWidth),
                borderRadius: BorderRadius.circular(height / 1.5),
              ),
            ),
          ),
          // Solid fill, clipped inside the track. No gradient, no stripes.
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(height / 1.5),
              child: LayoutBuilder(builder: (ctx, box) {
                final w = box.maxWidth * progress.clamp(0.0, 1.0);
                if (w <= 0) return const SizedBox.shrink();
                return Align(
                  alignment: Alignment.centerLeft,
                  child: Container(width: w, color: fill),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Section header ────────────────────────────────────────────────────────────

class BsSectionHeader extends StatelessWidget {
  final String label;
  const BsSectionHeader(this.label, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 0, 10),
      child: Row(children: [
        Container(width: 20, height: 2, color: QuestColors.osTextPrimary),
        const SizedBox(width: 8),
        Flexible(
          child: Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontFamily: 'Syne',
                  fontVariations: [FontVariation('wght', 800)],
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: QuestColors.osTextPrimary,
                  letterSpacing: 0.5)),
        ),
        const SizedBox(width: 8),
        Flexible(
            child: Container(
                height: 2, color: QuestColors.osTextPrimary.withAlpha(38))),
      ]),
    );
  }
}

// ── BsSegBar ──────────────────────────────────────────────────────────────────

class BsSegBar extends StatelessWidget {
  final List<String> options;
  final String value;
  final ValueChanged<String> onChange;
  final bool small;

  const BsSegBar({
    super.key,
    required this.options,
    required this.value,
    required this.onChange,
    this.small = false,
  });

  @override
  Widget build(BuildContext context) {
    // Separate chips, not a segmented group in a shared container. The
    // renders draw each option as its own outlined pill - the selected one
    // ink with cream text, the rest white with an ink outline - which is the
    // same treatment as the settings language chips and the notification
    // filters. Wrap so a long option set cannot overflow a narrow phone.
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: options.map((o) {
        final active = o == value;
        return GestureDetector(
          onTap: () => onChange(o),
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            constraints:
                BoxConstraints(minHeight: small ? 36 : kMinTouchTarget),
            padding: EdgeInsets.symmetric(
              vertical: small ? 6 : 10,
              horizontal: small ? 12 : 16,
            ),
            decoration: BoxDecoration(
              color: active ? QuestColors.osTextPrimary : QuestColors.osCard,
              borderRadius: BorderRadius.circular(11),
              border: Border.all(
                color: QuestColors.osTextPrimary,
                width: QuestSpacing.cardBorderWidth,
              ),
            ),
            alignment: Alignment.center,
            child: Text(o.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'Syne',
                  fontVariations: const [FontVariation('wght', 800)],
                  fontSize: small ? 11 : 12,
                  fontWeight: FontWeight.w800,
                  color: active ? QuestColors.osBg : QuestColors.osTextPrimary,
                  letterSpacing: 0.4,
                )),
          ),
        );
      }).toList(),
    );
  }
}

// ── BsToggle (chunky switch) ──────────────────────────────────────────────────

class BsToggle extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  const BsToggle({super.key, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      behavior: HitTestBehavior.opaque,
      child: BsMinTouch(
        minWidth: 48,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 48,
          height: 28,
          decoration: BoxDecoration(
            color: value ? QuestColors.osPrimary : QuestColors.osSurface,
            border: Border.all(
                color: QuestColors.osTextPrimary,
                width: QuestSpacing.cardBorderWidth),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Stack(children: [
            AnimatedAlign(
              duration: const Duration(milliseconds: 150),
              alignment: value ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                margin: const EdgeInsets.all(2),
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: QuestColors.osAccent,
                  border:
                      Border.all(color: QuestColors.osTextPrimary, width: 1.5),
                  borderRadius: BorderRadius.circular(11),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
