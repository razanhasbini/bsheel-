import 'package:app_core/app_core.dart' show timeAgo;
import 'package:flutter/material.dart';

import '../../core/theme/bsheel_design.dart';

/// Arcade Pop primitives for the admin console.
///
/// Every surface here carries a 2px ink outline and, where it matters, a
/// hard zero-blur offset shadow. Shadow depth is the weight scale:
/// 3px cards and small buttons · 4px stat tiles and primary buttons ·
/// 5px tables · 6px hero panels. A *coloured* shadow marks the one item in
/// a list that needs attention; everything else takes ink.
///
/// Pressing a shadowed control slides it into its own shadow, which is the
/// whole feedback mechanism — there is no ripple.
///
/// Colour carries meaning and nothing else: jade approves, coral rejects,
/// gold marks anything waiting on a person, violet is navigation and the
/// primary action.
///
/// Text on coral, gold, jade and sky is always ink — never white. Use
/// [BsheelColors.onAccent] rather than choosing by hand.

// ── Pressable ───────────────────────────────────────────────────────

/// Slides [child] into its shadow on press. [depth] must match the
/// shadow the child draws, so the surface lands exactly where the shadow
/// was.
class BsheelPressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double depth;
  final String? tooltip;

  const BsheelPressable({
    super.key,
    required this.child,
    this.onTap,
    this.depth = 3,
    this.tooltip,
  });

  @override
  State<BsheelPressable> createState() => _BsheelPressableState();
}

class _BsheelPressableState extends State<BsheelPressable> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    Widget out = AnimatedContainer(
      duration: const Duration(milliseconds: 70),
      curve: Curves.easeOut,
      transform: Matrix4.translationValues(
        _down ? widget.depth : 0,
        _down ? widget.depth : 0,
        0,
      ),
      child: widget.child,
    );

    if (widget.tooltip != null) {
      out = Tooltip(message: widget.tooltip!, child: out);
    }

    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onTapDown: enabled ? (_) => setState(() => _down = true) : null,
        onTapUp: enabled ? (_) => setState(() => _down = false) : null,
        onTapCancel: () => setState(() => _down = false),
        child: out,
      ),
    );
  }
}

// ── Card ────────────────────────────────────────────────────────────

/// White card, 2px ink outline, hard shadow. Pass [shadowColor] to mark
/// the one row in a list that needs attention.
class BsheelCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final double radius;
  final double depth;
  final Color shadowColor;
  final VoidCallback? onTap;
  final bool dashed;

  const BsheelCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.color,
    this.radius = BsheelRadii.card,
    this.depth = 4,
    this.shadowColor = BsheelColors.ink,
    this.onTap,
    this.dashed = false,
  });

  /// No shadow — for a card nested inside another shadowed surface.
  const BsheelCard.flat({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(13),
    this.color,
    this.radius = BsheelRadii.card,
    this.onTap,
    this.dashed = false,
  })  : depth = 0,
        shadowColor = BsheelColors.ink;

  /// Dashed muted outline, no shadow — hidden, retired or unavailable.
  const BsheelCard.muted({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(13),
    this.radius = BsheelRadii.card,
    this.onTap,
  })  : color = BsheelColors.surface,
        depth = 0,
        shadowColor = BsheelColors.ink,
        dashed = true;

  @override
  Widget build(BuildContext context) {
    final surface = dashed
        ? _DashedBox(
            radius: radius,
            color: color ?? BsheelColors.surface,
            child: Padding(padding: padding, child: child),
          )
        : Container(
            padding: padding,
            decoration: BoxDecoration(
              color: color ?? BsheelColors.card,
              borderRadius: BorderRadius.circular(radius),
              border: const Border.fromBorderSide(BsheelBorders.inkSide),
              boxShadow: depth > 0
                  ? BsheelShadows.hard(depth, color: shadowColor)
                  : null,
            ),
            child: child,
          );

    if (onTap == null) return surface;
    return BsheelPressable(onTap: onTap, depth: depth, child: surface);
  }
}

/// Dashed 2px muted outline. Flutter has no dashed `Border`, so this
/// paints one.
class _DashedBox extends StatelessWidget {
  final Widget child;
  final double radius;
  final Color color;

  const _DashedBox({
    required this.child,
    required this.radius,
    this.color = BsheelColors.surface,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DashedBorderPainter(
        radius: radius,
        color: BsheelColors.inkMuted,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(radius),
        ),
        child: child,
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  final double radius;
  final Color color;

  const _DashedBorderPainter({required this.radius, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = BsheelBorders.thick
      ..style = PaintingStyle.stroke;
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    // 6-on / 4-off, walked along the rounded rect.
    for (final metric in (Path()..addRRect(rrect)).computeMetrics()) {
      double d = 0;
      while (d < metric.length) {
        final end = (d + 6).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(d, end), paint);
        d += 10;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter old) =>
      old.radius != radius || old.color != color;
}

// ── Labels ──────────────────────────────────────────────────────────

/// Tracked mono label. ALL CAPS, four words or fewer.
class BsheelLabel extends StatelessWidget {
  final String text;
  final Color? color;
  final double? size;

  const BsheelLabel(this.text, {super.key, this.color, this.size});

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: BsheelType.labelMd.copyWith(
        color: color ?? BsheelColors.inkSoft,
        fontSize: size,
      ),
    );
  }
}

/// Section eyebrow. Kept under the old name; the em-dash prefix the port
/// direction used is gone — Arcade Pop tracks the caps instead.
class BsheelEyebrow extends StatelessWidget {
  final String text;
  final Color? color;

  const BsheelEyebrow(this.text, {super.key, this.color});

  @override
  Widget build(BuildContext context) => BsheelLabel(text, color: color);
}

/// Page or card title. `{braces}` in [text] used to mark an italic accent
/// in the previous direction; Arcade Pop has no italic accent, so the
/// braces are stripped and the whole title renders in Syne.
class BsheelDisplay extends StatelessWidget {
  final String text;
  final TextStyle baseStyle;

  const BsheelDisplay(
    this.text, {
    super.key,
    this.baseStyle = BsheelType.displayMd,
  });

  @override
  Widget build(BuildContext context) {
    return Text(
      text.replaceAll('{', '').replaceAll('}', ''),
      style: baseStyle,
    );
  }
}

// ── Page header ─────────────────────────────────────────────────────

/// The bar at the top of every page: cream surface, 2px ink rule beneath,
/// Syne title on the left, meta and actions on the right.
class BsheelPageHeader extends StatelessWidget {
  final String title;
  final String? meta;
  final Color? metaColor;
  final List<Widget> actions;

  const BsheelPageHeader({
    super.key,
    required this.title,
    this.meta,
    this.metaColor,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      constraints: const BoxConstraints(minHeight: BsheelLayout.headerHeight),
      decoration: const BoxDecoration(
        color: BsheelColors.surface,
        border: Border(bottom: BsheelBorders.inkSide),
      ),
      child: Row(
        children: [
          // The sidebar collapses to a drawer below the tablet breakpoint,
          // so the header carries the only way back to it.
          if (Scaffold.maybeOf(context)?.hasDrawer ?? false) ...[
            Builder(
              builder: (context) => Padding(
                padding: const EdgeInsets.only(right: 12),
                child: BsheelIconButton(
                  icon: Icons.menu_rounded,
                  tooltip: 'Menu',
                  size: 40,
                  onTap: () => Scaffold.of(context).openDrawer(),
                ),
              ),
            ),
          ],
          Expanded(
            child: Text(
              title.toUpperCase(),
              style: BsheelType.displayMd,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (meta != null) ...[
            const SizedBox(width: 12),
            Flexible(
              child: BsheelLabel(
                meta!,
                color: metaColor ?? BsheelColors.inkSoft,
              ),
            ),
          ],
          for (final action in actions) ...[
            const SizedBox(width: 10),
            action,
          ],
        ],
      ),
    );
  }
}

/// Eyebrow + display headline pair, for panes that need a heading inside
/// the scroll area rather than in the header bar.
class BsheelSectionHeader extends StatelessWidget {
  final String title;
  final String? emphasis;
  final String? eyebrow;
  final String? actionLabel;
  final VoidCallback? onAction;

  const BsheelSectionHeader({
    super.key,
    required this.title,
    this.emphasis,
    this.eyebrow,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (eyebrow != null) ...[
            BsheelLabel(eyebrow!),
            const SizedBox(height: 8),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Text(
                  [
                    title.replaceAll('{', '').replaceAll('}', ''),
                    if (emphasis != null) emphasis!,
                  ].join(' ').toUpperCase(),
                  style: BsheelType.displayMd,
                ),
              ),
              if (actionLabel != null) BsheelLink(actionLabel!, onTap: onAction),
            ],
          ),
        ],
      ),
    );
  }
}

