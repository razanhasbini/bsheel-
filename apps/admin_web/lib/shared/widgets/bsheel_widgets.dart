import 'package:app_core/app_core.dart' show timeAgo;
import 'package:flutter/material.dart';

import '../../core/theme/bsheel_design.dart';

/// "Port" primitives — strict black & white, hairline 1px rules, flat
/// (zero shadows), sharp radii, light Inter type. Emphasis is inversion
/// (solid black pill, white text), size and weight — never colour.
/// Semantic colours (hot / success / cool) appear only on status text.
///
/// Naming preserved from the previous direction so existing call sites
/// keep compiling — they're just restyled.

// ── Card ────────────────────────────────────────────────────────────

class BsheelCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final double radius;

  const BsheelCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(22),
    this.color,
    this.radius = BsheelRadii.lg,
  });

  /// Tighter padding, slightly sharper corners. Kept for call-site
  /// compatibility with the old `.card.flat` modifier.
  const BsheelCard.flat({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.color,
    this.radius = BsheelRadii.md,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? BsheelColors.paper,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: BsheelColors.line,
          width: BsheelBorders.thin,
        ),
      ),
      child: child,
    );
  }
}

// ── Eyebrow ─────────────────────────────────────────────────────────

class BsheelEyebrow extends StatelessWidget {
  final String text;
  final Color? color;

  const BsheelEyebrow(this.text, {super.key, this.color});

  @override
  Widget build(BuildContext context) {
    return Text(
      '— ${text.toUpperCase()}',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: BsheelType.labelMd.copyWith(
        color: color ?? BsheelColors.inkMuted,
      ),
    );
  }
}

// ── Pill ────────────────────────────────────────────────────────────

/// Tone names kept from the old palette; they now resolve to the port
/// system — solid black for emphasis, hairline outline with a semantic
/// text colour for status.
enum BsheelPillTone { ink, gold, coral, violet, green, sky, ghost, paper }

class BsheelPill extends StatelessWidget {
  final String label;
  final BsheelPillTone tone;
  final bool small;

  const BsheelPill(
    this.label, {
    super.key,
    this.tone = BsheelPillTone.ink,
    this.small = false,
  });

  @override
  Widget build(BuildContext context) {
    final (bg, fg, border) = switch (tone) {
      // Emphasis = inversion.
      BsheelPillTone.ink => (
          BsheelColors.ink,
          BsheelColors.pureWhite,
          BsheelColors.ink
        ),
      BsheelPillTone.gold => (
          BsheelColors.ink,
          BsheelColors.pureWhite,
          BsheelColors.ink
        ),
      BsheelPillTone.violet => (
          BsheelColors.ink,
          BsheelColors.pureWhite,
          BsheelColors.ink
        ),
      // Status = hairline pill, semantic colour only on the text. The
      // accent *fills* fail 4.5:1 as 10–11px type on paper, so each takes
      // its darkened text-only twin via `onCream`.
      BsheelPillTone.coral => (
          BsheelColors.paper,
          BsheelColors.onCream(BsheelColors.danger),
          BsheelColors.line
        ),
      BsheelPillTone.green => (
          BsheelColors.paper,
          BsheelColors.onCream(BsheelColors.success),
          BsheelColors.line
        ),
      BsheelPillTone.sky => (
          BsheelColors.paper,
          BsheelColors.onCream(BsheelColors.cool),
          BsheelColors.line
        ),
      BsheelPillTone.ghost => (
          Colors.transparent,
          BsheelColors.inkMuted,
          BsheelColors.line
        ),
      BsheelPillTone.paper => (
          BsheelColors.paper,
          BsheelColors.ink,
          BsheelColors.line
        ),
    };
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: small ? 9 : 12,
        vertical: small ? 4 : 6,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(BsheelRadii.full),
        border: Border.all(color: border, width: BsheelBorders.thin),
      ),
      child: Text(
        label.toUpperCase(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: BsheelType.labelMd.copyWith(
          color: fg,
          fontSize: small ? 10 : 11,
        ),
      ),
    );
  }
}

