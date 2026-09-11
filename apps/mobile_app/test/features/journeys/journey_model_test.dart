import 'package:app_models/app_models.dart';
import 'package:flutter_test/flutter_test.dart';

/// The journey model's reading of server state.
///
/// These matter because every one of them is a place the UI could quietly
/// invent something the backend deliberately withheld, or describe a
/// sequential journey's shape for one that has no sequence.
Map<String, dynamic> stage(
  int order,
  String state, {
  bool yours = false,
  String? title,
  double? lat,
  String? target,
  String? rejectionNote,
  String? rejectedSubmissionId,
  bool appealed = false,
}) =>
    {
      'stepOrder': order,
      'state': state,
      'isYours': yours,
      'requiresLocationVerification': false,
      'appealed': appealed,
      if (title != null) 'title': title,
      if (lat != null) 'latitude': lat,
      if (lat != null) 'longitude': 35.5,
      if (target != null) 'targetUsername': target,
      if (rejectionNote != null) 'rejectionNote': rejectionNote,
      if (rejectedSubmissionId != null)
        'rejectedSubmissionId': rejectedSubmissionId,
    };

Map<String, dynamic> run({
  required List<Map<String, dynamic>> stages,
  String rule = 'sequential',
  String kind = 'solo',
  String status = 'active',
  int completed = 1,
  Map<String, dynamic>? next,
  Map<String, dynamic>? unseen,
}) =>
    {
      'runId': 'run-1',
      'chainId': 'chain-1',
      'title': 'Byblos Journey',
      'description': '',
      'runKind': kind,
      'completionRule': rule,
      'status': status,
      'completedSteps': completed,
      'totalSteps': stages.length,
      'stages': stages,
      'nextForViewer': next,
      'unseenUnlock': unseen,
    };

void main() {
  test('a hidden checkpoint arrives with nothing to reveal', () {
    final parsed = JourneyRun.fromJson(run(stages: [
      stage(1, 'COMPLETED', title: 'Old Souk'),
      stage(2, 'LOCKED'),
    ]));
    final locked = parsed.stages[1];
    // The server omits it rather than sending it to be hidden, so there is
    // nothing local that could leak it — and nothing to draw on a map.
    expect(locked.title, isNull);
    expect(locked.hasCoordinates, isFalse);
  });

  test('a route is only drawable between checkpoints we were told about', () {
    final parsed = JourneyRun.fromJson(run(stages: [
      stage(1, 'COMPLETED', title: 'Old Souk', lat: 34.1),
      stage(2, 'LOCKED'),
    ]));
    expect(parsed.stages.where((s) => s.hasCoordinates).length, 1);
  });

  test('an any-order journey counts down instead of naming a next stage', () {
    final parsed = JourneyRun.fromJson(run(
      rule: 'all_steps_any_order',
      completed: 1,
      stages: [
        stage(1, 'COMPLETED', title: 'Lebanon'),
        stage(2, 'AVAILABLE', yours: true, title: 'Qatar'),
        stage(3, 'AVAILABLE', yours: true, title: 'Palestine'),
      ],
    ));
    expect(parsed.orderMatters, isFalse);
    // "Stage 2 of 3" would be a lie when two checkpoints are open at once.
    expect(parsed.remaining, 2);
  });

  test('under review is not the same as nothing to do', () {
    final parsed = JourneyRun.fromJson(run(
      completed: 0,
      stages: [
        stage(1, 'UNDER_REVIEW', yours: true, title: 'Old Souk'),
        stage(2, 'LOCKED'),
      ],
    ));
    expect(parsed.isUnderReview, isTrue);
    expect(parsed.canContinue, isFalse);
  });

  test('a relay checkpoint that is not yours offers no Continue', () {
    final parsed = JourneyRun.fromJson(run(
      kind: 'group',
      completed: 1,
      stages: [
        stage(1, 'COMPLETED', title: 'Old Souk', target: 'razan'),
        stage(2, 'AVAILABLE', title: 'Castle', target: 'tayseer'),
      ],
      next: null,
    ));
    expect(parsed.isRelay, isTrue);
    expect(parsed.canContinue, isFalse);
    expect(parsed.stages[1].targetUsername, 'tayseer');
    expect(parsed.stages[1].isYours, isFalse);
  });

  test('an unseen unlock is carried from the server, not inferred', () {
    final withUnlock = JourneyRun.fromJson(run(
      stages: [stage(1, 'COMPLETED'), stage(2, 'AVAILABLE', yours: true)],
      unseen: {'stepOrder': 2, 'questId': 'q2'},
    ));
    expect(withUnlock.unseenUnlock?.stepOrder, 2);

    // Once acknowledged the server stops sending it, and that is the only
    // thing that stops the celebration replaying.
    final acknowledged = JourneyRun.fromJson(run(
      stages: [stage(1, 'COMPLETED'), stage(2, 'AVAILABLE', yours: true)],
    ));
    expect(acknowledged.unseenUnlock, isNull);
  });

  test('a completed journey offers no next checkpoint', () {
    final parsed = JourneyRun.fromJson(run(
      status: 'completed',
      completed: 2,
      stages: [stage(1, 'COMPLETED'), stage(2, 'COMPLETED')],
    ));
    expect(parsed.isCompleted, isTrue);
    expect(parsed.canContinue, isFalse);
    expect(parsed.progress, 1.0);
  });

  test('the Home card knows which backend concept it came from', () {
    final chain = JourneyProgress.fromJson({
      'kind': 'chain',
      'id': 'c1',
      'runId': 'r1',
      'name': 'Byblos',
      'description': '',
      'totalQuests': 3,
      'completedQuests': 1,
      'canContinue': true,
      'nextCheckpointName': 'Castle',
    });
    final collection = JourneyProgress.fromJson({
      'kind': 'collection',
      'id': 'x1',
      'name': 'Discover Lebanon',
      'description': '',
      'totalQuests': 50,
      'completedQuests': 12,
    });
    // Tagged, not merged: one offers CONTINUE, the other EXPLORE.
    expect(chain.isChain, isTrue);
    expect(chain.canContinue, isTrue);
    expect(collection.isChain, isFalse);
    expect(collection.canContinue, isFalse);
  });
}