/// Violet tracked-mono text link.
class BsheelLink extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final TextAlign? align;

  const BsheelLink(this.label, {super.key, this.onTap, this.align});

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: onTap == null ? MouseCursor.defer : SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Text(
          label.toUpperCase(),
          textAlign: align,
          style: BsheelType.labelMd.copyWith(color: BsheelColors.primary),
        ),
      ),
    );
  }
}

// ── Pills and tags ──────────────────────────────────────────────────

/// Tone names are carried over from the previous direction so existing
/// call sites keep compiling; they now resolve to Arcade Pop accents.
enum BsheelPillTone { ink, gold, coral, violet, green, sky, ghost, paper }

extension BsheelPillToneColor on BsheelPillTone {
  Color get ground => switch (this) {
        BsheelPillTone.ink => BsheelColors.ink,
        BsheelPillTone.gold => BsheelColors.accent,
        BsheelPillTone.coral => BsheelColors.danger,
        BsheelPillTone.violet => BsheelColors.primary,
        BsheelPillTone.green => BsheelColors.success,
        BsheelPillTone.sky => BsheelColors.cool,
        BsheelPillTone.ghost => BsheelColors.surface,
        BsheelPillTone.paper => BsheelColors.card,
      };
}

/// Status pill — fully round. Shape is what separates it from a category
/// tag, before you read the text.
class BsheelPill extends StatelessWidget {
  final String label;
  final BsheelPillTone tone;
  final bool small;
  final bool dashed;

  const BsheelPill(
    this.label, {
    super.key,
    this.tone = BsheelPillTone.paper,
    this.small = false,
    this.dashed = false,
  });

  /// Expired / retired / unavailable — dashed muted outline on cream.
  const BsheelPill.muted(this.label, {super.key, this.small = false})
      : tone = BsheelPillTone.ghost,
        dashed = true;

  /// Resolves a submission or account status to its pill.
  factory BsheelPill.status(String status, {bool small = true}) {
    final tone = switch (status.toLowerCase()) {
      'approved' || 'active' || 'live' || 'invited' || 'visible' =>
        BsheelPillTone.green,
      'rejected' || 'banned' || 'flagged' || 'deleted' => BsheelPillTone.coral,
      'pending' || 'in review' || 'waiting' || 'suspended' || 'appeal' =>
        BsheelPillTone.gold,
      're-rejected' || 'final' => BsheelPillTone.ink,
      'expired' || 'retired' => BsheelPillTone.ghost,
      _ => BsheelPillTone.paper,
    };
    if (tone == BsheelPillTone.ghost) {
      return BsheelPill.muted(status, small: small);
    }
    return BsheelPill(status, tone: tone, small: small);
  }

  @override
  Widget build(BuildContext context) {
    final ground = tone.ground;
    final label0 = Text(
      label.toUpperCase(),
      style: BsheelType.labelSm.copyWith(
        color: dashed ? BsheelColors.inkSoft : BsheelColors.onAccent(ground),
        fontSize: small ? 9 : 10,
        letterSpacing: 0.7,
      ),
    );
    final padding = EdgeInsets.symmetric(
      horizontal: small ? 8 : 10,
      vertical: small ? 3 : 4,
    );

    if (dashed) {
      return _DashedBox(
        radius: BsheelRadii.full,
        color: BsheelColors.surface,
        child: Padding(padding: padding, child: label0),
      );
    }

    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: ground,
        borderRadius: BorderRadius.circular(BsheelRadii.full),
        border: const Border.fromBorderSide(BsheelBorders.inkSide),
      ),
      child: label0,
    );
  }
}

/// Category tag — 8px radius square. Tinted by the quest category so the
/// colour is consistent with the mobile app.
class BsheelTag extends StatelessWidget {
  final String label;
  final Color? ground;

  const BsheelTag(this.label, {super.key, this.ground});

  /// Tag tinted from a quest category string.
  BsheelTag.category(String category, {super.key})
      : label = category,
        ground = BsheelColors.category(category);

  @override
  Widget build(BuildContext context) {
    final bg = ground ?? BsheelColors.card;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: const Border.fromBorderSide(BsheelBorders.inkSide),
      ),
      child: Text(
        label.toUpperCase(),
        style: BsheelType.labelSm.copyWith(
          color: BsheelColors.onAccent(bg),
          fontSize: 10,
        ),
      ),
    );
  }
}

// ── Buttons ─────────────────────────────────────────────────────────

