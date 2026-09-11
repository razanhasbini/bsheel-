import 'package:app_core/app_core.dart';
import 'package:app_models/app_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/features/quests/presentation/widgets/active_journey_card.dart';

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
    expect(find.text('Old Souk'), findsOneWidget);
    expect(find.text('Byblos Castle'), findsOneWidget);
    expect(find.text('CONTINUE JOURNEY'), findsOneWidget);
  });

  testWidgets('a hidden checkpoint is named as a mystery, not invented',
      (tester) async {
    await pump(
      tester,
      JourneyRun.fromJson(run(
        completed: 1,
        stages: [stage(1, 'COMPLETED', title: 'Old Souk'), stage(3, 'LOCKED')],
      )),
    );
    expect(find.text('A checkpoint waiting to be found'), findsOneWidget);
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
    expect(find.text('CHECKPOINT UNDER REVIEW'), findsOneWidget);
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
    expect(find.text('@tayseer is up next.'), findsOneWidget);
    expect(find.text('CONTINUE JOURNEY'), findsNothing);
  });
}
