import 'package:flutter/material.dart';

/// Bsheel admin tokens — **Arcade Pop**, the same system the mobile app
/// ships (`QuestColors` / `QuestTypography` in `app_core`), applied to the
/// moderator console per `admin-handoff/SPEC.md`.
///
/// Cream ground, deep-indigo ink on every outline and every shadow, hard
/// zero-blur offset shadows, and four accents that each carry one meaning:
///
/// * jade   `success`  — approve, live, in sync
/// * coral  `danger`   — reject, ban, remove, fault
/// * gold   `accent`   — anything waiting on a person
/// * violet `primary`  — navigation and the primary action
///
/// **Contrast rule (non-negotiable).** Text on coral, gold, jade or sky is
/// always ink — never white. White on coral measures 3.03:1 and fails.
/// Use [BsheelColors.onAccent] rather than picking by hand.
///
/// This file is the single source of truth for the admin look. Reskin by
/// editing values here (+ `admin_theme.dart`), nothing else.
abstract final class BsheelColors {
  // ── Surfaces ──────────────────────────────────────────────────────
  /// Page ground.
  static const Color bg = Color(0xFFFFF9EE);

  /// Headers, sidebars, secondary panels, quiet rows.
  static const Color surface = Color(0xFFFFF1D6);

  /// Cards, table bodies, inputs.
  static const Color card = Color(0xFFFFFFFF);

  /// Legacy alias for [card].
  static const Color paper = card;

  // ── Ink ───────────────────────────────────────────────────────────
  /// Text, every border, every shadow.
  static const Color ink = Color(0xFF1A1330);

  /// Secondary text.
  static const Color inkSoft = Color(0xFF5B5170);

  /// Placeholders, disabled, retired.
  static const Color inkMuted = Color(0xFF938AA8);

  // ── Accents (each carries exactly one meaning) ────────────────────
  /// Violet — navigation active, primary action.
  static const Color primary = Color(0xFF6B3BFF);
  static const Color violet = primary;

  /// Jade — approve, live, in sync.
  static const Color success = Color(0xFF17C27B);
  static const Color jade = success;

  /// Coral — reject, ban, remove, fault.
  static const Color danger = Color(0xFFFF5A6E);
  static const Color coral = danger;

  /// Legacy aliases for [danger].
  static const Color hot = danger;
  static const Color error = danger;

  /// Gold — anything waiting on a person.
  static const Color accent = Color(0xFFFFC224);
  static const Color gold = accent;

  /// Sky — informational accent.
  static const Color cool = Color(0xFF4CC9F0);
  static const Color sky = cool;

  /// Red *text* on cream (passes 4.5:1). Coral itself never carries text.
  static const Color dangerText = Color(0xFFC0392F);

  /// Ink used for text on a gold ground (mirrors `accentYellowInk`).
  static const Color accentInk = Color(0xFF2A1B00);

  // ── Structure ─────────────────────────────────────────────────────
  /// Every card, input, button, chip and tile outline is ink. Kept under
  /// the old `line` name so existing call sites inherit the new border.
  static const Color line = ink;

  /// 1px dividers *inside* a table or list body — the only hairline.
  static const Color rowLine = Color(0xFFEFE7D6);

  /// Inactive chart bars, "off" toggles, skeleton outlines.
  static const Color lavender = Color(0xFFC7C0E0);

  /// Skeleton block fill.
  static const Color skeleton = Color(0xFFEFE7D6);

  // ── Ink panel (sidebar, offline bar) ──────────────────────────────
  static const Color inkPanel = ink;
  static const Color inkPanelBorder = Color(0xFF2A2450);
  static const Color inkPanelText = Color(0xFFC7C0E0);
  static const Color inkPanelTextStrong = Color(0xFFFFF9EE);

  // ── Absolute neutrals — prefer a semantic token above ─────────────
  static const Color pureWhite = Color(0xFFFFFFFF);
  static const Color pureBlack = Color(0xFF000000);

  // ── Heat ramp (kept for compatibility) ────────────────────────────
  static const Color heat1 = skeleton;
  static const Color heat2 = lavender;
  static const Color heat3 = primary;
  static const Color heat4 = accent;

