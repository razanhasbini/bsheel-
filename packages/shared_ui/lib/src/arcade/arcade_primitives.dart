import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:app_core/app_core.dart';

/// ──────────────────────────────────────────────────────────────────────────
/// Arcade Pop primitives — shared building blocks for every page.
///
/// All widgets here follow the Arcade Pop rules:
///   • 2-2.5 px ink border
///   • hard drop shadow (no blur, offset 2–4 px)
///   • chunky rounded corners (12–18 px)
///   • press-down = translate shadow into the card
///   • local fonts via QuestTypography (Syne w800 / DMSans / JetBrainsMono)
/// ──────────────────────────────────────────────────────────────────────────

/// Button variant. Drives the fill colour + foreground colour.
enum ArcadeButtonVariant {
  primary,   // gold (accentYellow)
  secondary, // violet (primary)
  danger,    // coral (softRed)
  ghost,     // transparent w/ ink border
}

/// Button size.
enum ArcadeButtonSize { small, medium, large }

class ArcadeButton extends StatefulWidget {
  const ArcadeButton({
    super.key,
    required this.label,
    this.onTap,
    this.variant = ArcadeButtonVariant.primary,
    this.size = ArcadeButtonSize.medium,
    this.icon,
    this.isLoading = false,
    this.expand = true,
  });

  final String label;
  final VoidCallback? onTap;
  final ArcadeButtonVariant variant;
  final ArcadeButtonSize size;
  final IconData? icon;
  final bool isLoading;
  final bool expand;

  @override
  State<ArcadeButton> createState() => _ArcadeButtonState();
}

class _ArcadeButtonState extends State<ArcadeButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final ink = QuestColors.text(context);
    final enabled = widget.onTap != null && !widget.isLoading;

    final (bg, fg) = switch (widget.variant) {
      ArcadeButtonVariant.primary =>
        (QuestColors.accentYellow, QuestColors.accentYellowInk),
      ArcadeButtonVariant.secondary => (QuestColors.osPrimary, QuestColors.osTextOnPrimary),
      ArcadeButtonVariant.danger => (QuestColors.softRed, QuestColors.osTextOnPrimary),
      ArcadeButtonVariant.ghost => (QuestColors.cardBg(context), ink),
    };

    final (paddingV, fontSize, iconSize, shadowOffset) = switch (widget.size) {
      ArcadeButtonSize.small => (10.0, 12.0, 16.0, 2.0),
      ArcadeButtonSize.medium => (14.0, 14.0, 18.0, 3.0),
      ArcadeButtonSize.large => (17.0, 16.0, 20.0, 4.0),
    };

    void onTapUp() {
      if (!enabled) return;
      HapticFeedback.lightImpact();
      widget.onTap?.call();
    }

    final child = AnimatedContainer(
      duration: const Duration(milliseconds: 60),
      transform: Matrix4.translationValues(
        0,
        _pressed ? shadowOffset : 0,
        0,
      ),
      padding: EdgeInsets.symmetric(vertical: paddingV, horizontal: 20),
      decoration: BoxDecoration(
        color: enabled ? bg : bg.withAlpha(120),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: ink, width: 2),
        boxShadow: _pressed || !enabled
            ? const []
            : [
                BoxShadow(
                  color: ink,
                  offset: Offset(0, shadowOffset),
                  blurRadius: 0,
                ),
              ],
      ),
      child: Row(
        mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (widget.isLoading)
            SizedBox(
              width: iconSize,
              height: iconSize,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                valueColor: AlwaysStoppedAnimation<Color>(fg),
              ),
            )
          else if (widget.icon != null)
            Icon(widget.icon, color: fg, size: iconSize),
          if ((widget.isLoading || widget.icon != null) &&
              widget.label.isNotEmpty)
            const SizedBox(width: 10),
          Flexible(
            child: Text(
              widget.label.toUpperCase(),
              textAlign: TextAlign.center,
              style: QuestTypography.buttonText.copyWith(
                color: fg,
                fontSize: fontSize,
                letterSpacing: 1.2,
                height: 1,
              ),
            ),
          ),
        ],
      ),
    );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
      onTapUp: enabled
          ? (_) {
              setState(() => _pressed = false);
              onTapUp();
            }
          : null,
      onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
      child: widget.expand
          ? SizedBox(width: double.infinity, child: child)
          : child,
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────
// TEXT FIELD
// ──────────────────────────────────────────────────────────────────────────

