import 'package:app_core/app_core.dart';
import 'package:flutter_test/flutter_test.dart';

/// ARC-015 / ARC-020: lock the canonical time-ago formatter so future
/// edits don't re-fragment the output across surfaces. Every "x m / h /
/// d / w / mo / y" rendering in the app routes through this.
void main() {
  // Pin "now" so the tests don't drift with wall-clock.
  final now = DateTime.utc(2026, 5, 3, 12, 0, 0);

  group('timeAgo', () {
    test('< 30 seconds renders as "now"', () {
      expect(
        timeAgo(now.subtract(const Duration(seconds: 5)), now: now),
        equals('now'),
      );
    });

    test('30s-60s renders as Ns', () {
      expect(
        timeAgo(now.subtract(const Duration(seconds: 45)), now: now),
        equals('45s'),
      );
    });

    test('< 60 minutes renders as Nm', () {
      expect(
        timeAgo(now.subtract(const Duration(minutes: 12)), now: now),
        equals('12m'),
      );
    });

    test('< 24 hours renders as Nh', () {
      expect(
        timeAgo(now.subtract(const Duration(hours: 5)), now: now),
        equals('5h'),
      );
    });

    test('< 7 days renders as Nd', () {
      expect(
        timeAgo(now.subtract(const Duration(days: 3)), now: now),
        equals('3d'),
      );
    });

    test('1-4 weeks renders as Nw', () {
      expect(
        timeAgo(now.subtract(const Duration(days: 14)), now: now),
        equals('2w'),
      );
    });

    test('1-11 months renders as Nmo', () {
      expect(
        timeAgo(now.subtract(const Duration(days: 60)), now: now),
        equals('2mo'),
      );
    });

    test('> 1 year renders as Ny', () {
      expect(
        timeAgo(now.subtract(const Duration(days: 800)), now: now),
        equals('2y'),
      );
    });

    test('future timestamps clamp to "now"', () {
      expect(
        timeAgo(now.add(const Duration(minutes: 5)), now: now),
        equals('now'),
      );
    });
  });
}
