import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/core/services/impression_tracker.dart';

/// Impressions are the one figure in the event store nobody can audit, so
/// every case here is a way of counting a view that did not happen.
void main() {
  const dwell = Duration(milliseconds: 20);

  ({ImpressionTracker tracker, List<String> seen}) trackerFor({
    bool Function()? isForeground,
  }) {
    final seen = <String>[];
    return (
      tracker: ImpressionTracker(
        onImpression: (questId, _) => seen.add(questId),
        dwell: dwell,
        isForeground: isForeground,
      ),
      seen: seen,
    );
  }

  test('counts a card that stayed on screen', () async {
    final t = trackerFor();
    t.tracker.onVisible('q1');
    expect(t.seen, isEmpty, reason: 'not before the dwell elapses');

    await Future<void>.delayed(dwell * 2);

    expect(t.seen, ['q1']);
    t.tracker.dispose();
  });

  test('does not count a card flicked past', () async {
    // The whole reason this class exists. Ten cards built in one scroll are
    // not ten views, and a build count cannot tell the difference.
    final t = trackerFor();
    for (var i = 0; i < 10; i += 1) {
      t.tracker.onVisible('q$i');
    }
    await Future<void>.delayed(dwell * 2);

    expect(t.seen, ['q9'], reason: 'only the one the user stopped on');
    t.tracker.dispose();
  });

  test('counts one quest once, however often it comes back', () async {
    final t = trackerFor();
    t.tracker.onVisible('q1');
    await Future<void>.delayed(dwell * 2);
    t.tracker.onVisible('q2');
    await Future<void>.delayed(dwell * 2);
    t.tracker.onVisible('q1'); // scrolled back up
    await Future<void>.delayed(dwell * 2);

    expect(t.seen, ['q1', 'q2']);
    t.tracker.dispose();
  });

  test('a rebuild does not restart the dwell', () async {
    // A card that rebuilds on a timer — the feed's countdowns do — would
    // otherwise postpone its own impression forever.
    final t = trackerFor();
    t.tracker.onVisible('q1');
    for (var i = 0; i < 5; i += 1) {
      await Future<void>.delayed(dwell ~/ 4);
      t.tracker.onVisible('q1');
    }
    await Future<void>.delayed(dwell);

    expect(t.seen, ['q1']);
    t.tracker.dispose();
  });

  test('abandons the dwell when the feed is left', () async {
    final t = trackerFor();
    t.tracker.onVisible('q1');
    t.tracker.onHidden();
    await Future<void>.delayed(dwell * 2);

    expect(t.seen, isEmpty);
    t.tracker.dispose();
  });

  test('does not count a view the app was backgrounded for', () async {
    var foreground = true;
    final t = trackerFor(isForeground: () => foreground);
    t.tracker.onVisible('q1');
    foreground = false; // backgrounded mid-dwell
    await Future<void>.delayed(dwell * 2);

    expect(t.seen, isEmpty);

    // And it is not spent: the card is still there when the user returns.
    foreground = true;
    t.tracker.onHidden();
    t.tracker.onVisible('q1');
    await Future<void>.delayed(dwell * 2);
    expect(t.seen, ['q1']);
    t.tracker.dispose();
  });

  test('reports nothing after dispose', () async {
    final t = trackerFor();
    t.tracker.onVisible('q1');
    t.tracker.dispose();
    await Future<void>.delayed(dwell * 2);

    expect(t.seen, isEmpty);
  });
}