/// Arcade Pop button. Primary carries a 4px shadow, secondary 3px, and a
/// disabled button loses its shadow and takes a dashed border so it reads
/// as unavailable rather than merely dim.
class BsheelButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final BsheelPillTone tone;
  final bool small;
  final bool loading;
  final bool ghost;
  final bool expand;
  final double? height;

  /// Retained for call-site compatibility; [tone] wins when both are set.
  final Color? background;
  final Color? foreground;

  const BsheelButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.tone = BsheelPillTone.violet,
    this.small = false,
    this.loading = false,
    this.ghost = false,
    this.expand = false,
    this.height,
    this.background,
    this.foreground,
  });

  /// Primary action — violet, white label, 4px shadow.
  const BsheelButton.primary({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.small = false,
    this.loading = false,
    this.expand = false,
    this.height,
  })  : tone = BsheelPillTone.violet,
        ghost = false,
        background = null,
        foreground = null;

  /// Approve — jade, ink label.
  const BsheelButton.positive({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.small = false,
    this.loading = false,
    this.expand = false,
    this.height,
  })  : tone = BsheelPillTone.green,
        ghost = false,
        background = null,
        foreground = null;

  /// Reject, ban, remove — coral, ink label.
  const BsheelButton.coral({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.small = false,
    this.loading = false,
    this.expand = false,
    this.height,
  })  : tone = BsheelPillTone.coral,
        ghost = false,
        background = null,
        foreground = null;

  /// Anything waiting on a person — gold, ink label.
  const BsheelButton.gold({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.small = false,
    this.loading = false,
    this.expand = false,
    this.height,
  })  : tone = BsheelPillTone.gold,
        ghost = false,
        background = null,
        foreground = null;

  /// Legacy alias — resolves to [BsheelButton.primary].
  const BsheelButton.violet({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.small = false,
    this.loading = false,
    this.expand = false,
    this.height,
  })  : tone = BsheelPillTone.violet,
        ghost = false,
        background = null,
        foreground = null;

  /// Secondary — cream ground, ink label, 3px shadow.
  const BsheelButton.ghost({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.small = false,
    this.loading = false,
    this.expand = false,
    this.height,
  })  : tone = BsheelPillTone.ghost,
        ghost = true,
        background = null,
        foreground = null;

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null || loading;
    final ground = background ?? tone.ground;
    final fg = foreground ?? BsheelColors.onAccent(ground);

    // Primary weight carries 4px; secondary and small carry 3px.
    final depth = (tone == BsheelPillTone.ghost || small) ? 3.0 : 4.0;
    final h = height ?? (small ? BsheelLayout.minTarget : 50.0);
    final hPad = small ? 14.0 : 18.0;
    final textStyle = (small ? BsheelType.buttonSm : BsheelType.buttonMd);

    final content = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (loading)
          SizedBox(
            width: 15,
            height: 15,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation(
                disabled ? BsheelColors.inkMuted : fg,
              ),
            ),
          )
        else if (icon != null) ...[
          Icon(
            icon,
            size: small ? 15 : 17,
            color: disabled ? BsheelColors.inkMuted : fg,
          ),
          const SizedBox(width: 8),
        ],
        if (!loading)
          Flexible(
            child: Text(
              label.toUpperCase(),
              style: textStyle.copyWith(
                color: disabled ? BsheelColors.inkSoft : fg,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
      ],
    );

    // Disabled: dashed muted border, cream ground, no shadow.
    if (disabled) {
      final box = _DashedBox(
        radius: BsheelRadii.md,
        color: BsheelColors.surface,
        child: SizedBox(
          height: h,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: hPad),
            child: Center(child: content),
          ),
        ),
      );
      return expand ? SizedBox(width: double.infinity, child: box) : box;
    }

    final box = Container(
      height: h,
      padding: EdgeInsets.symmetric(horizontal: hPad),
      decoration: BoxDecoration(
        color: ground,
        borderRadius: BorderRadius.circular(BsheelRadii.md),
        border: const Border.fromBorderSide(BsheelBorders.inkSide),
        boxShadow: BsheelShadows.hard(depth),
      ),
      alignment: Alignment.center,
      child: content,
    );

    return BsheelPressable(
      onTap: onPressed,
      depth: depth,
      child: expand ? SizedBox(width: double.infinity, child: box) : box,
    );
  }
}

