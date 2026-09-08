import 'package:flutter/material.dart';
import 'quest_colors.dart';

/// Arcade Pop typography — the single source of truth for fonts.
///
/// Uses locally bundled fonts declared in pubspec.yaml:
///   • Display / headline — Syne (variable font, axis wght → 800)
///   • Body — DMSans (400 / 500 / 600)
///   • Labels — JetBrainsMono (700)
///
/// Two style sets:
///   • `os*` styles — ink-on-cream colours; these feed the light ThemeData
///     (Theme.of(context).textTheme).
///   • Unprefixed styles — white-on-ink colours for the dark "ink panels"
///     (splash, video overlays, arcade hero cards). Call sites usually
///     override the colour with copyWith anyway.
///
/// Syne is shipped as a variable font. Flutter's `fontWeight` alone isn't
/// enough to push the variable axis — we need `fontVariations` with the
/// `wght` axis set to the numeric weight. Without this, the font renders at
/// its default axis position (Regular) and glyphs like digits appear thin.
abstract final class QuestTypography {
  static List<FontVariation> _wght(int w) =>
      [FontVariation('wght', w.toDouble())];

  static TextStyle _display({
    double fontSize = 24,
    FontWeight fontWeight = FontWeight.w800,
    Color color = QuestColors.textPrimary,
    double height = 1.1,
    double letterSpacing = -0.3,
    int weightAxis = 800,
  }) =>
      TextStyle(
        fontFamily: 'Syne',
        fontSize: fontSize,
        fontWeight: fontWeight,
        fontVariations: _wght(weightAxis),
        color: color,
        height: height,
        letterSpacing: letterSpacing,
      );

  static TextStyle _body({
    double fontSize = 14,
    FontWeight fontWeight = FontWeight.w500,
    Color color = QuestColors.textPrimary,
    double height = 1.5,
    double letterSpacing = 0,
    int weightAxis = 500,
  }) =>
      TextStyle(
        fontFamily: 'DMSans',
        fontSize: fontSize,
        fontWeight: fontWeight,
        fontVariations: _wght(weightAxis),
        color: color,
        height: height,
        letterSpacing: letterSpacing,
      );

  static TextStyle _mono({
    double fontSize = 11,
    FontWeight fontWeight = FontWeight.w700,
    Color color = QuestColors.textSecondary,
    double height = 1.4,
    double letterSpacing = 0.8,
    int weightAxis = 700,
  }) =>
      TextStyle(
        fontFamily: 'JetBrainsMono',
        fontSize: fontSize,
        fontWeight: fontWeight,
        fontVariations: _wght(weightAxis),
        color: color,
        height: height,
        letterSpacing: letterSpacing,
      );

  // ──────────────────────────────────────────────
  // ON-INK STYLES (white text — for dark ink panels)
  // ──────────────────────────────────────────────

  // Display scale
  static TextStyle get displayLarge =>
      _display(fontSize: 38, letterSpacing: -0.5);
  static TextStyle get displayMedium =>
      _display(fontSize: 30, letterSpacing: -0.4);
  static TextStyle get displaySmall =>
      _display(fontSize: 24, letterSpacing: -0.3);

  // Headline scale
  static TextStyle get headlineLarge => _display(fontSize: 20, height: 1.15);
  static TextStyle get headlineMedium => _display(fontSize: 16, height: 1.2);
  static TextStyle get headlineSmall =>
      _display(fontSize: 14, height: 1.25, letterSpacing: 0.2);

  // Body
  static TextStyle get bodyLarge => _body(fontSize: 16, height: 1.5);
  static TextStyle get bodyMedium => _body(fontSize: 14, height: 1.5);
  static TextStyle get bodySmall =>
      _body(fontSize: 12, color: QuestColors.textSecondary, height: 1.45);

  // Labels
  static TextStyle get labelLarge =>
      _mono(fontSize: 13, color: QuestColors.textPrimary, letterSpacing: 0.6);
  static TextStyle get labelMedium =>
      _mono(fontSize: 11, color: QuestColors.textPrimary, letterSpacing: 0.8);
  static TextStyle get labelSmall => _mono(fontSize: 10, letterSpacing: 1.0);

  static TextStyle get buttonText => _display(
        fontSize: 14,
        color: QuestColors.textPrimary,
        letterSpacing: 0.5,
        height: 1,
      );

  // ──────────────────────────────────────────────
  // LIGHT-SURFACE STYLES (ink text — feed the light ThemeData)
  // ──────────────────────────────────────────────

  static TextStyle get osDisplayLarge => _display(
      fontSize: 38, letterSpacing: -0.5, color: QuestColors.osTextPrimary);
  static TextStyle get osDisplayMedium => _display(
      fontSize: 30, letterSpacing: -0.4, color: QuestColors.osTextPrimary);
  static TextStyle get osDisplaySmall => _display(
      fontSize: 24, letterSpacing: -0.3, color: QuestColors.osTextPrimary);

  static TextStyle get osHeadlineLarge =>
      _display(fontSize: 20, height: 1.15, color: QuestColors.osTextPrimary);
  static TextStyle get osHeadlineMedium =>
      _display(fontSize: 16, height: 1.2, color: QuestColors.osTextPrimary);
  static TextStyle get osHeadlineSmall => _display(
      fontSize: 14,
      height: 1.25,
      letterSpacing: 0.2,
      color: QuestColors.osTextPrimary);

  static TextStyle get osBodyLarge =>
      _body(fontSize: 16, height: 1.5, color: QuestColors.osTextPrimary);
  static TextStyle get osBodyMedium =>
      _body(fontSize: 14, height: 1.5, color: QuestColors.osTextPrimary);
  static TextStyle get osBodySmall =>
      _body(fontSize: 12, height: 1.45, color: QuestColors.osTextSecondary);

  static TextStyle get osLabelLarge =>
      _mono(fontSize: 13, color: QuestColors.osTextPrimary, letterSpacing: 0.6);
  static TextStyle get osLabelMedium =>
      _mono(fontSize: 11, color: QuestColors.osTextPrimary, letterSpacing: 0.8);
  static TextStyle get osLabelSmall => _mono(
      fontSize: 10, color: QuestColors.osTextSecondary, letterSpacing: 1.0);

  static TextStyle get osButtonText => _display(
        fontSize: 14,
        color: QuestColors.osTextOnPrimary,
        letterSpacing: 0.5,
        height: 1,
      );
}
