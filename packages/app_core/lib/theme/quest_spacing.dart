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

  // ──────────────────────────────────────────────
  // RADIUS SCALE — the rest of it
  // ──────────────────────────────────────────────
  // The t-shirt scale above samples every *other* rung of an even ladder
  // (10 · 14 · 18 · 22) and the role names cover 8 · 12 · 16 · 18. The
  // design uses the odd rungs too, and heavily: counted across
  // `docs/design/mobile/Bsheel Mobile App.dc.html`, 13px appears 55 times
  // and 11px 39 times, against 2 uses of 10px. They were measured off the
  // frames, not guessed, so they are steps in the scale and not drift —
  // which is why 47 call sites had them written out as literals.
  //
  // Snapping them onto the nearest named token would have changed the
  // rendered design. Naming them changes nothing and finishes the scale.
  // Each token below records where its value comes from.

  /// 3px — tiny bars and pips: the 44×5 sheet grabber, carousel dots,
  /// onboarding step pips. The most-used small radius in the frames (40).
  static const double radiusPip = 3.0;

  /// 4px — password-strength segments and other standalone bar fills.
  /// A fill *nested inside* a bordered track is [inner] instead, not this.
  static const double radiusSegment = 4.0;

  /// 5px — 10pt status dots, the 18pt requirement checkbox, reroll segment
  /// cells, square heat cells (25 in the frames).
  static const double radiusDot = 5.0;

  /// 6px — micro badges carrying 2-3px of vertical padding, and the 36pt
  /// skeleton block (7 in the frames).
  static const double radiusBadge = 6.0;

  /// 7px — the 12pt meter track and the small pills set beside it
  /// (8 in the frames).
  static const double radiusMeterTrack = 7.0;

  /// 9px — 34pt glyph tiles and 38pt chips (12 in the frames). The lower
  /// bound of "9-14px controls" in `docs/design/mobile/SPEC.md`.
  static const double radiusGlyph = 9.0;

  /// 11px — 42-44pt square icon buttons, list rows, dialog inputs. The
  /// `r11` the widget doc comments throughout `mobile_app` already name
  /// (39 in the frames).
  static const double radiusButton = 11.0;

  /// 13px — 50-54pt buttons, the comment composer, and bordered content
  /// panels. The single most-used radius in the frames (55).
  static const double radiusPanel = 13.0;

  /// 15px — quest option cards and 60pt avatar tiles (5 in the frames).
  static const double radiusOption = 15.0;

  /// 24px — the 96-108pt chunky icon tile on the splash, offline and
  /// maintenance screens.
  static const double radiusTile = 24.0;

  /// 28px — the quest-history bottom sheet's top corners.
  ///
  /// The odd one out: the app's other three sheets use 22 (twice) and 18,
  /// and the frames draw no 28px sheet. Kept at its rendered value rather
  /// than snapped, because 28 → 22 is a 6px change nobody asked for.
  /// Worth settling with the designer, then collapsing to [radiusXl].
  static const double radiusSheet = 28.0;

  /// Every radius the design uses, in one set.
  ///
  /// `radius_scale_test.dart` asserts that no `BorderRadius.circular(N)` or
  /// `Radius.circular(N)` literal anywhere in `app_core`, `shared_ui` or
  /// `mobile_app` sits outside this set — so a new off-scale value fails a
  /// test instead of quietly becoming the 80th one.
  /// Not `const`: Dart forbids a constant set of `double`, which overrides
  /// `==`. `final` is fine — every element is a compile-time constant.
  static final Set<double> radiusScale = {
    radiusPip,
    radiusSegment,
    radiusDot,
    radiusBadge,
    radiusMeterTrack,
    radiusChip,
    radiusGlyph,
    radiusSm,
    radiusButton,
    radiusControl,
    radiusPanel,
    radiusMd,
    radiusOption,
    radiusCard,
    radiusLg,
    radiusXl,
    radiusTile,
    radiusSheet,
    radiusFull,
  };

  /// The radius the *inside* edge of a bordered box wants, given the box's
  /// [outer] radius and how far the child sits in from it ([inset] — the
  /// border width plus any padding between the two).
  ///
  /// Two concentric rounded boxes only look concentric when their radii
  /// differ by the gap between them; reuse [outer] and the inner corner
  /// reads too round. Use this rather than a second literal, so the pair
  /// stays correct when [outer] is retuned.
  ///
  /// Clamped at 0, since a large border on a small radius would otherwise
  /// go negative and throw.
  static double inner(double outer, double inset) {
    final r = outer - inset;
    return r < 0 ? 0 : r;
  }
}