// ── Button ──────────────────────────────────────────────────────────

class BsheelButton extends StatefulWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final BsheelPillTone tone;
  final bool small;
  final bool loading;
  final bool ghost;
  final double? height;

  /// `background`/`foreground` are kept for backwards compatibility with
  /// older call sites; they're ignored when [tone] resolves the colour.
  final Color? background;
  final Color? foreground;

  const BsheelButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.tone = BsheelPillTone.ink,
    this.small = false,
    this.loading = false,
    this.ghost = false,
    this.height,
    this.background,
    this.foreground,
  });

  /// Primary action — solid black pill, white text.
  const BsheelButton.primary({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.small = false,
    this.loading = false,
    this.height,
  })  : tone = BsheelPillTone.ink,
        ghost = false,
        background = null,
        foreground = null;

  /// Destructive action — solid pill in the semantic danger colour.
  const BsheelButton.coral({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.small = false,
    this.loading = false,
    this.height,
  })  : tone = BsheelPillTone.coral,
        ghost = false,
        background = null,
        foreground = null;

  /// Legacy secondary-emphasis variant — resolves to solid black.
  const BsheelButton.violet({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.small = false,
    this.loading = false,
    this.height,
  })  : tone = BsheelPillTone.violet,
        ghost = false,
        background = null,
        foreground = null;

  /// Hairline-outlined ghost variant.
  const BsheelButton.ghost({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.small = false,
    this.loading = false,
    this.height,
  })  : tone = BsheelPillTone.paper,
        ghost = true,
        background = null,
        foreground = null;

  @override
  State<BsheelButton> createState() => _BsheelButtonState();
}

class _BsheelButtonState extends State<BsheelButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final disabled = widget.onPressed == null || widget.loading;
    final (bg, fg, border) = switch (widget.tone) {
      // Emphasis tones — inversion.
      BsheelPillTone.ink => (
          BsheelColors.ink,
          BsheelColors.pureWhite,
          BsheelColors.ink
        ),
      BsheelPillTone.gold => (
          BsheelColors.ink,
          BsheelColors.pureWhite,
          BsheelColors.ink
        ),
      BsheelPillTone.violet => (
          BsheelColors.ink,
          BsheelColors.pureWhite,
          BsheelColors.ink
        ),
      // Semantic actions — ink on the accent, never white. White on coral
      // measures 3.03:1 and fails AA; `onAccent` picks the passing ink.
      BsheelPillTone.coral => (
          BsheelColors.danger,
          BsheelColors.onAccent(BsheelColors.danger),
          BsheelColors.ink
        ),
      BsheelPillTone.green => (
          BsheelColors.success,
          BsheelColors.onAccent(BsheelColors.success),
          BsheelColors.ink
        ),
      // Quiet variants — hairline outline, ink text.
      BsheelPillTone.sky => (
          BsheelColors.paper,
          BsheelColors.ink,
          BsheelColors.ink
        ),
      BsheelPillTone.paper => (
          BsheelColors.paper,
          BsheelColors.ink,
          BsheelColors.ink
        ),
      BsheelPillTone.ghost => (
          Colors.transparent,
          BsheelColors.ink,
          BsheelColors.ink
        ),
    };

    final hPad = widget.small ? 16.0 : 20.0;
    final vPad = widget.small ? 8.0 : 11.0;
    final fontSize = widget.small ? 11.0 : 13.0;

    return MouseRegion(
      cursor: disabled ? MouseCursor.defer : SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: disabled ? null : (_) => setState(() => _down = true),
        onTapUp: disabled
            ? null
            : (_) {
                setState(() => _down = false);
                widget.onPressed?.call();
              },
        onTapCancel: () => setState(() => _down = false),
        // 44px minimum click target (spec §1) without inflating the pill:
        // the hit box is at least 44 tall, the visual stays centred in it.
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: widget.height ?? BsheelLayout.minTarget,
          ),
          child: Align(
            alignment: Alignment.center,
            widthFactor: 1,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 90),
              opacity: disabled ? 0.45 : (_down ? 0.7 : 1.0),
              child: Container(
                height: widget.height,
                padding: EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(BsheelRadii.full),
                  border: Border.all(color: border, width: BsheelBorders.thin),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (widget.loading)
                      SizedBox(
                        width: fontSize + 2,
                        height: fontSize + 2,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.5,
                          valueColor: AlwaysStoppedAnimation(fg),
                        ),
                      )
                    else if (widget.icon != null) ...[
                      Icon(widget.icon, size: fontSize + 3, color: fg),
                      const SizedBox(width: 8),
                    ],
                    Flexible(
                      child: Text(
                        widget.label.toUpperCase(),
                        maxLines: 1,
                        style: TextStyle(
                          fontFamily: BsheelFonts.body,
                          fontWeight: FontWeight.w400,
                          fontSize: fontSize,
                          letterSpacing: 1.1,
                          color: fg,
                          height: 1,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Display headline with italic accent ────────────────────────────

/// Use `{...}` braces in [text] to mark the accent word. It renders as
/// plain italic in the same ink — never a colour.
class BsheelDisplay extends StatelessWidget {
  final String text;
  final TextStyle baseStyle;

  const BsheelDisplay(
    this.text, {
    super.key,
    this.baseStyle = BsheelType.displayLg,
  });

  @override
  Widget build(BuildContext context) {
    final spans = <InlineSpan>[];
    final pattern = RegExp(r'\{([^}]+)\}');
    int cursor = 0;
    for (final m in pattern.allMatches(text)) {
      if (m.start > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, m.start)));
      }
      spans.add(
        TextSpan(
          text: m.group(1)!,
          style: baseStyle.copyWith(fontStyle: FontStyle.italic),
        ),
      );
      cursor = m.end;
    }
    if (cursor < text.length) {
      spans.add(TextSpan(text: text.substring(cursor)));
    }
    return RichText(text: TextSpan(style: baseStyle, children: spans));
  }
}