  // ── Quest categories (mobile `QuestColors.cat*`, verbatim) ────────
  static const Color catFitness = danger;
  static const Color catCreativity = primary;
  static const Color catSocial = cool;
  static const Color catLearning = success;
  static const Color catAdventure = accent;

  /// Category tint by its DB string; muted for anything unknown.
  static Color category(String? category) => switch (category) {
        'fitness' => catFitness,
        'creativity' => catCreativity,
        'social' => catSocial,
        'learning' => catLearning,
        'adventure' => catAdventure,
        _ => lavender,
      };

  /// The text colour that passes contrast on [ground].
  ///
  /// Violet and ink grounds take white; gold takes [accentInk]; every other
  /// accent (coral, jade, sky, cream, white) takes ink.
  static Color onAccent(Color ground) {
    if (ground == primary || ground == ink || ground == inkPanelBorder) {
      return pureWhite;
    }
    if (ground == accent) return accentInk;
    return ink;
  }

  /// Secondary text on [ground] — same rule, softer where the ground
  /// allows it. Never alpha-muted on an accent ground.
  static Color onAccentSoft(Color ground) {
    if (ground == card || ground == bg || ground == surface) return inkSoft;
    return onAccent(ground);
  }
}

/// Corner radii. 9–11 controls · 12–14 cards · 16 page frames · 999 pills.
abstract final class BsheelRadii {
  static const double sm = 9; // chips, small buttons, thumbnails
  static const double md = 11; // inputs, buttons, callouts
  static const double lg = 14; // cards, tables
  static const double xl = 16; // page frames, hero panels
  static const double full = 999; // pills

  static const double control = md;
  static const double card = 12;
  static const double cardLg = lg;
  static const double frame = xl;
}

/// Border weights. Every outline is 2px ink; 1px exists only for row
/// dividers in [BsheelColors.rowLine].
abstract final class BsheelBorders {
  /// The outline weight for every card, input, button, chip and tile.
  static const double thin = 2;
  static const double thick = 2;

  /// Row dividers inside a table or list body — the only 1px rule.
  static const double hairline = 1;

  static const BorderSide inkSide =
      BorderSide(color: BsheelColors.ink, width: thick);

  static const BorderSide rowSide =
      BorderSide(color: BsheelColors.rowLine, width: hairline);

  static Border all({Color color = BsheelColors.ink, double width = thick}) =>
      Border.all(color: color, width: width);
}

/// Hard offset shadows — zero blur, ink by default. A coloured shadow marks
/// the one item in a list that needs attention; everything else takes ink.
abstract final class BsheelShadows {
  static List<BoxShadow> hard(double offset, {Color color = BsheelColors.ink}) =>
      [BoxShadow(color: color, offset: Offset(offset, offset))];

  /// 3px — cards and small buttons.
  static const List<BoxShadow> sm = [
    BoxShadow(color: BsheelColors.ink, offset: Offset(3, 3)),
  ];

  /// 4px — stat tiles and primary buttons.
  static const List<BoxShadow> md = [
    BoxShadow(color: BsheelColors.ink, offset: Offset(4, 4)),
  ];

  /// 5px — tables.
  static const List<BoxShadow> lg = [
    BoxShadow(color: BsheelColors.ink, offset: Offset(5, 5)),
  ];

  /// 6px — hero panels and dialogs.
  static const List<BoxShadow> xl = [
    BoxShadow(color: BsheelColors.ink, offset: Offset(6, 6)),
  ];

  /// 8px — page frames (public pages drawn as a framed card).
  static const List<BoxShadow> frame = [
    BoxShadow(color: BsheelColors.ink, offset: Offset(8, 8)),
  ];

  static const List<BoxShadow> none = [];
}

/// Font families — bundled in `pubspec.yaml`, same cuts as the mobile app.
abstract final class BsheelFonts {
  /// Syne 800 — page and card titles, numerals, button labels.
  static const String display = 'Syne';

  /// DM Sans 400 / 500 / 600 — sentences.
  static const String body = 'DMSans';

