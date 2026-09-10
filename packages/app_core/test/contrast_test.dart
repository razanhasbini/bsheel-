import 'dart:math' as math;
import 'dart:ui';

import 'package:app_core/app_core.dart';
import 'package:flutter_test/flutter_test.dart';

/// WCAG relative luminance.
double _luminance(Color c) {
  double channel(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
}

/// WCAG contrast ratio between two opaque colours.
double _ratio(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  final lighter = math.max(la, lb);
  final darker = math.min(la, lb);
  return (lighter + 0.05) / (darker + 0.05);
}

void main() {
  // The measurements the helpers' own documentation cites. If a token is
  // retuned, these say so rather than letting the claim rot in a comment.
  group('the numbers the helpers are built on', () {
    test('white on coral really does fail AA', () {
      expect(_ratio(QuestColors.pureWhite, QuestColors.osRed), lessThan(4.5));
    });

    test('and ink on coral really does pass', () {
      expect(_ratio(QuestColors.osTextPrimary, QuestColors.osRed),
          greaterThanOrEqualTo(4.5));
    });

    test('every accent fails as a foreground on cream', () {
      for (final accent in [
        QuestColors.osRed,
        QuestColors.osSuccess,
        QuestColors.osAccent,
        QuestColors.osCool,
      ]) {
        expect(_ratio(accent, QuestColors.osBg), lessThan(4.5),
            reason: 'if this now passes, onCream has nothing to fix for it');
      }
    });
  });

  group('QuestColors.onAccent', () {
    test('passes AA on every ground the design fills with', () {
      final grounds = <String, Color>{
        'violet': QuestColors.osPrimary,
        'coral': QuestColors.osRed,
        'jade': QuestColors.osSuccess,
        'gold': QuestColors.osAccent,
        'sky': QuestColors.osCool,
        'ink panel': QuestColors.osTextPrimary,
        'card': QuestColors.osCard,
        'cream': QuestColors.osBg,
        'surface': QuestColors.osSurface,
      };
      grounds.forEach((name, ground) {
        expect(_ratio(QuestColors.onAccent(ground), ground),
            greaterThanOrEqualTo(4.5),
            reason: '$name ground');
      });
    });

    test('never returns a foreground equal to its own ground', () {
      // The failure that hid here before: an ink *panel* used as a ground
      // returned ink, and the text vanished entirely.
      for (final ground in [
        QuestColors.osPrimary,
        QuestColors.osRed,
        QuestColors.osSuccess,
        QuestColors.osAccent,
        QuestColors.osCool,
        QuestColors.osTextPrimary,
        QuestColors.osCard,
        QuestColors.osBg,
      ]) {
        expect(QuestColors.onAccent(ground), isNot(ground));
      }
    });
  });

  group('QuestColors.onAccentSoft', () {
    test('still passes AA everywhere, accents included', () {
      // Secondary text is where dimming is tempting; on an accent ground it
      // drops straight back below AA, so this must not be alpha-muted.
      for (final ground in [
        QuestColors.osPrimary,
        QuestColors.osRed,
        QuestColors.osSuccess,
        QuestColors.osAccent,
        QuestColors.osCool,
        QuestColors.osCard,
        QuestColors.osBg,
        QuestColors.osSurface,
      ]) {
        expect(_ratio(QuestColors.onAccentSoft(ground), ground),
            greaterThanOrEqualTo(4.5),
            reason: 'soft foreground on $ground');
      }
    });
  });

  group('QuestColors.onCream', () {
    test('lifts each accent to AA as a foreground on cream', () {
      for (final accent in [
        QuestColors.osRed,
        QuestColors.osSuccess,
        QuestColors.osAccent,
        QuestColors.osCool,
      ]) {
        expect(_ratio(QuestColors.onCream(accent), QuestColors.osBg),
            greaterThanOrEqualTo(4.5),
            reason: 'readable twin of $accent');
      }
    });

    test('passes anything that is not an accent straight through', () {
      expect(QuestColors.onCream(QuestColors.osTextPrimary),
          QuestColors.osTextPrimary);
      expect(QuestColors.onCream(QuestColors.osPrimary), QuestColors.osPrimary);
    });
  });
}
