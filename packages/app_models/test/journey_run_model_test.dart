import 'package:app_models/app_models.dart';
import 'package:test/test.dart';

/// What Home is allowed to hide because of a journey.
///
/// `canContinue` and `hasCheckpointWaiting` differ by exactly one case — a
/// rejection — and the difference is load-bearing. Home keys the quest
/// generator off the narrower one, and when it keyed off the wider one a
/// single rejected photo took every quest type off the screen until the
/// player dealt with it.
Map<String, dynamic> stage(int order, String state) => {
      'stepOrder': order,
      'state': state,
      'isYours': true,
      'requiresLocationVerification': false,
    };

JourneyRun runWith(String nextState) => JourneyRun.fromJson({
      'runId': 'r',
      'chainId': 'c',
      'title': 'Three gates',
      'description': '',
      'runKind': 'solo',
      'completionRule': 'sequential',
      'status': 'active',
      'completedSteps': 0,
      'totalSteps': 2,
      'stages': [stage(1, nextState), stage(2, 'LOCKED')],
      'nextForViewer': stage(1, nextState),
    });

void main() {
  test('a live checkpoint holds the rest of Home back', () {
    for (final state in ['AVAILABLE', 'IN_PROGRESS']) {
      final run = runWith(state);
      expect(run.canContinue, isTrue, reason: state);
      expect(run.hasCheckpointWaiting, isTrue, reason: state);
    }
  });

  // The regression. A rejected checkpoint is something the player MAY come
  // back to, not something the journey is holding open for them — so it
  // must still offer the action, and must not close the rest of the app.
  test('a rejected checkpoint offers itself without closing Home', () {
    final run = runWith('REJECTED');
    expect(run.canContinue, isTrue);
    expect(run.hasCheckpointWaiting, isFalse);
  });

  test('a journey with nothing to do holds nothing back', () {
    final run = JourneyRun.fromJson({
      'runId': 'r',
      'chainId': 'c',
      'title': 'Three gates',
      'description': '',
      'runKind': 'group',
      'completionRule': 'sequential',
      'status': 'active',
      'completedSteps': 1,
      'totalSteps': 2,
      'stages': [stage(1, 'COMPLETED'), stage(2, 'UNDER_REVIEW')],
    });
    expect(run.canContinue, isFalse);
    expect(run.hasCheckpointWaiting, isFalse);
  });
}