/// Square icon button with the same press behaviour.
class BsheelIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final Color ground;
  final String? tooltip;
  final String? badge;
  final double size;

  const BsheelIconButton({
    super.key,
    required this.icon,
    this.onTap,
    this.ground = BsheelColors.card,
    this.tooltip,
    this.badge,
    this.size = BsheelLayout.minTarget,
  });

  @override
  Widget build(BuildContext context) {
    final btn = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: ground,
        borderRadius: BorderRadius.circular(BsheelRadii.sm),
        border: const Border.fromBorderSide(BsheelBorders.inkSide),
        boxShadow: BsheelShadows.sm,
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: 18, color: BsheelColors.onAccent(ground)),
    );

    return BsheelPressable(
      onTap: onTap,
      depth: 3,
      tooltip: tooltip,
      child: badge == null
          ? btn
          : Stack(
              clipBehavior: Clip.none,
              children: [
                btn,
                Positioned(
                  top: -6,
                  right: -6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: BsheelColors.danger,
                      borderRadius: BorderRadius.circular(BsheelRadii.full),
                      border:
                          const Border.fromBorderSide(BsheelBorders.inkSide),
                    ),
                    child: Text(
                      badge!,
                      style: BsheelType.labelSm.copyWith(
                        color: BsheelColors.ink,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

// ── Stat tile ───────────────────────────────────────────────────────

/// Dashboard stat tile — accent ground, tracked mono label, big Syne
/// numeral, mono footnote. 4px shadow.
class BsheelStatTile extends StatelessWidget {
  final String label;
  final String value;
  final String? footnote;
  final Color ground;
  final VoidCallback? onTap;

  const BsheelStatTile({
    super.key,
    required this.label,
    required this.value,
    this.footnote,
    this.ground = BsheelColors.card,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final fg = BsheelColors.onAccent(ground);
    // On an accent ground every line is full-opacity ink; on white the
    // label and footnote soften to inkSoft.
    final metaColor = ground == BsheelColors.card ? BsheelColors.inkSoft : fg;

    return BsheelCard(
      color: ground,
      radius: BsheelRadii.lg,
      depth: 4,
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(17, 15, 17, 15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label.toUpperCase(),
            style: BsheelType.labelMd.copyWith(color: metaColor, fontSize: 10),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 3),
          Text(value, style: BsheelType.displayXl.copyWith(color: fg)),
          if (footnote != null) ...[
            const SizedBox(height: 3),
            Text(
              footnote!.toUpperCase(),
              style: BsheelType.labelMd.copyWith(
                color: metaColor,
                fontSize: 10,
                letterSpacing: 0.4,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}

/// Legacy name for [BsheelStatTile], mapped to the old parameter list.
class BsheelTile extends StatelessWidget {
  final String eyebrow;
  final String value;
  final String? delta;
  final Color? deltaColor;
  final Color color;
  final Color foreground;
  final VoidCallback? onTap;

  const BsheelTile({
    super.key,
    required this.eyebrow,
    required this.value,
    this.delta,
    this.deltaColor,
    this.color = BsheelColors.card,
    this.foreground = BsheelColors.ink,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) => BsheelStatTile(
        label: eyebrow,
        value: value,
        footnote: delta,
        ground: color,
        onTap: onTap,
      );
}

// ── Callout ─────────────────────────────────────────────────────────

/// Banner that states a consequence. Coral for a fault or a block, gold
/// for something waiting on a person, jade for a confirmation.
class BsheelCallout extends StatelessWidget {
  final String message;
  final BsheelPillTone tone;
  final Widget? trailing;
  final List<InlineSpan>? richMessage;

  const BsheelCallout(
    this.message, {
    super.key,
    this.tone = BsheelPillTone.gold,
    this.trailing,
    this.richMessage,
  });

  const BsheelCallout.danger(
    this.message, {
    super.key,
    this.trailing,
    this.richMessage,
  }) : tone = BsheelPillTone.coral;

  const BsheelCallout.warning(
    this.message, {
    super.key,
    this.trailing,
    this.richMessage,
  }) : tone = BsheelPillTone.gold;

  const BsheelCallout.positive(
    this.message, {
    super.key,
    this.trailing,
    this.richMessage,
  }) : tone = BsheelPillTone.green;

  @override
  Widget build(BuildContext context) {
    final ground = tone.ground;
    final fg = BsheelColors.onAccent(ground);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      decoration: BoxDecoration(
        color: ground,
        borderRadius: BorderRadius.circular(BsheelRadii.md),
        border: const Border.fromBorderSide(BsheelBorders.inkSide),
        boxShadow: BsheelShadows.sm,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '!',
            style: BsheelType.displayXs.copyWith(color: fg, fontSize: 15),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: richMessage != null
                ? Text.rich(
                    TextSpan(children: richMessage),
                    style: BsheelType.bodySmMedium.copyWith(color: fg),
                  )
                : Text(
                    message,
                    style: BsheelType.bodySmMedium.copyWith(color: fg),
                  ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 10),
            trailing!,
          ],
        ],
      ),
    );
  }
}

// ── Table ───────────────────────────────────────────────────────────

/// One column in a [BsheelTable]. A null [width] flexes to fill.
class BsheelColumn {
  final String label;
  final double? width;

  const BsheelColumn(this.label, {this.width});
}

/// Table wrapped in a 2px ink outline with a 5px shadow. The header row
/// sits on cream with a 2px rule beneath; body rows are separated by the
/// only 1px hairline in the system.
class BsheelTable extends StatelessWidget {
  final List<BsheelColumn> columns;
  final List<BsheelRow> rows;
  final double depth;
  final double gap;

  const BsheelTable({
    super.key,
    required this.columns,
    required this.rows,
    this.depth = 5,
    this.gap = 12,
  });

  List<Widget> _cells(List<Widget> children) {
    final out = <Widget>[];
    for (var i = 0; i < columns.length; i++) {
      final child = i < children.length ? children[i] : const SizedBox();
      final w = columns[i].width;
      out.add(
        w == null
            ? Expanded(child: child)
            : SizedBox(width: w, child: child),
      );
      if (i != columns.length - 1) out.add(SizedBox(width: gap));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: BsheelColors.card,
        borderRadius: BorderRadius.circular(BsheelRadii.lg),
        border: const Border.fromBorderSide(BsheelBorders.inkSide),
        boxShadow: depth > 0 ? BsheelShadows.hard(depth) : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: const BoxDecoration(
              color: BsheelColors.surface,
              border: Border(bottom: BsheelBorders.inkSide),
            ),
            child: Row(
              children: _cells([
                for (final c in columns)
                  Text(
                    c.label.toUpperCase(),
                    style: BsheelType.labelSm.copyWith(letterSpacing: 1.1),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ]),
            ),
          ),
          for (var i = 0; i < rows.length; i++)
            _BsheelTableRow(
              row: rows[i],
              cells: _cells(rows[i].cells),
              last: i == rows.length - 1,
            ),
        ],
      ),
    );
  }
}

/// A body row. [muted] greys the row for retired or inactive records.
class BsheelRow {
  final List<Widget> cells;
  final VoidCallback? onTap;
  final bool muted;

  const BsheelRow(this.cells, {this.onTap, this.muted = false});
}

class _BsheelTableRow extends StatefulWidget {
  final BsheelRow row;
  final List<Widget> cells;
  final bool last;

  const _BsheelTableRow({
    required this.row,
    required this.cells,
    required this.last,
  });

  @override
  State<_BsheelTableRow> createState() => _BsheelTableRowState();
}

class _BsheelTableRowState extends State<_BsheelTableRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final bg = widget.row.muted
        ? BsheelColors.surface
        : (_hover && widget.row.onTap != null
            ? BsheelColors.surface
            : BsheelColors.card);

    return MouseRegion(
      cursor: widget.row.onTap == null
          ? MouseCursor.defer
          : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.row.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: bg,
            border: widget.last
                ? null
                : const Border(bottom: BsheelBorders.rowSide),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: widget.cells,
          ),
        ),
      ),
    );
  }
}

/// Table-cell helpers, so pages don't restate the type each time.
abstract final class BsheelCell {
  /// Row title — 13px DM Sans medium, ellipsised.
  static Widget title(String text, {bool muted = false}) => Text(
        text,
        style: BsheelType.bodySmMedium.copyWith(
          color: muted ? BsheelColors.inkMuted : BsheelColors.ink,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );

  /// Mono datum — id, username, count.
  static Widget mono(String text, {Color? color, bool bold = true}) => Text(
        text,
        style: BsheelType.monoMd.copyWith(
          color: color ?? BsheelColors.ink,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );

  /// Quieter mono datum — timestamps, moderator names.
  static Widget meta(String text, {Color? color}) => Text(
        text,
        style: BsheelType.monoSm.copyWith(color: color ?? BsheelColors.inkSoft),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );

  /// Tracked mono label inside a cell.
  static Widget label(String text, {Color? color}) => Text(
        text.toUpperCase(),
        style: BsheelType.labelSm.copyWith(
          color: color ?? BsheelColors.inkSoft,
          fontSize: 10,
          letterSpacing: 0.7,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );

  /// Left-aligned pill, so it doesn't stretch to the column width.
  static Widget pill(Widget pill) =>
      Align(alignment: Alignment.centerLeft, child: pill);
}

// ── Key / value rail ────────────────────────────────────────────────

/// Detail-rail panel: label on the left, mono value on the right, 1px
/// hairlines between rows.
class BsheelKeyValues extends StatelessWidget {
  final List<BsheelKeyValue> entries;
  final Color shadowColor;
  final double depth;

  const BsheelKeyValues({
    super.key,
    required this.entries,
    this.shadowColor = BsheelColors.ink,
    this.depth = 3,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13),
      decoration: BoxDecoration(
        color: BsheelColors.card,
        borderRadius: BorderRadius.circular(BsheelRadii.card),
        border: const Border.fromBorderSide(BsheelBorders.inkSide),
        boxShadow: BsheelShadows.hard(depth, color: shadowColor),
      ),
      child: Column(
        children: [
          for (var i = 0; i < entries.length; i++)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 9),
              decoration: i == entries.length - 1
                  ? null
                  : const BoxDecoration(
                      border: Border(bottom: BsheelBorders.rowSide),
                    ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      entries[i].label,
                      style: BsheelType.bodySm.copyWith(
                        color: BsheelColors.inkSoft,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    entries[i].value,
                    style: BsheelType.monoMd.copyWith(
                      color: entries[i].emphasis ?? BsheelColors.ink,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class BsheelKeyValue {
  final String label;
  final String value;

  /// Set for a value that needs to read as a fault, e.g. `SPENT`.
  final Color? emphasis;

  const BsheelKeyValue(this.label, this.value, {this.emphasis});
}

// ── Toggle row ──────────────────────────────────────────────────────

/// A trigger or feature flag: mono key, plain-language consequence, and
/// the switch. Wrap several in a [BsheelCard.flat] to get one panel.
class BsheelToggleRow extends StatelessWidget {
  final String name;
  final String description;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final bool monoName;
  final bool last;

  const BsheelToggleRow({
    super.key,
    required this.name,
    required this.description,
    required this.value,
    this.onChanged,
    this.monoName = true,
    this.last = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: last
          ? null
          : const BoxDecoration(border: Border(bottom: BsheelBorders.rowSide)),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  monoName ? name : name.toUpperCase(),
                  style: monoName ? BsheelType.monoMd : BsheelType.titleMd,
                ),
                const SizedBox(height: 2),
                Text(description, style: BsheelType.bodyXs),
              ],
            ),
          ),
          const SizedBox(width: 12),
          BsheelSwitch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

/// 50×28 switch — jade when on, lavender when off, cream knob, 2px ink.
class BsheelSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;

  const BsheelSwitch({super.key, required this.value, this.onChanged});

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: onChanged == null ? MouseCursor.defer : SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onChanged == null ? null : () => onChanged!(!value),
        // Keeps the row's hit area at 44px without changing the visual.
        child: SizedBox(
          height: BsheelLayout.minTarget,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 130),
              curve: Curves.easeOut,
              width: 50,
              height: 28,
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: value ? BsheelColors.success : BsheelColors.lavender,
                borderRadius: BorderRadius.circular(BsheelRadii.full),
                border: const Border.fromBorderSide(BsheelBorders.inkSide),
              ),
              alignment:
                  value ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: BsheelColors.bg,
                  borderRadius: BorderRadius.circular(BsheelRadii.full),
                  border: const Border.fromBorderSide(BsheelBorders.inkSide),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Filter chips ────────────────────────────────────────────────────

/// One filter option. [count] is appended to the label, and [ground]
/// tints the chip when it should carry a category or status colour.
class BsheelFilter {
  final String value;
  final String label;
  final int? count;
  final Color? ground;
  final bool dashed;

  const BsheelFilter(
    this.value,
    this.label, {
    this.count,
    this.ground,
    this.dashed = false,
  });
}

/// Chip row. The selected chip inverts to ink; unselected chips keep
/// their own ground, or white.
class BsheelFilterChips extends StatelessWidget {
  final List<BsheelFilter> filters;
  final String selected;
  final ValueChanged<String> onChanged;

  const BsheelFilterChips({
    super.key,
    required this.filters,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final f in filters)
          _Chip(
            filter: f,
            active: f.value == selected,
            onTap: () => onChanged(f.value),
          ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  final BsheelFilter filter;
  final bool active;
  final VoidCallback onTap;

  const _Chip({
    required this.filter,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final ground = active
        ? BsheelColors.ink
        : (filter.ground ?? BsheelColors.card);
    final label = filter.count == null
        ? filter.label.toUpperCase()
        : '${filter.label.toUpperCase()} ${filter.count}';
    final text = Text(
      label,
      style: BsheelType.labelSm.copyWith(
        color: filter.dashed && !active
            ? BsheelColors.inkSoft
            : BsheelColors.onAccent(ground),
        letterSpacing: 0.9,
      ),
    );
    const padding = EdgeInsets.symmetric(horizontal: 10, vertical: 5);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        // 44px hit target without inflating the chip.
        child: SizedBox(
          height: BsheelLayout.minTarget,
          child: Center(
            child: filter.dashed && !active
                ? _DashedBox(
                    radius: BsheelRadii.full,
                    color: BsheelColors.card,
                    child: Padding(padding: padding, child: text),
                  )
                : Container(
                    padding: padding,
                    decoration: BoxDecoration(
                      color: ground,
                      borderRadius: BorderRadius.circular(BsheelRadii.full),
                      border:
                          const Border.fromBorderSide(BsheelBorders.inkSide),
                    ),
                    child: text,
                  ),
          ),
        ),
      ),
    );
  }
}

/// Pill-shaped segmented control, kept for existing call sites.
class BsheelSegmented extends StatelessWidget {
  final List<String> options;
  final int selected;
  final ValueChanged<int>? onChanged;

  const BsheelSegmented({
    super.key,
    required this.options,
    required this.selected,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return BsheelFilterChips(
      filters: [
        for (var i = 0; i < options.length; i++)
          BsheelFilter('$i', options[i]),
      ],
      selected: '$selected',
      onChanged: (v) => onChanged?.call(int.parse(v)),
    );
  }
}

// ── Meter ───────────────────────────────────────────────────────────

/// Gold meter in an ink-outlined track — 16px tall, 2px inner padding.
class BsheelProgress extends StatelessWidget {
  final double value;
  final Color fill;
  final double height;

  const BsheelProgress({
    super.key,
    required this.value,
    this.fill = BsheelColors.accent,
    this.height = 16,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: BsheelColors.card,
        borderRadius: BorderRadius.circular(BsheelRadii.sm),
        border: const Border.fromBorderSide(BsheelBorders.inkSide),
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: value.clamp(0.0, 1.0),
          child: Container(
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(5),
            ),
          ),
        ),
      ),
    );
  }
}

/// Vertical bar chart — inactive bars lavender, emphasised bars violet,
/// the latest bar gold.
class BsheelBarChart extends StatelessWidget {
  final List<double> values;
  final int? highlightLast;
  final double height;
  final Color shadowColor;

  const BsheelBarChart({
    super.key,
    required this.values,
    this.highlightLast,
    this.height = 124,
    this.shadowColor = BsheelColors.cool,
  });

  @override
  Widget build(BuildContext context) {
    final max = values.isEmpty
        ? 1.0
        : values.reduce((a, b) => a > b ? a : b).clamp(1.0, double.infinity);

    return Container(
      height: height,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: BsheelColors.card,
        borderRadius: BorderRadius.circular(BsheelRadii.lg),
        border: const Border.fromBorderSide(BsheelBorders.inkSide),
        boxShadow: BsheelShadows.hard(4, color: shadowColor),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < values.length; i++) ...[
            Expanded(
              child: FractionallySizedBox(
                heightFactor: (values[i] / max).clamp(0.04, 1.0),
                child: Container(
                  decoration: BoxDecoration(
                    color: i == values.length - 1
                        ? BsheelColors.accent
                        : (values[i] >= max * 0.7
                            ? BsheelColors.primary
                            : BsheelColors.lavender),
                    borderRadius: BorderRadius.circular(3),
                    border:
                        const Border.fromBorderSide(BsheelBorders.inkSide),
                  ),
                ),
              ),
            ),
            if (i != values.length - 1) const SizedBox(width: 4),
          ],
        ],
      ),
    );
  }
}

// ── Inputs ──────────────────────────────────────────────────────────

/// Labelled field. Focus recolours the border to violet and adds a
/// matching coloured shadow; an error recolours to coral and adds one
/// line beneath, never a tooltip.
class BsheelField extends StatefulWidget {
  final TextEditingController? controller;
  final String? label;
  final String? hint;
  final String? error;
  final int maxLines;
  final int? maxLength;
  final TextInputType? keyboardType;
  final bool obscureText;
  final bool enabled;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final String? Function(String?)? validator;
  final Widget? prefix;
  final Widget? suffix;
  final TextAlign textAlign;
  final TextStyle? style;

  const BsheelField({
    super.key,
    this.controller,
    this.label,
    this.hint,
    this.error,
    this.maxLines = 1,
    this.maxLength,
    this.keyboardType,
    this.obscureText = false,
    this.enabled = true,
    this.onChanged,
    this.onSubmitted,
    this.validator,
    this.prefix,
    this.suffix,
    this.textAlign = TextAlign.start,
    this.style,
  });

  @override
  State<BsheelField> createState() => _BsheelFieldState();
}

class _BsheelFieldState extends State<BsheelField> {
  final _focus = FocusNode();
  String? _validationError;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final error = widget.error ?? _validationError;
    final focused = _focus.hasFocus;
    final borderColor = error != null
        ? BsheelColors.danger
        : (focused ? BsheelColors.primary : BsheelColors.ink);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.label != null) ...[
          BsheelLabel(widget.label!),
          const SizedBox(height: 6),
        ],
        AnimatedContainer(
          duration: const Duration(milliseconds: 110),
          decoration: BoxDecoration(
            color: widget.enabled ? BsheelColors.card : BsheelColors.surface,
            borderRadius: BorderRadius.circular(BsheelRadii.md),
            border: Border.all(
              color: borderColor,
              width: BsheelBorders.thick,
            ),
            boxShadow: focused
                ? BsheelShadows.hard(3, color: BsheelColors.primary)
                : null,
          ),
          child: Row(
            children: [
              if (widget.prefix != null) ...[
                const SizedBox(width: 12),
                widget.prefix!,
              ],
              Expanded(
                child: TextFormField(
                  controller: widget.controller,
                  focusNode: _focus,
                  enabled: widget.enabled,
                  maxLines: widget.maxLines,
                  maxLength: widget.maxLength,
                  keyboardType: widget.keyboardType,
                  obscureText: widget.obscureText,
                  onChanged: widget.onChanged,
                  onFieldSubmitted: widget.onSubmitted,
                  textAlign: widget.textAlign,
                  style: widget.style ?? BsheelType.bodyMd,
                  validator: widget.validator == null
                      ? null
                      : (v) {
                          final result = widget.validator!(v);
                          // Surface it on our own border, and return null
                          // so Material doesn't draw a second message.
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (mounted && result != _validationError) {
                              setState(() => _validationError = result);
                            }
                          });
                          return result;
                        },
                  decoration: InputDecoration(
                    hintText: widget.hint,
                    hintStyle: BsheelType.bodyMd.copyWith(
                      color: BsheelColors.inkMuted,
                    ),
                    counterText: '',
                    filled: false,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 13,
                      vertical: 14,
                    ),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    errorBorder: InputBorder.none,
                    focusedErrorBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    errorStyle: const TextStyle(height: 0, fontSize: 0),
                  ),
                ),
              ),
              if (widget.suffix != null) ...[
                widget.suffix!,
                const SizedBox(width: 8),
              ],
            ],
          ),
        ),
        if (error != null) ...[
          const SizedBox(height: 5),
          Text(
            error,
            style: BsheelType.bodyXs.copyWith(
              color: BsheelColors.dangerText,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }
}

/// Legacy validated field — delegates to [BsheelField].
class BsheelFormField extends StatelessWidget {
  final TextEditingController? controller;
  final String label;
  final int maxLines;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onChanged;

  const BsheelFormField({
    super.key,
    this.controller,
    required this.label,
    this.maxLines = 1,
    this.keyboardType,
    this.validator,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) => BsheelField(
        controller: controller,
        label: label,
        maxLines: maxLines,
        keyboardType: keyboardType,
        validator: validator,
        onChanged: onChanged,
      );
}

/// Legacy plain field — delegates to [BsheelField]. The old colour knobs
/// are accepted and ignored; the design has one input treatment.
class BsheelTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String? hint;
  final ValueChanged<String>? onChanged;
  final int maxLines;
  final TextInputType? keyboardType;
  final bool? isDense;
  final TextStyle? style;
  final TextStyle? labelStyle;
  final TextStyle? hintStyle;
  final Color fillColor;
  final Color borderColor;
  final Color focusedBorderColor;

  const BsheelTextField({
    super.key,
    required this.controller,
    required this.label,
    this.hint,
    this.onChanged,
    this.maxLines = 1,
    this.keyboardType,
    this.isDense,
    this.style,
    this.labelStyle,
    this.hintStyle,
    this.fillColor = BsheelColors.card,
    this.borderColor = BsheelColors.ink,
    this.focusedBorderColor = BsheelColors.primary,
  });

  @override
  Widget build(BuildContext context) => BsheelField(
        controller: controller,
        label: label.isEmpty ? null : label,
        hint: hint,
        onChanged: onChanged,
        maxLines: maxLines,
        keyboardType: keyboardType,
        style: style,
      );
}

/// Search field with a leading magnifier — used in page headers.
class BsheelSearchField extends StatelessWidget {
  final TextEditingController? controller;
  final String hint;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final double? width;

  const BsheelSearchField({
    super.key,
    this.controller,
    this.hint = 'Search…',
    this.onChanged,
    this.onSubmitted,
    this.width,
  });

  @override
  Widget build(BuildContext context) {
    final field = BsheelField(
      controller: controller,
      hint: hint,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      prefix: const Icon(
        Icons.search_rounded,
        size: 17,
        color: BsheelColors.inkMuted,
      ),
    );
    return width == null ? field : SizedBox(width: width, child: field);
  }
}

/// Dropdown in the Arcade Pop input shell.
class BsheelDropdown<T> extends StatelessWidget {
  final T value;
  final String label;
  final List<DropdownMenuItem<T>> items;
  final void Function(T?) onChanged;

  const BsheelDropdown({
    super.key,
    required this.value,
    required this.label,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label.isNotEmpty) ...[
          BsheelLabel(label),
          const SizedBox(height: 6),
        ],
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 13),
          decoration: BoxDecoration(
            color: BsheelColors.card,
            borderRadius: BorderRadius.circular(BsheelRadii.md),
            border: const Border.fromBorderSide(BsheelBorders.inkSide),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<T>(
              value: value,
              items: items,
              onChanged: onChanged,
              isExpanded: true,
              style: BsheelType.bodyMd,
              dropdownColor: BsheelColors.card,
              borderRadius: BorderRadius.circular(BsheelRadii.md),
              icon: const Icon(
                Icons.expand_more_rounded,
                color: BsheelColors.ink,
                size: 20,
              ),
              padding: const EdgeInsets.symmetric(vertical: 11),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Media ───────────────────────────────────────────────────────────

/// Diagonal-stripe placeholder for media that hasn't loaded or isn't
/// there. Same pattern as the design's proof-media block.
class BsheelMediaPlaceholder extends StatelessWidget {
  final String label;
  final double? width;
  final double? height;
  final double radius;
  final double depth;

  const BsheelMediaPlaceholder({
    super.key,
    this.label = 'PROOF MEDIA',
    this.width,
    this.height,
    this.radius = BsheelRadii.lg,
    this.depth = 0,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        border: const Border.fromBorderSide(BsheelBorders.inkSide),
        boxShadow: depth > 0 ? BsheelShadows.hard(depth) : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: CustomPaint(
        painter: const _StripePainter(),
        child: Center(
          child: label.isEmpty
              ? null
              : Padding(
                  padding: const EdgeInsets.all(8),
                  child: BsheelLabel(label, size: 10),
                ),
        ),
      ),
    );
  }
}

class _StripePainter extends CustomPainter {
  const _StripePainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = BsheelColors.bg,
    );
    final paint = Paint()
      ..color = BsheelColors.surface
      ..strokeWidth = 8
      ..style = PaintingStyle.stroke;
    // 135° stripes, 12px apart.
    for (double x = -size.height; x < size.width + size.height; x += 17) {
      canvas.drawLine(
        Offset(x, 0),
        Offset(x + size.height, size.height),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_StripePainter oldDelegate) => false;
}

/// Square thumbnail with the stripe pattern behind a network image.
class BsheelThumb extends StatelessWidget {
  final String? url;
  final double size;
  final double radius;

  const BsheelThumb({
    super.key,
    this.url,
    this.size = 44,
    this.radius = BsheelRadii.sm,
  });

  @override
  Widget build(BuildContext context) {
    final frame = BsheelMediaPlaceholder(
      label: '',
      width: size,
      height: size,
      radius: radius,
    );
    if (url == null || url!.isEmpty) return frame;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        border: const Border.fromBorderSide(BsheelBorders.inkSide),
      ),
      clipBehavior: Clip.antiAlias,
      child: Image.network(
        url!,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => frame,
        loadingBuilder: (_, child, progress) =>
            progress == null ? child : frame,
      ),
    );
  }
}

/// Circular avatar for a person; falls back to a tinted initial.
class BsheelAvatar extends StatelessWidget {
  final String? url;
  final String initial;
  final double size;
  final Color ground;

  const BsheelAvatar({
    super.key,
    this.url,
    this.initial = '?',
    this.size = 30,
    this.ground = BsheelColors.cool,
  });

  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: ground,
        shape: BoxShape.circle,
        border: const Border.fromBorderSide(BsheelBorders.inkSide),
      ),
      alignment: Alignment.center,
      child: Text(
        initial.toUpperCase(),
        style: BsheelType.titleSm.copyWith(
          color: BsheelColors.onAccent(ground),
          fontSize: size * 0.42,
        ),
      ),
    );

    if (url == null || url!.isEmpty) return fallback;

    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        border: Border.fromBorderSide(BsheelBorders.inkSide),
      ),
      clipBehavior: Clip.antiAlias,
      child: Image.network(
        url!,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => fallback,
      ),
    );
  }
}

