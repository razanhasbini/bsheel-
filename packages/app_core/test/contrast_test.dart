import 'dart:math' as math;

import 'package:app_core/app_core.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

/// Covers `QuestColors.onAccent` / `onAccentSoft` / `onCream` — the three
/// canonical answers to "what colour is the text on this ground".
///
/// These had no test. That is what made a second, hand-rolled copy of the
/// rule in `lib/design/bs_widgets.dart` survive: nothing said what the rule
/// was, so nothing noticed the copy disagreeing. The helpers are the rule
/// now; this file is what makes them enforceable.
///
/// Every assertion is a measured ratio, not a colour preference — WCAG AA
/// is 4.5:1 for body text, 3:1 for large text and UI.
void main() {
  /// WCAG 2.x relative luminance.
  double luminance(Color c) {
    double channel(double v) =>
        v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4) as double;
    return 0.2126 * channel(c.r) +
        0.7152 * channel(c.g) +
        0.0722 * channel(c.b);
  }

  /// WCAG 2.x contrast ratio between two opaque colours.
  double ratio(Color a, Color b) {
    final la = luminance(a);
    final lb = luminance(b);
    return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
  }

  const aa = 4.5;

  /// Every colour the design uses as a *ground* behind text.
  const grounds = <String, Color>{
    'violet': QuestColors.osPrimary,
    'gold': QuestColors.osAccent,
    'coral': QuestColors.osRed,
    'jade': QuestColors.osSuccess,
    'sky': QuestColors.osCool,
    'cream': QuestColors.osBg,
    'card': QuestColors.osCard,
    'surface': QuestColors.osSurface,
    'ink': QuestColors.osTextPrimary,
    'darkBg': QuestColors.darkBg,
    'darkCard': QuestColors.darkCard,
    'darkSurface': QuestColors.darkSurface,
  };

  group('the sanity of the measuring stick', () {
    test('reproduces the ratios quoted in quest_colors.dart', () {
      // If these drift, every other assertion here is measuring something
      // other than WCAG contrast.
      //
      // The two figures the file quotes to 2dp reproduce exactly.
      expect(
          ratio(QuestColors.pureWhite, QuestColors.osRed), closeTo(3.03, 0.02));
      expect(ratio(QuestColors.osTextPrimary, QuestColors.osRed),
          closeTo(5.88, 0.02));
      // The four text-on-cream figures are quoted to 1dp and rounded
      // loosely — sky measures 1.835 and is written up as "1.9". Near
      // enough to confirm the same measurement, not near enough for 0.05.
      expect(ratio(QuestColors.osRed, QuestColors.osBg), closeTo(2.9, 0.1));
      expect(ratio(QuestColors.osSuccess, QuestColors.osBg), closeTo(2.2, 0.1));
      expect(ratio(QuestColors.osCool, QuestColors.osBg), closeTo(1.9, 0.1));
      expect(ratio(QuestColors.osAccent, QuestColors.osBg), closeTo(1.6, 0.1));
    });
  });

  group('onAccent', () {
    test('passes AA on every ground the design uses', () {
      for (final entry in grounds.entries) {
        final fg = QuestColors.onAccent(entry.value);
        expect(
          ratio(fg, entry.value),
          greaterThanOrEqualTo(aa),
          reason: 'onAccent(${entry.key}) returns '
              '#${fg.toARGB32().toRadixString(16)}, which measures '
              '${ratio(fg, entry.value).toStringAsFixed(2)}:1 — under AA.',
        );
      }
    });

    test('beats white on the two grounds white fails', () {
      // The whole reason the helper exists: coral and jade read as dark
      // enough for white type and are not.
      for (final ground in [QuestColors.osRed, QuestColors.osSuccess]) {
        expect(ratio(QuestColors.pureWhite, ground), lessThan(aa));
        expect(
          ratio(QuestColors.onAccent(ground), ground),
          greaterThan(ratio(QuestColors.pureWhite, ground)),
        );
      }
    });

    test('is white on violet and on every ink panel', () {
      for (final ground in [
        QuestColors.osPrimary,
        QuestColors.osTextPrimary,
        QuestColors.darkBg,
        QuestColors.darkCard,
        QuestColors.darkSurface,
      ]) {
        expect(QuestColors.onAccent(ground), QuestColors.pureWhite);
      }
    });

    test('never returns the ground back to the caller', () {
      // An ink foreground on an ink ground is the invisible-text bug the
      // helper was fixed for; nothing may reintroduce it.
      for (final ground in grounds.values) {
        expect(QuestColors.onAccent(ground), isNot(ground));
      }
    });

    test('is ink on the light grounds, and osAccentInk on gold', () {
      expect(
          QuestColors.onAccent(QuestColors.osAccent), QuestColors.osAccentInk);
      for (final ground in [
        QuestColors.osRed,
        QuestColors.osSuccess,
        QuestColors.osCool,
        QuestColors.osBg,
        QuestColors.osCard,
        QuestColors.osSurface,
      ]) {
        expect(QuestColors.onAccent(ground), QuestColors.osTextPrimary);
      }
    });
  });

  group('onAccentSoft', () {
    test('passes AA on every ground the design uses', () {
      for (final entry in grounds.entries) {
        final fg = QuestColors.onAccentSoft(entry.value);
        expect(
          ratio(fg, entry.value),
          greaterThanOrEqualTo(aa),
          reason: 'onAccentSoft(${entry.key}) measures '
              '${ratio(fg, entry.value).toStringAsFixed(2)}:1 — under AA.',
        );
      }
    });

    test('does not soften on an accent ground', () {
      // Dimming ink on coral drops it back under AA, so on an accent this
      // must hand back onAccent unchanged.
      for (final ground in [
        QuestColors.osPrimary,
        QuestColors.osAccent,
        QuestColors.osRed,
        QuestColors.osSuccess,
        QuestColors.osCool,
      ]) {
        expect(
          QuestColors.onAccentSoft(ground),
          QuestColors.onAccent(ground),
        );
      }
    });

    test('softens only where the ground has headroom', () {
      for (final ground in [
        QuestColors.osCard,
        QuestColors.osBg,
        QuestColors.osSurface,
      ]) {
        expect(QuestColors.onAccentSoft(ground), QuestColors.osTextSecondary);
      }
      for (final ground in [
        QuestColors.osTextPrimary,
        QuestColors.darkBg,
        QuestColors.darkCard,
        QuestColors.darkSurface,
      ]) {
        expect(QuestColors.onAccentSoft(ground), QuestColors.textSecondary);
      }
    });

    test('is fully opaque everywhere', () {
      // `withAlpha` on type over an accent is what the rule forbids.
      for (final ground in grounds.values) {
        expect(QuestColors.onAccentSoft(ground).a, 1.0);
        expect(QuestColors.onAccent(ground).a, 1.0);
      }
    });
  });

  group('onCream', () {
    test('lifts every failing accent to AA as text on cream', () {
      for (final accent in [
        QuestColors.osRed,
        QuestColors.osSuccess,
        QuestColors.osAccent,
        QuestColors.osCool,
      ]) {
        expect(ratio(accent, QuestColors.osBg), lessThan(aa),
            reason: 'this accent no longer needs a text twin');
        expect(
          ratio(QuestColors.onCream(accent), QuestColors.osBg),
          greaterThanOrEqualTo(aa),
          reason: 'onCream leaves '
              '#${accent.toARGB32().toRadixString(16)} under AA on cream.',
        );
      }
    });

    test('maps each accent to its documented twin', () {
      expect(QuestColors.onCream(QuestColors.osRed), QuestColors.osRedText);
      expect(QuestColors.onCream(QuestColors.osSuccess),
          QuestColors.osSuccessText);
      expect(
          QuestColors.onCream(QuestColors.osAccent), QuestColors.osAccentText);
      // Sky has a twin too. The deleted bs_widgets copy of this rule
      // returned ink here, which is the disagreement that made two copies
      // of the rule a maintenance trap rather than a stylistic choice.
      expect(QuestColors.onCream(QuestColors.osCool), QuestColors.osCoolText);
    });

    test('passes anything that already reads on cream straight through', () {
      for (final c in [
        QuestColors.osPrimary,
        QuestColors.osTextPrimary,
        QuestColors.osTextSecondary,
        QuestColors.osRedText,
      ]) {
        expect(QuestColors.onCream(c), c);
      }
    });

    test('is idempotent — a twin passed back in is unchanged', () {
      for (final accent in [
        QuestColors.osRed,
        QuestColors.osSuccess,
        QuestColors.osAccent,
        QuestColors.osCool,
      ]) {
        final twin = QuestColors.onCream(accent);
        expect(QuestColors.onCream(twin), twin);
      }
    });
  });
}
