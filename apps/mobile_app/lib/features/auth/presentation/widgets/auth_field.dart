import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';

/// The auth screens' text input, measured off `export/mobile/16-login.jpg`
/// and `export/mobile/17-signup.jpg`.
///
/// ```text
/// label      mono 10 / 700 / 0.1em, inkSoft            gap 6
/// box        52 of content inside a 2px stroke = 56 tall, r12,
///            white ground, 14 of horizontal padding, 15px value,
///            inkMuted placeholder, and NO drop shadow
/// error      12px / 600 osRedText                      gap 6
/// helper     12px inkSoft                              gap 6
/// ```
///
/// This is deliberately not `ArcadeTextField`. That primitive carries a
/// mandatory 3px ink shadow the frames do not draw, labels its field in full
/// ink rather than inkSoft, and paints its error state in
/// `QuestColors.softRed` with an 11px message — and `softRed` is the
/// retired token, not the design's coral. Until those are fixed in
/// `shared_ui` it cannot render these two screens. Everything here belongs
/// in `shared_ui` once it can.
class AuthField extends StatefulWidget {
  const AuthField({
    super.key,
    required this.label,
    this.controller,
    this.focusNode,
    this.hint,
    this.helperText,
    this.errorText,
    this.obscureText = false,
    this.keyboardType,
    this.textInputAction,
    this.onChanged,
    this.onSubmitted,
    this.autofillHints,
    this.autocorrect = true,
    this.enabled = true,
    this.trailing,
    this.textCapitalization = TextCapitalization.none,
    this.required = false,
  });

  final String label;
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String? hint;

  /// Rule-of-thumb copy under the field, in normal case. Hidden while
  /// [errorText] is showing — the frames never stack both.
  final String? helperText;
  final String? errorText;
  final bool obscureText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final Iterable<String>? autofillHints;
  final bool autocorrect;
  final bool enabled;

  /// Sits inside the box, right-aligned — the signup screen's jade
  /// username tick.
  final Widget? trailing;
  final TextCapitalization textCapitalization;

  /// Appends a coral asterisk to the label. The form marks what is
  /// mandatory rather than explaining it in prose — one glyph, no sentence.
  final bool required;

  @override
  State<AuthField> createState() => _AuthFieldState();
}

class _AuthFieldState extends State<AuthField> {
  FocusNode? _ownNode;
  bool _focused = false;
  bool _passwordVisible = false;

  FocusNode get _node => widget.focusNode ?? (_ownNode ??= FocusNode());

  @override
  void initState() {
    super.initState();
    _node.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(AuthField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode?.removeListener(_onFocusChange);
      _ownNode?.removeListener(_onFocusChange);
      _node.addListener(_onFocusChange);
    }
  }

  void _onFocusChange() {
    if (!mounted) return;
    final focused = _node.hasFocus;
    if (focused != _focused) setState(() => _focused = focused);
  }

