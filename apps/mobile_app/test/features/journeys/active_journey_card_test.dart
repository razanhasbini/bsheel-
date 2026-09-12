import 'package:app_core/app_core.dart';
import 'package:app_models/app_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/features/quests/presentation/widgets/active_journey_card.dart';
import 'package:mobile_app/features/quests/presentation/widgets/checkpoint_rail.dart';

import 'journey_model_test.dart' show run, stage;

/// What the card says, in each state a journey can be in.
///
/// The first test is the bug that started the whole task: an approved stage
/// used to take the journey off Home entirely.
Future<void> pump(WidgetTester tester, JourneyRun journey) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: QuestTheme.light,
        home: Scaffold(body: ActiveJourneyCard(run: journey)),
      ),
    ),
  );
}

void main() {
  underReviewNeverLooksDone();
  rejectionIsVisibleOnHome();
  lastStageDoesNotLookFinished();
  testWidgets('a journey survives its first checkpoint being approved',
      (tester) async {
    await pump(
      tester,
      JourneyRun.fromJson(run(
        completed: 1,
        stages: [
          stage(1, 'COMPLETED', title: 'Old Souk'),
          stage(2, 'AVAILABLE', yours: true, title: 'Byblos Castle'),
          stage(3, 'LOCKED'),
        ],
        next: stage(2, 'AVAILABLE', yours: true, title: 'Byblos Castle'),
      )),
    );
    expect(find.text('BYBLOS JOURNEY'), findsOneWidget);
    expect(find.text('STAGE 2 OF 3 · 2 LEFT'), findsOneWidget);
    // A summary, not the whole journey: the current checkpoint by name,
    // and one action. The rest lives on the detail page.
    expect(find.text('BYBLOS CASTLE'), findsOneWidget);
    expect(find.text('CONTINUE JOURNEY'), findsOneWidget);
  });

  testWidgets('a hidden current checkpoint is named as a mystery',
      (tester) async {
    await pump(
      tester,
      JourneyRun.fromJson(run(
        completed: 1,
        stages: [
          stage(1, 'COMPLETED', title: 'Old Souk'),
          stage(2, 'AVAILABLE', yours: true)
        ],
        next: stage(2, 'AVAILABLE', yours: true),
      )),
    );
    expect(find.text('A CHECKPOINT WAITING TO BE FOUND'), findsOneWidget);
  });

  testWidgets('three stages draw three checkpoints, not a progress bar',
      (tester) async {
    await pump(
      tester,
      JourneyRun.fromJson(run(
        completed: 2,
        stages: [
          stage(1, 'COMPLETED', title: 'One'),
          stage(2, 'COMPLETED', title: 'Two'),
          stage(3, 'AVAILABLE', yours: true, title: 'Three'),
        ],
        next: stage(3, 'AVAILABLE', yours: true, title: 'Three'),
      )),
    );
    // The rail is the visual language; a percentage bar cannot say which
    // checkpoint you are standing on.
    expect(find.byType(CheckpointRail), findsOneWidget);
    final rail = tester.widget<CheckpointRail>(find.byType(CheckpointRail));
    expect(rail.stages.length, 3);
  });

  testWidgets('under review shows the wait, not a Continue button',
      (tester) async {
    await pump(
      tester,
      JourneyRun.fromJson(run(
        completed: 0,
        stages: [
          stage(1, 'UNDER_REVIEW', yours: true, title: 'Old Souk'),
          stage(2, 'LOCKED'),
        ],
      )),
    );
    expect(find.text('UNDER REVIEW'), findsOneWidget);
    // Offering CONTINUE here would be a button the server refuses.
    expect(find.text('CONTINUE JOURNEY'), findsNothing);
  });

  testWidgets('an any-order journey counts down instead of naming a stage',
      (tester) async {
    await pump(
      tester,
      JourneyRun.fromJson(run(
        rule: 'all_steps_any_order',
        completed: 1,
        stages: [
          stage(1, 'COMPLETED', title: 'Lebanon'),
          stage(2, 'AVAILABLE', yours: true, title: 'Qatar'),
          stage(3, 'AVAILABLE', yours: true, title: 'Palestine'),
        ],
        next: stage(2, 'AVAILABLE', yours: true, title: 'Qatar'),
      )),
    );
    expect(find.text('2 CHECKPOINTS REMAINING'), findsOneWidget);
    expect(find.textContaining('STAGE 2 OF'), findsNothing);
  });

  testWidgets('a relay names whose turn it is and offers nothing to others',
      (tester) async {
    await pump(
      tester,
      JourneyRun.fromJson(run(
        kind: 'group',
        completed: 1,
        stages: [
          stage(1, 'COMPLETED', title: 'Old Souk', target: 'razan'),
          stage(2, 'AVAILABLE', title: 'Byblos Castle', target: 'tayseer'),
        ],
      )),
    );
    expect(find.text('RELAY'), findsOneWidget);
    // The button says whose turn it is rather than offering something the
    // server would refuse.
    expect(find.text('WAITING FOR @TAYSEER'), findsOneWidget);
    expect(find.text('CONTINUE JOURNEY'), findsNothing);
  });
}

