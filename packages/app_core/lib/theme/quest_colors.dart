import 'package:flutter/material.dart';

/// Bit Sheel "Arcade Pop" palette — the SINGLE source of truth for every
/// colour in the product. To reskin the app, edit the values in this file
/// (plus quest_typography.dart for fonts and quest_spacing.dart for shape);
/// no widget code needs to change.
///
/// The app ships ONE theme: light Arcade Pop — cream background, deep-indigo
/// ink outlines, violet / gold / coral accents. Some screens deliberately
/// paint dark "ink panels" (splash, video overlays, arcade hero cards);
/// those colours live in the INK PANELS section. They are part of the light
/// theme's design language, not a dark mode.
abstract final class QuestColors {
  // ──────────────────────────────────────────────
  // CONTEXT HELPERS — preferred API in pages/widgets.
  // Kept as functions (context in, colour out) so a future multi-theme
  // setup can reintroduce per-theme logic without touching call sites.
  // ──────────────────────────────────────────────

  /// Page / scaffold background
  static Color bg(BuildContext context) => osBg;

  /// Card / container background
  static Color cardBg(BuildContext context) => osCard;

  /// Surface (slightly tinted — the "surfaceAlt" in design tokens)
  static Color surfaceBg(BuildContext context) => osSurface;

  /// Primary text colour
  static Color text(BuildContext context) => osTextPrimary;

  /// Secondary text colour
  static Color textSub(BuildContext context) => osTextSecondary;

  /// Muted / hint text colour
  static Color textDim(BuildContext context) => osTextMuted;

  /// Default border colour
  static Color borderC(BuildContext context) => osBorder;

  /// Accent / secondary interactive colour (gold)
  static Color accent(BuildContext context) => osAccent;

  /// Highlight / interactive accent (violet primary)
  static Color highlight(BuildContext context) => osPrimary;

  /// Page title colour
  static Color pageTitle(BuildContext context) => osTextPrimary;

  /// Subtle tinted bg for active chips, selected states.
  static Color highlightBg(BuildContext context) => osPrimary.withAlpha(30);

  // ──────────────────────────────────────────────
  // LIGHT CORE — cream surfaces + indigo ink (the shipped theme)
  // ──────────────────────────────────────────────

  // Surfaces (cream)
  static const Color osBg = Color(0xFFFFF9EE); // cream page
  static const Color osSurface = Color(0xFFFFF1D6); // warm surfaceAlt
  static const Color osCard = Color(0xFFFFFFFF); // white card

  // Text (deep indigo ink)
  static const Color osTextPrimary = Color(0xFF1A1330); // ink
  static const Color osTextSecondary = Color(0xFF5B5170); // inkSoft
  static const Color osTextMuted = Color(0xFF938AA8); // inkMuted
  static const Color osTextOnPrimary = Color(0xFFFFFFFF);

  // Primary — violet
  static const Color osPrimary = Color(0xFF6B3BFF);

  // Accents
  static const Color osAccent = Color(0xFFFFC224); // gold
  static const Color osAccentInk = Color(0xFF2A1B00);
  static const Color osRed = Color(0xFFFF5A6E); // hot / streak
  static const Color osSuccess = Color(0xFF17C27B);
  static const Color osCool = Color(0xFF4CC9F0);

  // Borders (soft violet-ink tinted)
  static const Color osBorder = Color(0x141A1330); // ~8% ink hairline
  static const Color osBorderStrong = Color(0xFF1A1330); // chunky 2px outlines

  // ──────────────────────────────────────────────
  // INK PANELS — dark surfaces used INSIDE the light design
  // (splash screen, video overlays, arcade hero cards).
  // ──────────────────────────────────────────────

  // Surfaces
  static const Color darkBg = Color(0xFF0E0B1C); // deep indigo
  static const Color darkSurface = Color(0xFF241E40); // surfaceAlt
  static const Color darkCard = Color(0xFF1A1530); // surface

