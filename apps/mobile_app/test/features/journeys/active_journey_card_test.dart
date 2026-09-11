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
    expect(find.text('STAGE 2 OF 3'), findsOneWidget);
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
