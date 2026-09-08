import 'package:app_models/app_models.dart';
import 'package:app_contracts/app_contracts.dart';
import 'package:test/test.dart';

Map<String, dynamic> qotdRow({Map<String, dynamic> overrides = const {}}) => {
      'id': 'qotd-1',
      'display_date': '2026-05-12',
      'ticket_no': '1234',
      'bonus_xp': 50,
      'quest_id': 'quest-1',
      'quest_title': 'Photo walk',
      'quest_description': 'Shoot 3 frames.',
      'quest_category': QuestCategory.creativity,
      'quest_difficulty': QuestDifficulty.hard,
      'quest_xp_reward': 150,
      'quest_duration_hours': 6,
      ...overrides,
    };

void main() {
  group('QuestOfTheDayModel.fromRow', () {
    test('parses the full RPC row', () {
      final qotd = QuestOfTheDayModel.fromRow(qotdRow());

      expect(qotd.id, 'qotd-1');
      expect(qotd.displayDate, DateTime(2026, 5, 12));
      expect(qotd.ticketNo, '1234');
      expect(qotd.bonusXp, 50);
      expect(qotd.questId, 'quest-1');
      expect(qotd.questTitle, 'Photo walk');
      expect(qotd.questDescription, 'Shoot 3 frames.');
      expect(qotd.questCategory, 'creativity');
      expect(qotd.questDifficulty, 'hard');
      expect(qotd.questXpReward, 150);
      expect(qotd.questDurationHours, 6);
    });

    test('id and quest_id are hard requirements', () {
      for (final key in ['id', 'quest_id']) {
        final row = qotdRow()..remove(key);
        expect(
          () => QuestOfTheDayModel.fromRow(row),
          throwsA(isA<TypeError>()),
          reason: 'a missing $key should throw',
        );
      }
    });

    group('display_date', () {
      test('accepts a date-only string', () {
        expect(
          QuestOfTheDayModel.fromRow(qotdRow(overrides: {
            'display_date': '2026-12-31',
          })).displayDate,
          DateTime(2026, 12, 31),
        );
      });

      test('accepts a DateTime instance', () {
        final at = DateTime.utc(2026, 5, 12);
        expect(
          QuestOfTheDayModel.fromRow(qotdRow(overrides: {
            'display_date': at,
          })).displayDate,
          at,
        );
      });

      test('a bad type or an unparseable string degrades to the epoch', () {
        // Regression guard. This used to raise ArgumentError on a wrong
        // type and FormatException on 'tomorrow', and the QOTD provider's
        // catch block turns any throw here into a silently hidden widget.
        // A required timestamp degrades to the Unix epoch instead — same
        // rule as every other model in the package.
        final epoch = DateTime.utc(1970);
        for (final bad in <Object?>[null, 20260512, true, 'tomorrow']) {
          expect(
            QuestOfTheDayModel.fromRow(
              qotdRow(overrides: {'display_date': bad}),
            ).displayDate,
            epoch,
            reason: 'display_date=$bad should degrade to the epoch',
          );
        }
        final row = qotdRow()..remove('display_date');
        expect(QuestOfTheDayModel.fromRow(row).displayDate, epoch);
      });
    });

    group('numeric coercion is deliberately permissive', () {
      test('num-typed integers are accepted and rounded down', () {
        final qotd = QuestOfTheDayModel.fromRow(qotdRow(overrides: {
          'bonus_xp': 50.0,
          'quest_xp_reward': 150.9,
          'quest_duration_hours': 6.4,
        }));

        expect(qotd.bonusXp, 50);
        expect(qotd.questXpReward, 150);
        expect(qotd.questDurationHours, 6);
      });

      test('numeric strings parse', () {
        final qotd = QuestOfTheDayModel.fromRow(qotdRow(overrides: {
          'bonus_xp': '50',
          'quest_xp_reward': '150',
        }));

        expect(qotd.bonusXp, 50);
        expect(qotd.questXpReward, 150);
      });

      test('nulls use each column fallback (duration keeps the 4h default)',
          () {
        final qotd = QuestOfTheDayModel.fromRow(qotdRow(overrides: {
          'bonus_xp': null,
          'quest_xp_reward': null,
          'quest_duration_hours': null,
        }));

        expect(qotd.bonusXp, 0);
        expect(qotd.questXpReward, 0);
        expect(qotd.questDurationHours, 4);
      });

      test('a non-numeric, non-string value uses the fallback', () {
        final qotd = QuestOfTheDayModel.fromRow(qotdRow(overrides: {
          'bonus_xp': true,
          'quest_duration_hours': false,
        }));

        expect(qotd.bonusXp, 0);
        expect(qotd.questDurationHours, 4);
      });

      test('the duration is clamped to the same 1..168 range as QuestModel',
          () {
        // Regression guard. QuestModel applied a 1h floor and this model
        // applied nothing, so the same bad duration_hours reached the QOTD
        // ticket as 0 (or as 100000). Both now mirror the DB CHECK
        // `duration_hours between 1 and 168`.
        expect(
          QuestOfTheDayModel.fromRow(qotdRow(overrides: {
            'quest_duration_hours': 0,
          })).questDurationHours,
          4,
        );
        expect(
          QuestOfTheDayModel.fromRow(qotdRow(overrides: {
            'quest_duration_hours': -3,
          })).questDurationHours,
          4,
        );
        expect(
          QuestOfTheDayModel.fromRow(qotdRow(overrides: {
            'quest_duration_hours': 100000,
          })).questDurationHours,
          168,
        );
        expect(
          QuestOfTheDayModel.fromRow(qotdRow(overrides: {
            'quest_duration_hours': 168,
          })).questDurationHours,
          168,
        );
      });
    });

    test('missing quest text columns coerce to empty strings', () {
      final row = qotdRow()
        ..remove('quest_title')
        ..remove('quest_description')
        ..remove('quest_category')
        ..remove('quest_difficulty');
      final qotd = QuestOfTheDayModel.fromRow(row);

      expect(qotd.questTitle, isEmpty);
      expect(qotd.questDescription, isEmpty);
      expect(qotd.questCategory, isEmpty);
      // Difficulty is the one with a real default.
      expect(qotd.questDifficulty, QuestDifficulty.medium);
    });
  });

  group('QuestOfTheDayModel.totalXpReward', () {
    test('sums the base reward and the curated bonus', () {
      expect(QuestOfTheDayModel.fromRow(qotdRow()).totalXpReward, 200);
    });

    test('is just the base reward when there is no bonus', () {
      expect(
        QuestOfTheDayModel.fromRow(qotdRow(overrides: {'bonus_xp': 0}))
            .totalXpReward,
        150,
      );
    });

    test('a negative bonus subtracts (no clamping)', () {
      expect(
        QuestOfTheDayModel.fromRow(qotdRow(overrides: {'bonus_xp': -25}))
            .totalXpReward,
        125,
      );
    });
  });

  group('QuestOfTheDayModel.displayTicketNo', () {
    test('uses the admin-set ticket number verbatim', () {
      expect(QuestOfTheDayModel.fromRow(qotdRow()).displayTicketNo, '1234');
    });

    test('trims surrounding whitespace', () {
      expect(
        QuestOfTheDayModel.fromRow(qotdRow(overrides: {
          'ticket_no': '  1234  ',
        })).displayTicketNo,
        '1234',
      );
    });

    test('falls back to a zero-padded MMDD when null', () {
      final row = qotdRow()..remove('ticket_no');
      expect(QuestOfTheDayModel.fromRow(row).displayTicketNo, '0512');
    });

    test('falls back for an empty or whitespace-only ticket', () {
      for (final blank in ['', '   ']) {
        expect(
          QuestOfTheDayModel.fromRow(qotdRow(overrides: {
            'ticket_no': blank,
          })).displayTicketNo,
          '0512',
          reason: 'ticket_no="$blank" should fall back',
        );
      }
    });

    test('pads single-digit months and days to four characters', () {
      final qotd = QuestOfTheDayModel.fromRow(qotdRow(overrides: {
        'display_date': '2026-01-02',
        'ticket_no': null,
      }));

      expect(qotd.displayTicketNo, '0102');
      expect(qotd.displayTicketNo.length, 4);
    });

    test('a two-digit month and day need no padding', () {
      final qotd = QuestOfTheDayModel.fromRow(qotdRow(overrides: {
        'display_date': '2026-11-25',
        'ticket_no': null,
      }));

      expect(qotd.displayTicketNo, '1125');
    });
  });

  group('QuestOfTheDayModel value equality', () {
    // Regression guard. Equality used to be identity, so the home page
    // rebuilt the QOTD ticket on every unchanged re-fetch.
    test('two rows parsed from the same payload are equal', () {
      expect(
        QuestOfTheDayModel.fromRow(qotdRow()),
        QuestOfTheDayModel.fromRow(qotdRow()),
      );
      expect(
        QuestOfTheDayModel.fromRow(qotdRow()).hashCode,
        QuestOfTheDayModel.fromRow(qotdRow()).hashCode,
      );
    });

    test('a differing bonus breaks equality', () {
      expect(
        QuestOfTheDayModel.fromRow(qotdRow(overrides: {'bonus_xp': 60})),
        isNot(QuestOfTheDayModel.fromRow(qotdRow())),
      );
    });
  });
}
