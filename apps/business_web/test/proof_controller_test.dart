import 'dart:async';

import 'package:app_models/app_models.dart';
import 'package:app_repositories/app_repositories.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:business_web/core/providers/proof_controller.dart';

/// Paging the proof wall.
///
/// A single-page read was the original bug: a business with fifty posts saw
/// twenty and nothing saying there were more. These cases are about the
/// three ways an accumulating list goes wrong — losing pages, duplicating
/// them, and losing everything when one request fails.
void main() {
  BusinessPublicProof item(String id) => BusinessPublicProof(
        submissionId: id,
        questTitle: 'Quest',
        placeName: 'Place',
        username: 'player',
        displayName: 'Player',
        mediaUrl: 'https://example.test/$id.jpg',
        mediaType: 'image',
        submittedAt: DateTime.utc(2026, 9, 1),
      );

  BusinessProofCursor cursor(String id) => BusinessProofCursor(
      beforeSubmittedAt: '2026-09-01T00:00:00Z', beforeId: id);

  ProofController controllerFor(_FakeRepository repository) =>
      ProofController(() => repository, 'b1');

  test('loads the first page and reports there is more', () async {
    final repository = _FakeRepository([
      BusinessProofPage(
          items: [item('s1'), item('s2')], nextCursor: cursor('s2')),
    ]);
    final controller = controllerFor(repository);
    await repository.settled;

    expect(controller.state.items.map((i) => i.submissionId), ['s1', 's2']);
    expect(controller.state.hasMore, isTrue);
  });

  test('appends the next page rather than replacing the first', () async {
    final repository = _FakeRepository([
      BusinessProofPage(items: [item('s1')], nextCursor: cursor('s1')),
      BusinessProofPage(items: [item('s2')], nextCursor: null),
    ]);
    final controller = controllerFor(repository);
    await repository.settled;

    await controller.loadMore();

    expect(controller.state.items.map((i) => i.submissionId), ['s1', 's2']);
    // Null cursor is how "that is all of them" is known, so the UI can say
    // so instead of leaving a button that fetches nothing.
    expect(controller.state.hasMore, isFalse);
  });

  test('passes the cursor it was given, so pages do not overlap', () async {
    final repository = _FakeRepository([
      BusinessProofPage(items: [item('s1')], nextCursor: cursor('s1')),
      const BusinessProofPage(items: []),
    ]);
    final controller = controllerFor(repository);
    await repository.settled;

    await controller.loadMore();

    expect(repository.cursors, [null, 's1']);
  });

  // Two taps on LOAD MORE, or a tap while a request is still in flight,
  // would otherwise fetch the same page twice and show every row in it
  // twice. The guard is synchronous — it flips `loadingMore` before the
  // first await — so the second call returns before issuing anything.
  test('ignores a second request while one is in flight', () async {
    final repository = _FakeRepository([
      BusinessProofPage(items: [item('s1')], nextCursor: cursor('s1')),
      BusinessProofPage(items: [item('s2')], nextCursor: null),
    ]);
    final controller = controllerFor(repository);
    await repository.settled;
    expect(repository.calls, 1);

    // Hold the next request open, then tap twice while it is in flight.
    final held = Completer<void>();
    repository.gate = held;
    final first = controller.loadMore();
    final second = controller.loadMore();
    // Release it and let both settle.
    held.complete();
    await Future.wait([first, second]);

    // Two taps, one page request. `calls` is 2 in total — the initial
    // refresh plus a single loadMore — and would be 3 if the guard were
    // missing, which is the same thing as page two appearing twice.
    expect(repository.calls, 2);
    expect(controller.state.items.map((i) => i.submissionId), ['s1', 's2']);
    expect(controller.state.hasMore, isFalse);
  });

  test('does nothing once the end is reached', () async {
    final repository = _FakeRepository([
      BusinessProofPage(items: [item('s1')], nextCursor: null),
    ]);
    final controller = controllerFor(repository);
    await repository.settled;

    await controller.loadMore();

    expect(repository.calls, 1);
  });

  /// The failure that matters. A page that fails must not discard the pages
  /// already on screen, and must keep its cursor so retrying costs one
  /// request rather than the whole list.
  test('keeps what is loaded when a later page fails, and can retry', () async {
    final repository = _FakeRepository([
      BusinessProofPage(items: [item('s1')], nextCursor: cursor('s1')),
      null, // this page throws
      BusinessProofPage(items: [item('s2')], nextCursor: null),
    ]);
    final controller = controllerFor(repository);
    await repository.settled;

    await controller.loadMore();
    expect(controller.state.items.map((i) => i.submissionId), ['s1']);
    expect(controller.state.error, isNotNull);
    expect(controller.state.hasMore, isTrue);

    await controller.loadMore();
    expect(controller.state.items.map((i) => i.submissionId), ['s1', 's2']);
    expect(controller.state.error, isNull);
  });

  test('surfaces a first-page failure as an empty errored feed', () async {
    final repository = _FakeRepository([null]);
    final controller = controllerFor(repository);
    await repository.settled;

    expect(controller.state.items, isEmpty);
    expect(controller.state.error, isNotNull);
  });
}

/// Serves the given pages in order. A null entry throws instead.
///
/// When [gate] is set, the next `proof` call parks on it until the test
/// completes it — which is how a request can be held "in flight" without
/// depending on timer or microtask ordering.
class _FakeRepository implements BusinessRepository {
  _FakeRepository(this._pages);

  final List<BusinessProofPage?> _pages;
  final List<String?> cursors = [];
  int calls = 0;
  Completer<void>? gate;

  Future<void> get settled => Future<void>.delayed(Duration.zero);

  @override
  Future<BusinessProofPage> proof(String businessId,
      {int limit = 20, BusinessProofCursor? cursor}) async {
    cursors.add(cursor?.beforeId);
    final index = calls;
    calls += 1;
    final held = gate;
    if (held != null) {
      gate = null;
      await held.future;
    }
    final page = _pages[index];
    if (page == null) throw Exception('page failed');
    return page;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
      '${invocation.memberName} is not used by this test');
}