// ── Section header (eyebrow + display headline pair) ────────────────

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
            BsheelEyebrow(eyebrow!),
            const SizedBox(height: 8),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: RichText(
                  text: TextSpan(
                    style: BsheelType.displayLg,
                    children: [
                      TextSpan(text: title),
                      if (emphasis != null)
                        TextSpan(
                          text: ' $emphasis',
                          style: BsheelType.displayLg.copyWith(
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              if (actionLabel != null)
                GestureDetector(
                  onTap: onAction,
                  behavior: HitTestBehavior.opaque,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    // 44px min target — padding, so the label keeps its
                    // quiet visual weight.
                    child: Container(
                      constraints: const BoxConstraints(
                        minHeight: BsheelLayout.minTarget,
                      ),
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        '$actionLabel  →',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: BsheelType.labelLg,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Tile (dashboard stat block) ────────────────────────────────────

class BsheelTile extends StatelessWidget {
  final String eyebrow;
  final String value;
  final String? delta;
  final Color? deltaColor;
  final Color color;
  final VoidCallback? onTap;

  const BsheelTile({
    super.key,
    required this.eyebrow,
    required this.value,
    this.delta,
    this.deltaColor,
    this.color = BsheelColors.paper,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Foreground is derived, never passed: on coral / gold / jade / sky the
    // text must be ink, and `onAccent` is the only place that decides.
    final fg = BsheelColors.onAccent(color);
    final soft = BsheelColors.onAccentSoft(color);
    return _Pressable(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: BsheelLayout.minTarget),
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(BsheelRadii.lg),
          border: Border.all(
            color: BsheelColors.line,
            width: BsheelBorders.thin,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // The affordance arrow shares the eyebrow row rather than
            // floating over it, so a long eyebrow can never run under it.
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: BsheelEyebrow(eyebrow, color: soft)),
                if (onTap != null) ...[
                  const SizedBox(width: 6),
                  Icon(
                    Icons.arrow_outward_rounded,
                    size: 14,
                    color: soft,
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                maxLines: 1,
                style: BsheelType.displayXl.copyWith(
                  color: fg,
                  letterSpacing: -1.5,
                ),
              ),
            ),
            const SizedBox(height: 6),
            if (delta != null)
              Text(
                delta!.toUpperCase(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: BsheelType.labelMd.copyWith(
                  color: deltaColor ?? soft,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Segmented (pill-shaped tab control) ────────────────────────────

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
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: BsheelColors.paper,
        borderRadius: BorderRadius.circular(BsheelRadii.full),
        border: Border.all(
          color: BsheelColors.line,
          width: BsheelBorders.thin,
        ),
      ),
      // A long option list must never run outside the control: it wraps
      // onto a second run instead of overflowing the shell.
      child: Wrap(
        spacing: 2,
        runSpacing: 2,
        children: List.generate(options.length, (i) {
          final on = i == selected;
          return MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onChanged?.call(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                // 44px minimum click target (spec §1).
                constraints: const BoxConstraints(
                  minHeight: BsheelLayout.minTarget,
                ),
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: on ? BsheelColors.ink : Colors.transparent,
                  borderRadius: BorderRadius.circular(BsheelRadii.full),
                ),
                child: Text(
                  options[i].toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: BsheelType.labelMd.copyWith(
                    color: on
                        ? BsheelColors.onAccent(BsheelColors.ink)
                        : BsheelColors.inkSoft,
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

// ── Progress bar ────────────────────────────────────────────────────

/// Flat meter — black fill on a light gray track, square ends.
class BsheelProgress extends StatelessWidget {
  final double value;
  final Color fill;
  final double height;

  const BsheelProgress({
    super.key,
    required this.value,
    this.fill = BsheelColors.ink,
    this.height = 6,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      color: BsheelColors.heat1,
      child: Align(
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: value.clamp(0.0, 1.0),
          child: ColoredBox(color: fill),
        ),
      ),
    );
  }
}

// ── Form field (validated, TextFormField-based) ────────────────────

/// Canonical Bsheel form field. Was the private `_DarkFormField` copied
/// across quest_management / users / quest_injection pages.
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
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      style: BsheelType.bodyMd,
      validator: validator,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: BsheelType.labelSm.copyWith(
          color: BsheelColors.inkMuted,
        ),
        filled: true,
        fillColor: BsheelColors.paper,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(BsheelRadii.md),
          borderSide: const BorderSide(
            color: BsheelColors.line,
            width: BsheelBorders.thin,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(BsheelRadii.md),
          borderSide: const BorderSide(
            color: BsheelColors.line,
            width: BsheelBorders.thin,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(BsheelRadii.md),
          borderSide: const BorderSide(
            color: BsheelColors.ink,
            width: BsheelBorders.thin,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(BsheelRadii.md),
          borderSide: const BorderSide(
            color: BsheelColors.hot,
            width: BsheelBorders.thin,
          ),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(BsheelRadii.md),
          borderSide: const BorderSide(
            color: BsheelColors.hot,
            width: BsheelBorders.thin,
          ),
        ),
      ),
    );
  }
}

// ── Text field (plain, TextField-based) ────────────────────────────

/// Canonical Bsheel text field. Was the private `_DarkTextField` copied
/// (with small divergences) across pending_submissions /
/// submission_review / xp_management pages. Styling knobs remain so
/// call sites can quiet or emphasise a field, but defaults are the port
/// look: white fill, hairline border, black focus border.
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
    this.fillColor = BsheelColors.paper,
    this.borderColor = BsheelColors.line,
    this.focusedBorderColor = BsheelColors.ink,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      style: style ?? BsheelType.bodyMd,
      onChanged: onChanged,
      maxLines: maxLines,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: labelStyle ??
            BsheelType.labelSm.copyWith(color: BsheelColors.inkMuted),
        hintStyle: hintStyle,
        filled: true,
        fillColor: fillColor,
        isDense: isDense,
        // A dense field still has to clear the 44px target (spec §1).
        constraints: const BoxConstraints(minHeight: BsheelLayout.minTarget),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(BsheelRadii.md),
          borderSide: BorderSide(color: borderColor, width: BsheelBorders.thin),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(BsheelRadii.md),
          borderSide: BorderSide(color: borderColor, width: BsheelBorders.thin),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(BsheelRadii.md),
          borderSide: BorderSide(
            color: focusedBorderColor,
            width: BsheelBorders.thin,
          ),
        ),
      ),
    );
  }
}

// ── Dropdown ────────────────────────────────────────────────────────

/// Canonical Bsheel dropdown. Was the private `_DarkDropdown` copied
/// across quest_management / quest_injection pages.
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
    return DropdownButtonFormField<T>(
      initialValue: value,
      style: BsheelType.bodyMd,
      dropdownColor: BsheelColors.paper,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: BsheelType.labelSm.copyWith(
          color: BsheelColors.inkMuted,
        ),
        filled: true,
        fillColor: BsheelColors.paper,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(BsheelRadii.md),
          borderSide: const BorderSide(
            color: BsheelColors.line,
            width: BsheelBorders.thin,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(BsheelRadii.md),
          borderSide: const BorderSide(
            color: BsheelColors.line,
            width: BsheelBorders.thin,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(BsheelRadii.md),
          borderSide: const BorderSide(
            color: BsheelColors.ink,
            width: BsheelBorders.thin,
          ),
        ),
      ),
      items: items,
      onChanged: onChanged,
    );
  }
}

// ── Dialog (title + content + trailing actions row) ────────────────

/// Canonical Bsheel dialog. Was the private `_DarkAlertDialog` /
/// `_DarkDialog` copied across quest_management / users /
/// pending_submissions pages. Defaults are the white port look; pass
/// [backgroundColor] / [titleStyle] for the dark media-panel variant.
class BsheelDialog extends StatelessWidget {
  final String title;
  final Widget content;
  final List<Widget> actions;
  final Color backgroundColor;
  final TextStyle? titleStyle;

  const BsheelDialog({
    super.key,
    required this.title,
    required this.content,
    required this.actions,
    this.backgroundColor = BsheelColors.paper,
    this.titleStyle,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: backgroundColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(BsheelRadii.xl),
        side: const BorderSide(
          color: BsheelColors.line,
          width: BsheelBorders.thin,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: titleStyle ??
                  BsheelType.displaySm.copyWith(color: BsheelColors.ink),
            ),
            const SizedBox(height: 16),
            // Tall content scrolls inside the dialog rather than pushing
            // the action row off a short browser window.
            Flexible(child: SingleChildScrollView(child: content)),
            const SizedBox(height: 24),
            // Actions wrap instead of overflowing a narrow dialog.
            Align(
              alignment: Alignment.centerRight,
              child: Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 8,
                children: actions,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Time-ago label helper ───────────────────────────────────────────

/// Formats an ISO timestamp as a short relative label. Wraps the shared
/// app_core [timeAgo] formatter. Was the private `_timeAgo` copied
/// across appeals / reports / auto_notifications pages.
///
/// - Default (`caps: true`): `'3M AGO'` style, `''` on null/unparsable
///   input (appeals / reports).
/// - `caps: false`: `'3m ago'` style — pair with `fallback: '?'` for the
///   auto_notifications variant.
String bsheelTimeAgo(String? iso, {bool caps = true, String fallback = ''}) {
  if (iso == null) return fallback;
  final dt = DateTime.tryParse(iso);
  if (dt == null) return fallback;
  final label = '${timeAgo(dt.toLocal())} ago';
  return caps ? label.toUpperCase() : label;
}

// ── Pressable scale helper ─────────────────────────────────────────

class _Pressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;

  const _Pressable({required this.child, this.onTap});

  @override
  State<_Pressable> createState() => _PressableState();
}

class _PressableState extends State<_Pressable> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor:
          widget.onTap == null ? MouseCursor.defer : SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onTapDown:
            widget.onTap == null ? null : (_) => setState(() => _down = true),
        onTapUp: (_) => setState(() => _down = false),
        onTapCancel: () => setState(() => _down = false),
        child: AnimatedScale(
          duration: const Duration(milliseconds: 80),
          scale: _down ? 0.985 : 1.0,
          child: widget.child,
        ),
      ),
    );
  }
}
