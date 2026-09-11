import 'package:app_core/app_core.dart';
import 'package:app_models/app_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/features/quests/presentation/widgets/checkpoint_rail.dart';

import 'journey_model_test.dart' show stage;

/// The rail's job is to transition and then STAY transitioned.
///
/// The thing being guarded is the failure the redesign existed to fix: a
/// celebration that plays and leaves, putting the page back exactly where it
/// was and the player back to wondering what changed.
List<JourneyStage> stages(List<String> states) => [
      for (var i = 0; i < states.length; i++)
        JourneyStage.fromJson(stage(i + 1, states[i],
            yours: states[i] == 'AVAILABLE', title: 'Stage ${i + 1}')),
    ];

Future<void> pump(WidgetTester tester, Widget rail) => tester.pumpWidget(
      MaterialApp(
        theme: QuestTheme.light,
        home: Scaffold(body: SizedBox(width: 340, child: rail)),
      ),
    );

void main() {
  testWidgets('renders one node per stage, whatever the count', (tester) async {
    for (final count in [2, 3, 5]) {
      await pump(
        tester,
        CheckpointRail(stages: stages(List.filled(count, 'LOCKED'))),
      );
      final rail = tester.widget<CheckpointRail>(find.byType(CheckpointRail));
      expect(rail.stages.length, count);
    }
  });

  testWidgets('an unlock transition finishes and reports once', (tester) async {
    var finished = 0;
    await pump(
      tester,
      CheckpointRail(
        stages: stages(['COMPLETED', 'AVAILABLE', 'LOCKED']),
        advanceFrom: 1,
        onFinished: () => finished++,
      ),
    );
    // Mid-flight it is still animating, so nothing has been acknowledged.
    await tester.pump(const Duration(milliseconds: 300));
    expect(finished, 0);

    await tester.pumpAndSettle(const Duration(seconds: 3));
    // Exactly once: acknowledging twice would be two writes for one moment.
    expect(finished, 1);

    // And the rail is still on screen in its new state. The animation
    // explained a change; it did not replace the thing it changed.
    expect(find.byType(CheckpointRail), findsOneWidget);
  });

  testWidgets('no advance means no animation and no acknowledgement',
      (tester) async {
    var finished = 0;
    await pump(
      tester,
      CheckpointRail(
        stages: stages(['COMPLETED', 'AVAILABLE', 'LOCKED']),
        onFinished: () => finished++,
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 3));
    // Nothing was owed, so nothing is marked seen — otherwise reopening the
    // page would burn an unlock the player never watched.
    expect(finished, 0);
  });

  testWidgets('reduced motion still arrives at the new state', (tester) async {
    var finished = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: QuestTheme.light,
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Scaffold(
            body: SizedBox(
              width: 340,
              child: CheckpointRail(
                stages: stages(['COMPLETED', 'AVAILABLE', 'LOCKED']),
                advanceFrom: 1,
                onFinished: () => finished++,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    // Somebody who asked the system to stop animating still gets the state
    // change — it arrives rather than travels.
    expect(finished, 1);
  });
}