/// A checkpoint awaiting a decision must never look finished.
///
/// The rule the product asks for: submitted is YELLOW and says pending; only
/// an approval turns it green. Getting this wrong tells somebody their quest
/// was accepted when a moderator has not looked at it yet, and they stop
/// waiting for the answer.
void underReviewNeverLooksDone() {
  testWidgets('a submitted checkpoint is pending, not a green tick',
      (tester) async {
    await pump(
      tester,
      JourneyRun.fromJson(run(
        completed: 1,
        stages: [
          stage(1, 'COMPLETED', title: 'Old Souk'),
          stage(2, 'UNDER_REVIEW', yours: true, title: 'Byblos Castle'),
          stage(3, 'LOCKED'),
        ],
      )),
    );

    // The card says it in words…
    expect(find.text('UNDER REVIEW'), findsOneWidget);
    // …and offers nothing to press, because there is nothing to do yet.
    expect(find.text('CONTINUE JOURNEY'), findsNothing);

    // And the rail carries the real state through rather than flattening
    // it — one completed, one pending, one locked.
    final rail = tester.widget<CheckpointRail>(find.byType(CheckpointRail));
    expect(rail.stages[0].state, StageState.completed);
    expect(rail.stages[1].state, StageState.underReview);
    expect(rail.stages[2].state, StageState.locked);
  });

  testWidgets('progress does not count a checkpoint still under review',
      (tester) async {
    final journey = JourneyRun.fromJson(run(
      completed: 1,
      stages: [
        stage(1, 'COMPLETED', title: 'Old Souk'),
        stage(2, 'UNDER_REVIEW', yours: true, title: 'Byblos Castle'),
        stage(3, 'LOCKED'),
      ],
    ));
    await pump(tester, journey);
    // One of three, not two: submitting is not finishing.
    expect(journey.completedSteps, 1);
    expect(find.text('STAGE 2 OF 3 · 2 LEFT'), findsOneWidget);
  });
}

/// The label on the last checkpoint of a route, which used to read as the
/// whole journey being finished.
///
/// "STAGE 3 OF 3" is positionally true and looks exactly like 3/3 complete.
/// A player two stops into a three-stop route saw it, believed they were
/// done, and went looking for the completion that was never owed to them.
/// The count of what remains is the half that cannot be misread.
void lastStageDoesNotLookFinished() {
  testWidgets('the final checkpoint says what is left, not just where you are',
      (tester) async {
    await pump(
      tester,
      JourneyRun.fromJson(run(
        completed: 2,
        stages: [
          stage(1, 'COMPLETED', title: 'Old Souk'),
          stage(2, 'COMPLETED', title: 'Byblos Castle'),
          stage(3, 'AVAILABLE', yours: true, title: 'The Last Gate'),
        ],
        next: stage(3, 'AVAILABLE', yours: true, title: 'The Last Gate'),
      )),
    );
    expect(find.text('STAGE 3 OF 3'), findsNothing);
    expect(find.text('STAGE 3 OF 3 · 1 LEFT'), findsOneWidget);
  });
}

/// A checkpoint that came back rejected.
///
/// The bug: the card said nothing at all. A solo run's step 1 has no unlock
/// row, so `isYours` was false, so `nextForViewer` skipped it and the
/// journey reported "nothing to do" over a rejection nobody had answered.
/// Home is where a player finds out a checkpoint was turned down — they are
/// not going to open the journey to discover it.
void rejectionIsVisibleOnHome() {
  testWidgets('names the rejection and offers the checkpoint again',
      (tester) async {
    final rejected = stage(1, 'REJECTED',
        yours: true,
        title: 'Find the sea gate',
        rejectionNote: 'That is a screenshot, not a sea gate.',
        rejectedSubmissionId: 'sub-1');
    await pump(
      tester,
      JourneyRun.fromJson(run(
        completed: 0,
        stages: [rejected, stage(2, 'LOCKED'), stage(3, 'LOCKED')],
        next: rejected,
      )),
    );

    expect(find.textContaining('REJECTED'), findsWidgets);
    // "Continue" is the wrong word for going back to something turned down,
    // and the right word is also the reassurance: the attempt is not spent.
    expect(find.text('TRY CHECKPOINT AGAIN'), findsOneWidget);
    expect(find.text('CONTINUE JOURNEY'), findsNothing);
  });

  testWidgets('says an appeal is in rather than asking for another',
      (tester) async {
    final appealed = stage(1, 'REJECTED',
        yours: true,
        title: 'Find the sea gate',
        rejectionNote: 'Not the gate.',
        rejectedSubmissionId: 'sub-1',
        appealed: true);
    await pump(
      tester,
      JourneyRun.fromJson(run(
        completed: 0,
        stages: [appealed, stage(2, 'LOCKED')],
        next: appealed,
      )),
    );
    expect(find.textContaining('APPEAL SENT'), findsOneWidget);
  });
}
