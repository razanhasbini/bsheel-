import 'package:flutter/material.dart';

/// Bsheel admin tokens — "Port" direction (ported from ~/Desktop/port).
///
/// Strict black & white, light grotesque type (Helvetica Neue → bundled
/// Inter), tight tracking, hairline 1px rules, #F7F7F7 surfaces, #8F8F8F
/// muted. No chunky borders, no hard-offset shadows, no decorative colour —
/// the only hues left are quiet semantic states an admin tool needs
/// (approve / danger), desaturated so they whisper.
///
/// This file is the single source of truth for the admin look: reskin the
/// dashboard by editing values here (+ admin_theme.dart), nothing else.
abstract final class BsheelColors {
  static const Color bg = Color(0xFFFFFFFF);      // page — pure white
  static const Color surface = Color(0xFFF7F7F7); // quiet panel gray
  static const Color paper = Color(0xFFFFFFFF);   // cards sit flush on white

  static const Color ink = Color(0xFF000000);     // text + lines
  static const Color inkSoft = Color(0xFF4D4D4D);
  static const Color inkMuted = Color(0xFF8F8F8F);

  /// Primary action = solid black. The port system has no accent hue;
  /// emphasis is weight, size, and inversion.
  static const Color accent = Color(0xFF000000);
  static const Color primary = Color(0xFF000000);

  // Semantic states — desaturated so they read as status, not decoration.
  static const Color hot = Color(0xFFC03434);     // destructive / danger
  static const Color error = hot;
  static const Color cool = Color(0xFF6E6E6E);    // informational
  static const Color success = Color(0xFF2F7A54); // approve / positive

  // Heatmap stops — grayscale ramp (light → black).
  static const Color heat1 = Color(0xFFEDEDED);
  static const Color heat2 = Color(0xFFC9C9C9);
  static const Color heat3 = Color(0xFF8F8F8F);
  static const Color heat4 = Color(0xFF000000);

  // Absolute neutrals — prefer a semantic token above when one fits.
  static const Color pureWhite = Color(0xFFFFFFFF);
  static const Color pureBlack = Color(0xFF000000);

  /// Hairline for dividers / card outlines (ink at ~10%).
  static const Color line = Color(0x1A000000);
}

abstract final class BsheelRadii {
  // Port is sharp: media sits at ~3px, everything else near-square.
  static const double sm = 2;
  static const double md = 3;
  static const double lg = 4;
  static const double xl = 6;
  static const double full = 999; // pills stay pills
}

abstract final class BsheelBorders {
  /// Hairline — the only border weight in the system.
  static const double thin = 1;
}

abstract final class BsheelFonts {
  /// Light grotesque throughout. Helvetica Neue where the OS has it,
  /// otherwise the bundled Inter (port's own fallback order).
  static const String display = 'Inter';
  static const String body = 'Inter';
  static const String mono = 'JetBrainsMono'; // tabular data / ids only
}

abstract final class BsheelType {
  // Display — light weight, tight tracking, tight leading. An accent word
  // inside a headline renders as plain italic (same ink), never a colour.
  static const TextStyle displayXl = TextStyle(
    fontFamily: BsheelFonts.display,
    fontWeight: FontWeight.w300,
    fontSize: 46,
    height: 1.04,
    letterSpacing: -1.4,
    color: BsheelColors.ink,
  );
  static const TextStyle displayLg = TextStyle(
    fontFamily: BsheelFonts.display,
    fontWeight: FontWeight.w300,
    fontSize: 34,
    height: 1.06,
    letterSpacing: -1.0,
    color: BsheelColors.ink,
  );
  static const TextStyle displayMd = TextStyle(
    fontFamily: BsheelFonts.display,
    fontWeight: FontWeight.w400,
    fontSize: 26,
    height: 1.1,
    letterSpacing: -0.6,
    color: BsheelColors.ink,
  );
  static const TextStyle displaySm = TextStyle(
    fontFamily: BsheelFonts.display,
    fontWeight: FontWeight.w400,
    fontSize: 20,
    height: 1.15,
    letterSpacing: -0.3,
    color: BsheelColors.ink,
  );

  // Body — light, calm leading.
  static const TextStyle bodyLg = TextStyle(
    fontFamily: BsheelFonts.body,
    fontWeight: FontWeight.w300,
    fontSize: 16,
    height: 1.5,
    letterSpacing: -0.1,
    color: BsheelColors.ink,
  );
  static const TextStyle bodyMd = TextStyle(
    fontFamily: BsheelFonts.body,
    fontWeight: FontWeight.w300,
    fontSize: 14,
    height: 1.5,
    letterSpacing: -0.05,
    color: BsheelColors.ink,
  );
  static const TextStyle bodySm = TextStyle(
    fontFamily: BsheelFonts.body,
    fontWeight: FontWeight.w400,
    fontSize: 12.5,
    height: 1.45,
    color: BsheelColors.inkSoft,
  );
  static const TextStyle bodyMdBold = TextStyle(
    fontFamily: BsheelFonts.body,
    fontWeight: FontWeight.w500,
    fontSize: 14,
    height: 1.5,
    color: BsheelColors.ink,
  );

  // Labels — small caps-style utility (used ALL CAPS at call sites),
  // regular weight, wide-but-quiet tracking, muted by default.
  static const TextStyle labelLg = TextStyle(
    fontFamily: BsheelFonts.body,
    fontWeight: FontWeight.w400,
    fontSize: 12,
    height: 1.3,
    letterSpacing: 1.2,
    color: BsheelColors.ink,
  );
  static const TextStyle labelMd = TextStyle(
    fontFamily: BsheelFonts.body,
    fontWeight: FontWeight.w400,
    fontSize: 11,
    height: 1.3,
    letterSpacing: 1.0,
    color: BsheelColors.inkMuted,
  );
  static const TextStyle labelSm = TextStyle(
    fontFamily: BsheelFonts.body,
    fontWeight: FontWeight.w400,
    fontSize: 10,
    height: 1.3,
    letterSpacing: 0.9,
    color: BsheelColors.inkMuted,
  );
}