class ArcadeTextField extends StatefulWidget {
  const ArcadeTextField({
    super.key,
    this.controller,
    this.focusNode,
    this.label,
    this.hint,
    this.helper,
    this.errorText,
    this.obscureText = false,
    this.keyboardType,
    this.textInputAction,
    this.prefixIcon,
    this.suffixIcon,
    this.onChanged,
    this.onSubmitted,
    this.enabled = true,
    this.maxLines = 1,
    this.maxLength,
    this.autocorrect = true,
    this.autofillHints,
    this.textCapitalization = TextCapitalization.none,
  });

  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String? label;
  final String? hint;
  final String? helper;
  final String? errorText;

  /// If true, the field is a password field with a built-in visibility toggle.
  final bool obscureText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final IconData? prefixIcon;
  final Widget? suffixIcon;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool enabled;
  final int maxLines;
  final int? maxLength;
  final bool autocorrect;
  final Iterable<String>? autofillHints;
  final TextCapitalization textCapitalization;

  @override
  State<ArcadeTextField> createState() => _ArcadeTextFieldState();
}

class _ArcadeTextFieldState extends State<ArcadeTextField> {
  bool _obscured = true;

  @override
  void initState() {
    super.initState();
    _obscured = widget.obscureText;
  }

  @override
  Widget build(BuildContext context) {
    final ink = QuestColors.text(context);
    final bg = QuestColors.cardBg(context);
    final hasError = widget.errorText != null && widget.errorText!.isNotEmpty;
    final borderColor = hasError ? QuestColors.softRed : ink;

    Widget? suffix;
    if (widget.obscureText) {
      suffix = GestureDetector(
        onTap: () => setState(() => _obscured = !_obscured),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(
            _obscured
                ? Icons.visibility_off_rounded
                : Icons.visibility_rounded,
            color: ink.withAlpha(QuestColors.alphaInkSoft),
            size: 20,
          ),
        ),
      );
    } else if (widget.suffixIcon != null) {
      suffix = widget.suffixIcon;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.label != null) ...[
          Text(
            widget.label!.toUpperCase(),
            style: QuestTypography.labelSmall.copyWith(
              color: ink,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 6),
        ],
        Container(
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderColor, width: 2),
            boxShadow: [
              BoxShadow(
                color: ink,
                offset: const Offset(2, 3),
                blurRadius: 0,
              ),
            ],
          ),
          child: TextField(
            controller: widget.controller,
            focusNode: widget.focusNode,
            enabled: widget.enabled,
            obscureText: _obscured && widget.obscureText,
            keyboardType: widget.keyboardType,
            textInputAction: widget.textInputAction,
            maxLines: widget.obscureText ? 1 : widget.maxLines,
            maxLength: widget.maxLength,
            autocorrect: widget.autocorrect,
            autofillHints: widget.autofillHints,
            textCapitalization: widget.textCapitalization,
            onChanged: widget.onChanged,
            onSubmitted: widget.onSubmitted,
            style: QuestTypography.bodyMedium.copyWith(color: ink),
            cursorColor: QuestColors.osPrimary,
            decoration: InputDecoration(
              hintText: widget.hint,
              hintStyle: QuestTypography.bodyMedium.copyWith(
                color: ink.withAlpha(QuestColors.alphaInkWeak),
              ),
              prefixIcon: widget.prefixIcon != null
                  ? Icon(
                      widget.prefixIcon,
                      color: ink.withAlpha(QuestColors.alphaInkSoft),
                      size: 20,
                    )
                  : null,
              suffixIcon: suffix,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 14,
              ),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              errorBorder: InputBorder.none,
              focusedErrorBorder: InputBorder.none,
              disabledBorder: InputBorder.none,
              counterText: '',
              isDense: true,
              filled: false,
            ),
          ),
        ),
        if (hasError) ...[
          const SizedBox(height: 6),
          Text(
            widget.errorText!,
            style: QuestTypography.bodySmall.copyWith(
              color: QuestColors.softRed,
              fontSize: 11,
            ),
          ),
        ] else if (widget.helper != null) ...[
          const SizedBox(height: 6),
          Text(
            widget.helper!,
            style: QuestTypography.bodySmall.copyWith(
              color: ink.withAlpha(QuestColors.alphaInkSoft),
              fontSize: 11,
            ),
          ),
        ],
      ],
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────
// CARD (chunky container)
// ──────────────────────────────────────────────────────────────────────────