  // Text on ink panels
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFFC7C0E0);
  static const Color textMuted = Color(0xFF7D759A);

  // Borders on ink panels
  static const Color border = Color(0xFF2A2450);

  // ──────────────────────────────────────────────
  // BRAND ACCENTS — shared across light surfaces and ink panels
  // ──────────────────────────────────────────────

  static const Color violet = Color(0xFF6B3BFF); // electric violet (brand)
  static const Color accentYellow = Color(0xFFFFC224); // XP gold
  static const Color accentYellowInk = Color(0xFF2A1B00);
  static const Color softRed = Color(0xFFFF6B7C); // streak / hot / error
  static const Color successGreen = Color(0xFF2FE096);

  // XP / Level
  static const Color xpGold = accentYellow;

  // ──────────────────────────────────────────────
  // ABSOLUTE NEUTRALS — prefer a semantic token above when one fits
  // ──────────────────────────────────────────────
  static const Color pureWhite = Color(0xFFFFFFFF);
  static const Color pureBlack = Color(0xFF000000);

  // ──────────────────────────────────────────────
  // QUEST CATEGORY COLOURS — Arcade Pop category tints
  // ──────────────────────────────────────────────
  static const Color catFitness = Color(0xFFFF5A6E); // coral/pink
  static const Color catCreativity = Color(0xFF6B3BFF); // violet
  static const Color catSocial = Color(0xFF4CC9F0); // sky
  static const Color catLearning = Color(0xFF17C27B); // jade
  static const Color catAdventure = Color(0xFFFFC224); // gold

  /// The tint for a category by its database string.
  ///
  /// Takes the raw value so a category added server-side degrades to violet
  /// rather than throwing — the catalog is admin-editable, so the client
  /// cannot assume it knows every value.
  static Color category(String? category) => switch (category) {
        'fitness' => catFitness,
        'creativity' => catCreativity,
        'social' => catSocial,
        'learning' => catLearning,
        'adventure' => catAdventure,
        _ => osPrimary,
      };

  // ──────────────────────────────────────────────
  // TEXT ON CREAM — accent tokens that fail contrast as small type
  // ──────────────────────────────────────────────
  // The accent fills are tuned to be read as *grounds*, behind ink. Used as
  // small text directly on cream they fall under 4.5:1, so each has a
  // darkened text-only twin. These are for type, never for a fill.

  /// Coral as text on cream. `osRed` measures 2.9:1 at 13px and fails.
  static const Color osRedText = Color(0xFFC0392F);

  /// Jade as text on cream. `osSuccess` measures 2.2:1 and fails.
  static const Color osSuccessText = Color(0xFF0F7A4E);

  /// Gold as text on cream. `osAccent` measures 1.6:1 — nearly invisible.
  static const Color osAccentText = Color(0xFF8A5F09);

  // ──────────────────────────────────────────────
  // CONTRAST — pick text by the ground it sits on
  // ──────────────────────────────────────────────

  /// The text colour that passes contrast on [ground].
  ///
  /// Violet and the ink panels take white; gold takes [osAccentInk]; every
  /// other accent — coral, jade, sky — takes ink.
  ///
  /// This encodes the one rule that is easiest to get wrong by eye: coral
  /// and jade *look* dark enough for white text and are not. White on
  /// coral measures 3.03:1 and fails WCAG AA; ink on coral measures
  /// 5.88:1 and passes. Call this instead of choosing by hand.
  static Color onAccent(Color ground) {
    if (ground == osPrimary ||
        ground == darkBg ||
        ground == darkCard ||
        ground == darkSurface) {
      return pureWhite;
    }
    if (ground == osAccent) return osAccentInk;
    return osTextPrimary;
  }

  /// Secondary text on [ground] — the same rule, softer only where the
  /// ground has the contrast headroom to allow it.
  ///
  /// Never alpha-muted on an accent ground: dimming ink on coral drops it
  /// back below AA, which is exactly what [onAccent] exists to prevent.
  /// On an accent, this returns full-opacity [onAccent] and lets size and
  /// weight carry the hierarchy instead.
  static Color onAccentSoft(Color ground) {
    if (ground == osCard || ground == osBg || ground == osSurface)
      return osTextSecondary;
    if (ground == darkBg || ground == darkCard || ground == darkSurface)
      return textSecondary;
    return onAccent(ground);
  }

  // ──────────────────────────────────────────────
  // SEMANTIC ALPHAS — use these instead of magic numbers
  // ──────────────────────────────────────────────
  /// ~12% — whisper / faint backgrounds, scanlines
  static const int alphaWhisper = 30;

  /// ~24% — hairlines, soft dividers
  static const int alphaHairline = 60;

  /// ~30% — overlay scrims, pressed states
  static const int alphaOverlay = 77;

  /// ~47% — weak ink (captions, placeholders)
  static const int alphaInkWeak = 120;

  /// ~55% — soft ink (secondary labels)
  static const int alphaInkSoft = 140;

  /// ~66% — muted ink (sublabels on tints)
  static const int alphaInkMuted = 170;
}