  /// JetBrains Mono 700 — labels, ids, timestamps, counts, table headers.
  static const String mono = 'JetBrainsMono';
}

/// Type scale. ALL CAPS is for labels and headers only (four words or
/// fewer); sentences stay normal case. Minimum 9px for tracked mono labels,
/// 13px for body.
abstract final class BsheelType {
  // ── Display — Syne 800, tight tracking ────────────────────────────

  /// 38px numerals on stat tiles.
  static const TextStyle displayXl = TextStyle(
    fontFamily: BsheelFonts.display,
    fontWeight: FontWeight.w800,
    fontSize: 38,
    height: 1.0,
    letterSpacing: -1.5,
    color: BsheelColors.ink,
  );

  /// 30px — login title, secondary tile numerals.
  static const TextStyle displayLg = TextStyle(
    fontFamily: BsheelFonts.display,
    fontWeight: FontWeight.w800,
    fontSize: 30,
    height: 1.0,
    letterSpacing: -1.05,
    color: BsheelColors.ink,
  );

  /// 23px — page titles in the header bar.
  static const TextStyle displayMd = TextStyle(
    fontFamily: BsheelFonts.display,
    fontWeight: FontWeight.w800,
    fontSize: 23,
    height: 1.1,
    letterSpacing: -0.7,
    color: BsheelColors.ink,
  );

  /// 20px — content-pane titles, hero card titles.
  static const TextStyle displaySm = TextStyle(
    fontFamily: BsheelFonts.display,
    fontWeight: FontWeight.w800,
    fontSize: 20,
    height: 1.1,
    letterSpacing: -0.55,
    color: BsheelColors.ink,
  );

  /// 16px — card headings, section titles inside a pane.
  static const TextStyle displayXs = TextStyle(
    fontFamily: BsheelFonts.display,
    fontWeight: FontWeight.w700,
    fontSize: 16,
    height: 1.2,
    letterSpacing: -0.3,
    color: BsheelColors.ink,
  );

  /// 14px Syne 700 — usernames and row titles.
  static const TextStyle titleMd = TextStyle(
    fontFamily: BsheelFonts.display,
    fontWeight: FontWeight.w700,
    fontSize: 14,
    height: 1.2,
    letterSpacing: -0.1,
    color: BsheelColors.ink,
  );

  /// 13px Syne 700 — footer name, compact titles.
  static const TextStyle titleSm = TextStyle(
    fontFamily: BsheelFonts.display,
    fontWeight: FontWeight.w700,
    fontSize: 13,
    height: 1.2,
    color: BsheelColors.ink,
  );

  // ── Body — DM Sans ────────────────────────────────────────────────
  static const TextStyle bodyLg = TextStyle(
    fontFamily: BsheelFonts.body,
    fontWeight: FontWeight.w400,
    fontSize: 16,
    height: 1.6,
    color: BsheelColors.ink,
  );
  static const TextStyle bodyMd = TextStyle(
    fontFamily: BsheelFonts.body,
    fontWeight: FontWeight.w400,
    fontSize: 14,
    height: 1.55,
    color: BsheelColors.ink,
  );
  static const TextStyle bodyMdMedium = TextStyle(
    fontFamily: BsheelFonts.body,
    fontWeight: FontWeight.w500,
    fontSize: 14,
    height: 1.5,
    color: BsheelColors.ink,
  );
  static const TextStyle bodyMdBold = TextStyle(
    fontFamily: BsheelFonts.body,
    fontWeight: FontWeight.w600,
    fontSize: 14,
    height: 1.5,
    color: BsheelColors.ink,
  );

  /// 13px — table cells, card descriptions, callout copy.
  static const TextStyle bodySm = TextStyle(
    fontFamily: BsheelFonts.body,
    fontWeight: FontWeight.w400,
    fontSize: 13,
    height: 1.5,
    color: BsheelColors.ink,
  );
  static const TextStyle bodySmMedium = TextStyle(
    fontFamily: BsheelFonts.body,
    fontWeight: FontWeight.w500,
    fontSize: 13,
    height: 1.5,
    color: BsheelColors.ink,
  );