  @override
  void dispose() {
    _node.removeListener(_onFocusChange);
    _ownNode?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasError = widget.errorText != null && widget.errorText!.isNotEmpty;
    // Error outranks focus: a coral box the user has just tapped into still
    // needs to read as the thing that is wrong.
    final borderColor = hasError
        ? QuestColors.osRed
        : _focused
            ? QuestColors.osPrimary
            : QuestColors.osTextPrimary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text.rich(
          TextSpan(
            text: widget.label.toUpperCase(),
            children: widget.required
                ? const [
                    TextSpan(
                      text: ' *',
                      style: TextStyle(color: QuestColors.osRedText),
                    ),
                  ]
                : null,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: QuestTypography.osLabelSmall.copyWith(
            fontSize: 10,
            // 0.1em at 10px.
            letterSpacing: 1,
            color: QuestColors.osTextSecondary,
          ),
        ),
        const SizedBox(height: 6),
        // The painted value is one 18px line inside a 52pt box, so a tap
        // near the top or bottom edge would otherwise miss the field
        // entirely. This makes the whole box the hit area.
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.enabled ? _node.requestFocus : null,
          child: Container(
            // 52 of content inside the 2px stroke.
            height: 56,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: QuestColors.cardBg(context),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: borderColor, width: 2),
              // The frames draw no shadow on an input. Focus is the one
              // exception: a violet 3px lift, which is how the component
              // sheet marks the active field.
              boxShadow: _focused && !hasError
                  ? QuestSpacing.hardShadow(3, color: QuestColors.osPrimary)
                  : null,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Center(
                    child: TextField(
                      controller: widget.controller,
                      focusNode: _node,
                      enabled: widget.enabled,
                      obscureText: widget.obscureText && !_passwordVisible,
                      keyboardType: widget.keyboardType,
                      textInputAction: widget.textInputAction,
                      autocorrect:
                          widget.obscureText ? false : widget.autocorrect,
                      enableSuggestions: !widget.obscureText,
                      autofillHints: widget.autofillHints,
                      textCapitalization: widget.textCapitalization,
                      onChanged: widget.onChanged,
                      onSubmitted: widget.onSubmitted,
                      maxLines: 1,
                      cursorColor: QuestColors.osPrimary,
                      style: _valueStyle,
                      decoration: InputDecoration(
                        hintText: widget.hint,
                        hintStyle: _valueStyle.copyWith(
                          color: QuestColors.osTextMuted,
                        ),
                        isCollapsed: true,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        disabledBorder: InputBorder.none,
                        errorBorder: InputBorder.none,
                        focusedErrorBorder: InputBorder.none,
                        counterText: '',
                        filled: false,
                      ),
                    ),
                  ),
                ),
                if (widget.obscureText)
                  IconButton(
                    tooltip:
                        _passwordVisible ? 'Hide password' : 'Show password',
                    constraints:
                        const BoxConstraints(minWidth: 44, minHeight: 44),
                    onPressed: widget.enabled
                        ? () =>
                            setState(() => _passwordVisible = !_passwordVisible)
                        : null,
                    icon: Icon(_passwordVisible
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined),
                  ),
                if (widget.trailing != null) ...[
                  const SizedBox(width: 10),
                  widget.trailing!,
                ],
              ],
            ),
          ),
        ),
        if (hasError) ...[
          const SizedBox(height: 6),
          Text(
            widget.errorText!,
            style: QuestTypography.osBodySmall.copyWith(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              fontVariations: const [FontVariation('wght', 600)],
              // Coral as type on cream fails contrast; this is its twin.
              color: QuestColors.onCream(QuestColors.osRed),
            ),
          ),
        ] else if (widget.helperText != null) ...[
          const SizedBox(height: 6),
          Text(
            widget.helperText!,
            style: QuestTypography.osBodySmall.copyWith(
              fontSize: 12,
              color: QuestColors.osTextSecondary,
            ),
          ),
        ],
      ],
    );
  }

  /// DM Sans 400 at 15px, as the frames set it. The family is a variable
  /// font, so the weight has to move the `wght` axis as well as the
  /// `fontWeight` slot.
  TextStyle get _valueStyle => QuestTypography.osBodyMedium.copyWith(
        fontSize: 15,
        height: 1.2,
        fontWeight: FontWeight.w400,
        fontVariations: const [FontVariation('wght', 400)],
        color: QuestColors.osTextPrimary,
      );
}

/// The jade check badge the signup frame puts inside a valid username field:
/// 24 of content inside a 2px ink stroke, r12, jade ground, ink glyph.
class AuthFieldTick extends StatelessWidget {
  const AuthFieldTick({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: QuestColors.osSuccess,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: QuestColors.osTextPrimary, width: 2),
      ),
      child: Icon(
        Icons.check_rounded,
        size: 15,
        // Jade ground: ink, never white.
        color: QuestColors.onAccent(QuestColors.osSuccess),
      ),
    );
  }
}

/// The auth screens' section label — mono 10/700 at 0.1em in inkSoft.
///
/// Shared with the OR divider so the two never drift apart.
TextStyle authMonoLabel({double fontSize = 10, double letterSpacingEm = 0.1}) =>
    QuestTypography.osLabelSmall.copyWith(
      fontSize: fontSize,
      letterSpacing: fontSize * letterSpacingEm,
      color: QuestColors.osTextSecondary,
    );
