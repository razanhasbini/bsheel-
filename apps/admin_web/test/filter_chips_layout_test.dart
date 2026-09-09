import 'package:admin_web/shared/widgets/bsheel_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// A filter row must stay on one line. It shipped stacked: `Center` has a null
// widthFactor, so it expanded to the full width its parent offered, and inside
// a Wrap that meant every chip claimed an entire row. Five chips came to 244px
// of vertical space instead of 44, and each one sat centred rather than left.
//
// Nothing catches that except layout — the analyzer was clean and every widget
// rendered correctly in isolation. Hence this test.
void main() {
  Future<void> pumpChips(WidgetTester tester, {double width = 1400}) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                // Matches AdminPage's subheader padding, since that is where
                // every filter row in the console actually lives.
                padding: const EdgeInsets.fromLTRB(24, 14, 24, 0),
                child: BsheelFilterChips(
                  selected: 'all',
                  onChanged: (_) {},
                  filters: const [
                    BsheelFilter('all', 'All'),
                    BsheelFilter('approved', 'Approved'),
                    BsheelFilter('rejected', 'Rejected'),
                    BsheelFilter('appealed', 'Appealed'),
                    BsheelFilter('rerejected', 'Re-rejected'),
                  ],
                ),
              ),
              const Expanded(child: SizedBox()),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  const labels = ['ALL', 'APPROVED', 'REJECTED', 'APPEALED', 'RE-REJECTED'];

  testWidgets('sits on a single row at desktop width', (tester) async {
    await pumpChips(tester);
    final tops = labels.map((l) => tester.getRect(find.text(l)).top).toSet();
    expect(tops, hasLength(1), reason: 'chips must share one row');
  });

  testWidgets('costs one row of height, not one row per chip', (tester) async {
    await pumpChips(tester);
    // 44 is the hit-target floor. Anything near 5x that means each chip took
    // its own row again.
    expect(tester.getRect(find.byType(Wrap)).height, lessThanOrEqualTo(56));
  });

  testWidgets('starts at the left edge rather than centring', (tester) async {
    await pumpChips(tester);
    final first = tester.getRect(find.text('ALL'));
    // A full-width chip centres its label; a hugging one starts near the
    // 24px page padding.
    expect(first.left, lessThan(60));
  });

  testWidgets('each chip still meets the 44px touch target', (tester) async {
    await pumpChips(tester);
    for (final label in labels) {
      final box = find.ancestor(
        of: find.text(label),
        matching: find.byType(SizedBox),
      );
      expect(tester.getRect(box.first).height, greaterThanOrEqualTo(44));
    }
  });

  testWidgets('wraps to more rows only when genuinely too narrow',
      (tester) async {
    await pumpChips(tester, width: 320);
    final tops = labels.map((l) => tester.getRect(find.text(l)).top).toSet();
    // It should wrap here — the point is that wrapping is width-driven, not
    // unconditional.
    expect(tops.length, greaterThan(1));
    expect(tops.length, lessThan(labels.length));
  });
}
