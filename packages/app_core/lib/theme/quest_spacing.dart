import 'dart:ui' show Color, Offset;

import 'package:flutter/painting.dart' show BoxShadow;

import 'quest_colors.dart';

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

  // ──────────────────────────────────────────────
  // HARD SHADOW SCALE — the Arcade Pop signature
  // ──────────────────────────────────────────────
  // Zero blur, ink colour, equal x/y offset. Depth *is* the weight scale,
  // so pick by the element's role rather than by eye:
  //
  //   3px  small cards and chips
  //   4px  stat tiles and secondary buttons
  //   5px  primary buttons and media
  //   6px  hero panels
  //   8px  phone-level frames
  //
  // A *coloured* shadow marks the one element on screen that matters most
  // (violet on the active-quest hero, jade on a cleared quest). Everything
  // else takes ink. Pass `color` for that case.

  /// Hard offset shadow at [depth], ink unless [color] says otherwise.
  static List<BoxShadow> hardShadow(
    double depth, {
    Color color = QuestColors.osTextPrimary,
  }) =>
      [BoxShadow(color: color, offset: Offset(depth, depth))];

  /// 3px — small cards and chips.
  static const List<BoxShadow> shadowSm = [
    BoxShadow(color: QuestColors.osTextPrimary, offset: Offset(3, 3)),
  ];

  /// 4px — stat tiles and secondary buttons.
  static const List<BoxShadow> shadowMd = [
    BoxShadow(color: QuestColors.osTextPrimary, offset: Offset(4, 4)),
  ];

  /// 5px — primary buttons and media.
  static const List<BoxShadow> shadowLg = [
    BoxShadow(color: QuestColors.osTextPrimary, offset: Offset(5, 5)),
  ];

  /// 6px — hero panels.
  static const List<BoxShadow> shadowXl = [
    BoxShadow(color: QuestColors.osTextPrimary, offset: Offset(6, 6)),
  ];

  /// 8px — phone-level frames.
  static const List<BoxShadow> shadowFrame = [
    BoxShadow(color: QuestColors.osTextPrimary, offset: Offset(8, 8)),
  ];

  /// Border radii the design uses, named by role so call sites stop
  /// guessing between 12 and 14.
  static const double radiusChip = 8.0; // category tags are square-ish
  static const double radiusControl = 12.0; // inputs, buttons
  static const double radiusCard = 16.0; // cards
  static const double radiusHero = 18.0; // hero panels
}
