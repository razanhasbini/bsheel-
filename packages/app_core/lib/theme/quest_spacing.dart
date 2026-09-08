import 'dart:ui' show Offset;

/// Arcade Pop spacing + radius — the single source of truth for shape.
/// Chunky 2-3px borders and generous radii (10-22px) for the rounded-pop look.
abstract final class QuestSpacing {
  // 8px grid
  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 16.0;
  static const double lg = 24.0;
  static const double xl = 32.0;
  static const double xxl = 48.0;

  // Border radii
  static const double radiusSm = 10.0;
  static const double radiusMd = 14.0; // small tiles, cards, inputs
  static const double radiusLg = 18.0; // quest option cards
  static const double radiusXl = 22.0; // hero cards
  static const double radiusFull = 999.0;

  // Screen padding
  static const double screenPadding = 20.0;

  // Card
  static const double cardBorderWidth = 2.0; // chunky 2px outline

  /// Minimum comfortable hit target on any control, in logical pixels.
  ///
  /// Both design specs mandate 44 — the mobile one as a touch floor, the
  /// admin one as "44px minimum touch/click target on every control", since
  /// a moderator works a queue by pointer for hours. It lives here, with the
  /// other tokens, because it had otherwise been redefined three times: once
  /// per app and once in shared_ui. Three copies of one number is how a rule
  /// ends up meaning something slightly different in each place.
  ///
  /// Apply it to the hit area, not the paint: a control may look small and
  /// still be comfortably tappable.
  static const double minTouchTarget = 44.0;

  // Hard-offset drop shadow (no blur) — the Arcade Pop signature
  static const Offset hardShadowOffset = Offset(0, 6);
}