// ── States ──────────────────────────────────────────────────────────

/// Skeleton block — keeps the 2px border but drops to muted violet-grey,
/// so a loading row still reads as a row and nothing shifts on load.
class BsheelSkeleton extends StatelessWidget {
  final double height;
  final double? width;
  final double? widthFactor;
  final double radius;

  const BsheelSkeleton({
    super.key,
    this.height = 56,
    this.width,
    this.widthFactor,
    this.radius = BsheelRadii.md,
  });

  /// Short bar, for a heading placeholder.
  const BsheelSkeleton.line({super.key, this.widthFactor = 0.45})
      : height = 16,
        width = null,
        radius = 6;

  @override
  Widget build(BuildContext context) {
    final box = Container(
      height: height,
      width: width,
      decoration: BoxDecoration(
        color: BsheelColors.skeleton,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: BsheelColors.lavender,
          width: BsheelBorders.thick,
        ),
      ),
    );
    if (widthFactor == null) return box;
    return FractionallySizedBox(
      alignment: Alignment.centerLeft,
      widthFactor: widthFactor,
      child: box,
    );
  }
}

/// Loading placeholder whose shapes match the real rows. No spinner.
class BsheelLoadingList extends StatelessWidget {
  final int rows;
  final double rowHeight;

  const BsheelLoadingList({super.key, this.rows = 4, this.rowHeight = 56});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const BsheelSkeleton.line(),
        const SizedBox(height: 9),
        for (var i = 0; i < rows; i++) ...[
          BsheelSkeleton(
            height: rowHeight,
            widthFactor: i == rows - 1 ? 0.7 : null,
          ),
          if (i != rows - 1) const SizedBox(height: 9),
        ],
      ],
    );
  }
}

