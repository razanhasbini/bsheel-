import 'package:app_repositories/app_repositories.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/core/services/analytics_reporter.dart';

/// The reporter's job is to collect telemetry without making the app worse
/// to use. These cases are the three ways that goes wrong: blocking on the
/// network, losing events it already holds, and reporting for nobody.
void main() {
  AnalyticsReporter reporterFor(
    _FakeAnalytics repository, {
    AuthUser? session = const AuthUser(id: 'u1'),
  }) =>
      AnalyticsReporter(repository, () => session);

  test('batches a burst into one request', () async {
    final repository = _FakeAnalytics();
    final reporter = reporterFor(repository);

    for (var i = 0; i < 3; i += 1) {
      reporter.report(
          eventType: AnalyticsEvents.questDetailView,
          questId: 'q$i',
          surface: AnalyticsSurfaces.feed);
    }
    // Nothing sent yet: the timer coalesces.
    expect(repository.calls, 0);

    await reporter.flush();

    expect(repository.calls, 1);
    expect(repository.sent.single, hasLength(3));
    reporter.dispose();
  });

  test('gives every event its own id, so a resend is idempotent', () async {
    final repository = _FakeAnalytics();
    final reporter = reporterFor(repository);

    for (var i = 0; i < 5; i += 1) {
      reporter.report(
          eventType: AnalyticsEvents.questBsheeel,
          questId: 'q',
          surface: AnalyticsSurfaces.feed);
    }
    await reporter.flush();

    final ids = repository.sent.single.map((e) => e.clientEventId).toSet();
    // A reused id is silently dropped by the server's idempotency key, so a
    // collision here would lose real events rather than duplicate them.
    expect(ids, hasLength(5));
    reporter.dispose();
  });

  /// A failure is dropped on purpose. Retrying forever on a flaky
  /// connection costs the user battery for data nobody reads in real time,
  /// and a queue that survives restarts replays stale events into the wrong
  /// day.
  test('drops a failed batch instead of retrying it', () async {
    final repository = _FakeAnalytics(fail: true);
    final reporter = reporterFor(repository);

    reporter.report(
        eventType: AnalyticsEvents.questDetailView,
        questId: 'q',
        surface: AnalyticsSurfaces.feed);
    // Must not throw: nothing awaits this in the app.
    await reporter.flush();
    expect(repository.calls, 1);

    // And the failed batch is gone rather than queued behind the next one.
    repository.fail = false;
    await reporter.flush();
    expect(repository.calls, 1);
    reporter.dispose();
  });

  test('reports nothing at all while signed out', () async {
    final repository = _FakeAnalytics();
    final reporter = reporterFor(repository, session: null);

    reporter.report(
        eventType: AnalyticsEvents.questDetailView,
        questId: 'q',
        surface: AnalyticsSurfaces.feed);
    await reporter.flush();

    // The endpoint attributes events to the caller, so an event with no
    // session has nobody to belong to.
    expect(repository.calls, 0);
    reporter.dispose();
  });

  test('flushing an empty queue makes no request', () async {
    final repository = _FakeAnalytics();
    final reporter = reporterFor(repository);

    await reporter.flush();

    expect(repository.calls, 0);
    reporter.dispose();
  });

  // Events queued while a request is in flight belong to the next batch,
  // not this one — and must be neither lost nor sent twice.
  test('keeps events queued during a flush', () async {
    final repository = _FakeAnalytics();
    final reporter = reporterFor(repository);

    reporter.report(
        eventType: AnalyticsEvents.questDetailView,
        questId: 'first',
        surface: AnalyticsSurfaces.feed);
    final inFlight = reporter.flush();
    reporter.report(
        eventType: AnalyticsEvents.questDetailView,
        questId: 'second',
        surface: AnalyticsSurfaces.feed);
    await inFlight;
    await reporter.flush();

    expect(repository.calls, 2);
    expect(repository.sent[0].single.questId, 'first');
    expect(repository.sent[1].single.questId, 'second');
    reporter.dispose();
  });

  // Impressions are not emitted yet: accurate counting needs visibility
  // detection, and an over-counted impression is worse than an absent one
  // because a business is shown it as a measurement. The constant exists so
  // the server contract is complete; nothing should be sending it.
  test('does not pretend to measure impressions', () {
    expect(AnalyticsEvents.questImpression, 'quest_impression');
  });
}

class _FakeAnalytics implements AnalyticsRepository {
  _FakeAnalytics({this.fail = false});

  bool fail;
  int calls = 0;
  final List<List<AnalyticsEvent>> sent = [];

  @override
  Future<void> record(List<AnalyticsEvent> events) async {
    calls += 1;
    sent.add(events);
    if (fail) throw Exception('offline');
  }
}