class ArcadeCard extends StatelessWidget {
  const ArcadeCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.backgroundColor,
    this.borderColor,
    this.borderRadius = 16,
    this.shadowOffset = 3,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? backgroundColor;
  final Color? borderColor;
  final double borderRadius;
  final double shadowOffset;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ink = borderColor ?? QuestColors.text(context);
    final bg = backgroundColor ?? QuestColors.cardBg(context);

    final container = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: ink, width: 2),
        boxShadow: [
          BoxShadow(
            color: ink,
            offset: Offset(2, shadowOffset),
            blurRadius: 0,
          ),
        ],
      ),
      child: child,
    );

    if (onTap == null) return container;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: container,
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────
// BACK BUTTON (ink square + arrow)
// ──────────────────────────────────────────────────────────────────────────

class ArcadeBackButton extends StatelessWidget {
  const ArcadeBackButton({super.key, this.onTap});
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ink = QuestColors.text(context);
    return GestureDetector(
      onTap: onTap ?? () => Navigator.of(context).maybePop(),
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: QuestColors.cardBg(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: ink, width: 2),
          boxShadow: [
            BoxShadow(color: ink, offset: const Offset(2, 3), blurRadius: 0),
          ],
        ),
        child: Icon(Icons.arrow_back_rounded, color: ink, size: 22),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────
// SECTION HEADER (short bar + label + hairline)
// ──────────────────────────────────────────────────────────────────────────

class ArcadeSectionHeader extends StatelessWidget {
  const ArcadeSectionHeader({
    super.key,
    required this.text,
    this.trailing,
  });
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final ink = QuestColors.text(context);
    return Row(
      children: [
        Container(width: 20, height: 2, color: ink),
        const SizedBox(width: 8),
        Text(
          text.toUpperCase(),
          style: QuestTypography.headlineSmall.copyWith(
            color: ink,
            fontSize: 14,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Container(
            height: 2,
            color: ink.withAlpha(QuestColors.alphaWhisper),
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 8),
          trailing!,
        ],
      ],
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────
// ERROR STATE
// ──────────────────────────────────────────────────────────────────────────

class ArcadeErrorState extends StatelessWidget {
  const ArcadeErrorState({
    super.key,
    this.title = 'Something went wrong',
    this.subtitle,
    this.onRetry,
  });

  final String title;
  final String? subtitle;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final ink = QuestColors.text(context);
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: QuestColors.softRed,
              shape: BoxShape.circle,
              border: Border.all(color: ink, width: 2),
              boxShadow: [
                BoxShadow(
                  color: ink,
                  offset: const Offset(3, 4),
                  blurRadius: 0,
                ),
              ],
            ),
            child: const Icon(
              Icons.error_outline_rounded,
              color: QuestColors.osTextOnPrimary,
              size: 34,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            title.toUpperCase(),
            textAlign: TextAlign.center,
            style: QuestTypography.headlineMedium.copyWith(
              color: ink,
              letterSpacing: 1,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 8),
            Text(
              subtitle!,
              textAlign: TextAlign.center,
              style: QuestTypography.bodyMedium.copyWith(
                color: ink.withAlpha(QuestColors.alphaInkMuted),
              ),
            ),
          ],
          if (onRetry != null) ...[
            const SizedBox(height: 20),
            ArcadeButton(
              label: 'Retry',
              icon: Icons.refresh_rounded,
              onTap: onRetry,
              variant: ArcadeButtonVariant.primary,
              expand: false,
            ),
          ],
        ],
      ),
    );
  }
}