/// Empty state. Every one names a single thing worth doing next, so pass
/// an [actionLabel] wherever there is one.
class BsheelEmptyState extends StatelessWidget {
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Color accent;
  final String? glyph;

  const BsheelEmptyState({
    super.key,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.accent = BsheelColors.inkMuted,
    this.glyph,
  });

  /// Queue cleared — jade dashed border and a tick.
  const BsheelEmptyState.allClear({
    super.key,
    this.title = 'ALL CLEAR',
    required this.message,
    this.actionLabel,
    this.onAction,
  })  : accent = BsheelColors.success,
        glyph = '✓';

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: CustomPaint(
          painter: _DashedBorderPainter(
            radius: BsheelRadii.card,
            color: accent,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (glyph != null) ...[
                  Text(glyph!, style: const TextStyle(fontSize: 28)),
                  const SizedBox(height: 7),
                ],
                Text(
                  title.toUpperCase(),
                  style: BsheelType.displaySm,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),
                Text(
                  message,
                  style: BsheelType.bodySm.copyWith(
                    color: BsheelColors.inkSoft,
                  ),
                  textAlign: TextAlign.center,
                ),
                if (actionLabel != null && onAction != null) ...[
                  const SizedBox(height: 14),
                  BsheelButton.ghost(
                    label: actionLabel!,
                    onPressed: onAction,
                    small: true,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Error state. Says what did *not* happen before offering retry — a
/// moderator's first fear is a half-applied decision.
class BsheelErrorState extends StatelessWidget {
  final String title;
  final String message;
  final VoidCallback? onRetry;

  const BsheelErrorState({
    super.key,
    this.title = 'FAILED TO LOAD',
    required this.message,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: BsheelColors.danger,
            borderRadius: BorderRadius.circular(BsheelRadii.card),
            border: const Border.fromBorderSide(BsheelBorders.inkSide),
            boxShadow: BsheelShadows.md,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title.toUpperCase(),
                style: BsheelType.displaySm.copyWith(fontSize: 19),
              ),
              const SizedBox(height: 8),
              Text(message, style: BsheelType.bodySm),
              if (onRetry != null) ...[
                const SizedBox(height: 12),
                BsheelButton(
                  label: 'Tap to retry',
                  onPressed: onRetry,
                  small: true,
                  background: BsheelColors.bg,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Persistent offline bar — not a toast. Actions stay enabled and queue
/// locally, so this states that rather than blocking the page.
class BsheelOfflineBar extends StatelessWidget {
  final String message;

  const BsheelOfflineBar({
    super.key,
    this.message = 'Reconnecting… decisions are queued locally.',
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
      decoration: BoxDecoration(
        color: BsheelColors.ink,
        borderRadius: BorderRadius.circular(BsheelRadii.card),
        border: const Border.fromBorderSide(BsheelBorders.inkSide),
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: const BoxDecoration(
              color: BsheelColors.accent,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const BsheelLabel('OFFLINE', color: BsheelColors.accent),
                const SizedBox(height: 1),
                Text(
                  message,
                  style: BsheelType.bodySm.copyWith(
                    color: BsheelColors.inkPanelTextStrong,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Dialog ──────────────────────────────────────────────────────────

/// Cream dialog with a 2px ink outline and a 6px shadow.
class BsheelDialog extends StatelessWidget {
  final String title;
  final Widget content;
  final List<Widget> actions;
  final Color backgroundColor;
  final TextStyle? titleStyle;
  final double maxWidth;

  const BsheelDialog({
    super.key,
    required this.title,
    required this.content,
    required this.actions,
    this.backgroundColor = BsheelColors.bg,
    this.titleStyle,
    this.maxWidth = 460,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Container(
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(BsheelRadii.lg),
            border: const Border.fromBorderSide(BsheelBorders.inkSide),
            boxShadow: BsheelShadows.xl,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 15,
                ),
                decoration: const BoxDecoration(
                  color: BsheelColors.surface,
                  border: Border(bottom: BsheelBorders.inkSide),
                ),
                child: Text(
                  title.toUpperCase(),
                  style: titleStyle ?? BsheelType.displaySm,
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: content,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    for (var i = 0; i < actions.length; i++) ...[
                      if (i != 0) const SizedBox(width: 9),
                      actions[i],
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Helpers ─────────────────────────────────────────────────────────

/// Short relative label from an ISO timestamp. Wraps app_core's
/// [timeAgo].
///
/// - `caps: true` (default) → `'3M AGO'`, `''` when unparsable.
/// - `caps: false` → `'3m ago'`; pair with `fallback: '?'`.
String bsheelTimeAgo(String? iso, {bool caps = true, String fallback = ''}) {
  if (iso == null) return fallback;
  final dt = DateTime.tryParse(iso);
  if (dt == null) return fallback;
  final label = '${timeAgo(dt.toLocal())} ago';
  return caps ? label.toUpperCase() : label;
}

/// `6h 12m` style waiting label from an ISO timestamp, for queue rows
/// where the exact age is the point.
String bsheelWaiting(String? iso, {String fallback = '—'}) {
  if (iso == null) return fallback;
  final dt = DateTime.tryParse(iso);
  if (dt == null) return fallback;
  final d = DateTime.now().difference(dt.toLocal());
  if (d.inMinutes < 1) return 'just now';
  if (d.inHours < 1) return '${d.inMinutes}m';
  if (d.inDays < 1) return '${d.inHours}h ${d.inMinutes % 60}m';
  return '${d.inDays}d ${d.inHours % 24}h';
}

/// True once a queue item has waited long enough to need coral.
bool bsheelIsStale(String? iso, {Duration threshold = const Duration(hours: 4)}) {
  if (iso == null) return false;
  final dt = DateTime.tryParse(iso);
  if (dt == null) return false;
  return DateTime.now().difference(dt.toLocal()) > threshold;
}