  /// 12px — row descriptions under a mono key, audit lines.
  static const TextStyle bodyXs = TextStyle(
    fontFamily: BsheelFonts.body,
    fontWeight: FontWeight.w400,
    fontSize: 12,
    height: 1.45,
    color: BsheelColors.inkSoft,
  );

  // ── Labels — JetBrains Mono 700, tracked, ALL CAPS at call sites ──

  /// 11px · 0.14em — section eyebrows.
  static const TextStyle labelLg = TextStyle(
    fontFamily: BsheelFonts.mono,
    fontWeight: FontWeight.w700,
    fontSize: 11,
    height: 1.3,
    letterSpacing: 1.5,
    color: BsheelColors.inkSoft,
  );

  /// 10px · 0.12em — field labels, card eyebrows, meta lines.
  static const TextStyle labelMd = TextStyle(
    fontFamily: BsheelFonts.mono,
    fontWeight: FontWeight.w700,
    fontSize: 10,
    height: 1.3,
    letterSpacing: 1.2,
    color: BsheelColors.inkSoft,
  );

  /// 9px · 0.1em — table headers, pills, footnotes.
  static const TextStyle labelSm = TextStyle(
    fontFamily: BsheelFonts.mono,
    fontWeight: FontWeight.w700,
    fontSize: 9,
    height: 1.3,
    letterSpacing: 0.9,
    color: BsheelColors.inkSoft,
  );

  // ── Mono data — ids, counts, timestamps (untracked) ───────────────

  /// 12px — ids, usernames in tables, counts.
  static const TextStyle monoMd = TextStyle(
    fontFamily: BsheelFonts.mono,
    fontWeight: FontWeight.w700,
    fontSize: 12,
    height: 1.3,
    color: BsheelColors.ink,
  );

  /// 11px — timestamps, moderator names in tables.
  static const TextStyle monoSm = TextStyle(
    fontFamily: BsheelFonts.mono,
    fontWeight: FontWeight.w700,
    fontSize: 11,
    height: 1.3,
    color: BsheelColors.inkSoft,
  );

  /// 13px — emphasised inline values (emails, ids in sentences).
  static const TextStyle monoLg = TextStyle(
    fontFamily: BsheelFonts.mono,
    fontWeight: FontWeight.w700,
    fontSize: 13,
    height: 1.3,
    color: BsheelColors.ink,
  );

  // ── Buttons — Syne ────────────────────────────────────────────────
  static const TextStyle buttonLg = TextStyle(
    fontFamily: BsheelFonts.display,
    fontWeight: FontWeight.w800,
    fontSize: 15,
    height: 1,
    letterSpacing: 0.6,
    color: BsheelColors.ink,
  );
  static const TextStyle buttonMd = TextStyle(
    fontFamily: BsheelFonts.display,
    fontWeight: FontWeight.w800,
    fontSize: 14,
    height: 1,
    letterSpacing: 0.5,
    color: BsheelColors.ink,
  );
  static const TextStyle buttonSm = TextStyle(
    fontFamily: BsheelFonts.display,
    fontWeight: FontWeight.w700,
    fontSize: 13,
    height: 1,
    letterSpacing: 0.2,
    color: BsheelColors.ink,
  );
  static const TextStyle buttonXs = TextStyle(
    fontFamily: BsheelFonts.display,
    fontWeight: FontWeight.w700,
    fontSize: 12,
    height: 1,
    letterSpacing: 0.2,
    color: BsheelColors.ink,
  );
}

/// Layout constants shared by the shell and page scaffolds.
abstract final class BsheelLayout {
  /// Fixed sidebar width.
  static const double sidebarWidth = 230;

  /// Header bar height across every page.
  static const double headerHeight = 66;

  /// Minimum click target on every control.
  static const double minTarget = 44;

  /// Content-pane padding (`22px 26px` on the dashboard, `20px 24px` on
  /// the rest — one value keeps pages aligned).
  static const EdgeInsets pagePadding = EdgeInsets.fromLTRB(24, 20, 24, 24);

  /// Width of a 640px content pane's inner column when centred.
  static const double paneMaxWidth = 720;
}
