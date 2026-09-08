import 'package:app_models/app_models.dart';
import 'package:supabase_contracts/supabase_contracts.dart';
import 'package:test/test.dart';

/// Wire shape of a `quests` row as PostgREST returns it.
Map<String, dynamic> questRow({Map<String, dynamic> overrides = const {}}) => {
      QuestColumns.id: 'quest-1',
      QuestColumns.title: 'Take a photo walk',
      QuestColumns.description: 'Walk and shoot 3 frames.',
      QuestColumns.category: QuestCategory.creativity,
      QuestColumns.difficulty: QuestDifficulty.medium,
      QuestColumns.xpReward: 150,
      QuestColumns.durationHours: 4,
      QuestColumns.isActive: true,
      QuestColumns.createdBy: 'admin-1',
      QuestColumns.createdAt: '2026-05-03T12:00:00Z',
      QuestColumns.updatedAt: '2026-05-04T09:30:00Z',
      ...overrides,
    };

void main() {
  group('QuestModel.fromJson', () {
    test('parses the full snake_case wire row', () {
      final quest = QuestModel.fromJson(questRow());

      expect(quest.id, 'quest-1');
      expect(quest.title, 'Take a photo walk');
      expect(quest.description, 'Walk and shoot 3 frames.');
      expect(quest.category, 'creativity');
      expect(quest.difficulty, 'medium');
      expect(quest.xpReward, 150);
      expect(quest.durationHours, 4);
      expect(quest.isActive, isTrue);
      expect(quest.createdBy, 'admin-1');
      expect(quest.createdAt, DateTime.utc(2026, 5, 3, 12));
      expect(quest.updatedAt, DateTime.utc(2026, 5, 4, 9, 30));
    });

    test('missing string columns coerce to empty strings, not null', () {
      final quest = QuestModel.fromJson({
        QuestColumns.createdAt: '2026-05-03T12:00:00Z',
      });

      expect(quest.id, isEmpty);
      expect(quest.title, isEmpty);
      expect(quest.description, isEmpty);
      expect(quest.category, isEmpty);
      expect(quest.difficulty, isEmpty);
    });

    test('explicit nulls coerce to empty strings too', () {
      final quest = QuestModel.fromJson(questRow(overrides: {
        QuestColumns.id: null,
        QuestColumns.title: null,
        QuestColumns.category: null,
      }));

      expect(quest.id, isEmpty);
      expect(quest.title, isEmpty);
      expect(quest.category, isEmpty);
    });

    test('a missing or malformed created_at degrades to the epoch', () {
      // Regression guard. `_toDateTime` did `value as String` with no null
      // guard, so an incomplete select (or a NULL created_at) blew up the
      // whole list parse instead of yielding one degraded row.
      final epoch = DateTime.utc(1970);

      expect(QuestModel.fromJson({}).createdAt, epoch);
      expect(
        QuestModel.fromJson(questRow(overrides: {QuestColumns.createdAt: null}))
            .createdAt,
        epoch,
      );
      expect(
        QuestModel.fromJson(
          questRow(overrides: {QuestColumns.createdAt: 'someday'}),
        ).createdAt,
        epoch,
      );
    });

    test('an unparseable updated_at degrades to null, not to the epoch', () {
      expect(
        QuestModel.fromJson(
          questRow(overrides: {QuestColumns.updatedAt: 'someday'}),
        ).updatedAt,
        isNull,
      );
    });

    test('a DateTime instance passes through un-reparsed', () {
      final now = DateTime.utc(2026, 1, 2, 3, 4);
      final quest = QuestModel.fromJson(questRow(overrides: {
        QuestColumns.createdAt: now,
        QuestColumns.updatedAt: now,
      }));

      expect(quest.createdAt, now);
      expect(quest.updatedAt, now);
    });

    test('a missing updated_at stays null', () {
      final row = questRow()..remove(QuestColumns.updatedAt);
      expect(QuestModel.fromJson(row).updatedAt, isNull);
    });

    group('xp_reward coercion', () {
      test('numeric string parses', () {
        expect(
          QuestModel.fromJson(
            questRow(overrides: {QuestColumns.xpReward: '250'}),
          ).xpReward,
          250,
        );
      });

      test('double truncates toward zero', () {
        expect(
          QuestModel.fromJson(
            questRow(overrides: {QuestColumns.xpReward: 99.9}),
          ).xpReward,
          99,
        );
      });

      test('non-numeric string falls back to 0', () {
        expect(
          QuestModel.fromJson(
            questRow(overrides: {QuestColumns.xpReward: 'lots'}),
          ).xpReward,
          0,
        );
      });

      test('a decimal string truncates exactly like the num does', () {
        // Regression guard. '99.9' used NOT to be truncated the way the num
        // 99.9 is — int.tryParse returns null, so the reward silently
        // became 0. The shared coercion falls back to num.tryParse.
        expect(
          QuestModel.fromJson(
            questRow(overrides: {QuestColumns.xpReward: '99.9'}),
          ).xpReward,
          99,
        );
      });

      test('missing column falls back to 0', () {
        final row = questRow()..remove(QuestColumns.xpReward);
        expect(QuestModel.fromJson(row).xpReward, 0);
      });
    });

    group('duration_hours normalisation', () {
      test('zero, negative and missing all normalise to the 4h default', () {
        for (final bad in <Object?>[0, -3, null, 'abc']) {
          expect(
            QuestModel.fromJson(
              questRow(overrides: {QuestColumns.durationHours: bad}),
            ).durationHours,
            4,
            reason: 'duration_hours=$bad should normalise to 4',
          );
        }
      });

      test('1 hour is kept (the lower bound is inclusive)', () {
        expect(
          QuestModel.fromJson(
            questRow(overrides: {QuestColumns.durationHours: 1}),
          ).durationHours,
          1,
        );
      });

      test('168 hours is kept (the upper bound is inclusive)', () {
        expect(
          QuestModel.fromJson(
            questRow(overrides: {QuestColumns.durationHours: 168}),
          ).durationHours,
          168,
        );
      });

      test('an over-long duration clamps to the 168h DB ceiling', () {
        // Regression guard. Only the lower bound used to be normalised, so
        // a bad admin write of 100000 reached the countdown timer unchanged
        // even though the DB CHECK (duration_hours between 1 and 168)
        // would have rejected it.
        expect(
          QuestModel.fromJson(
            questRow(overrides: {QuestColumns.durationHours: 100000}),
          ).durationHours,
          168,
        );
        expect(
          QuestModel.fromJson(
            questRow(overrides: {QuestColumns.durationHours: '169'}),
          ).durationHours,
          168,
        );
      });

      test('a numeric-string duration parses', () {
        expect(
          QuestModel.fromJson(
            questRow(overrides: {QuestColumns.durationHours: '12'}),
          ).durationHours,
          12,
        );
      });
    });

    group('is_active coercion', () {
      test('false stays false', () {
        expect(
          QuestModel.fromJson(
            questRow(overrides: {QuestColumns.isActive: false}),
          ).isActive,
          isFalse,
        );
      });

      test('null and missing default to true', () {
        expect(
          QuestModel.fromJson(
            questRow(overrides: {QuestColumns.isActive: null}),
          ).isActive,
          isTrue,
        );
        final row = questRow()..remove(QuestColumns.isActive);
        expect(QuestModel.fromJson(row).isActive, isTrue);
      });

      test('a stringly-typed "false" now coerces instead of throwing', () {
        // Regression guard. `as bool?` was a hard cast, so a backend that
        // ever serialised booleans as strings failed the whole parse.
        expect(
          QuestModel.fromJson(
            questRow(overrides: {QuestColumns.isActive: 'false'}),
          ).isActive,
          isFalse,
        );
        expect(
          QuestModel.fromJson(
            questRow(overrides: {QuestColumns.isActive: 'true'}),
          ).isActive,
          isTrue,
        );
      });
    });

    test('a non-string created_by throws (hard cast)', () {
      expect(
        () => QuestModel.fromJson(
          questRow(overrides: {QuestColumns.createdBy: 7}),
        ),
        throwsA(isA<TypeError>()),
      );
    });
  });

  group('QuestModel.toJson', () {
    test('emits every column with ISO-8601 timestamps', () {
      final json = QuestModel.fromJson(questRow()).toJson();

      expect(json[QuestColumns.id], 'quest-1');
      expect(json[QuestColumns.xpReward], 150);
      expect(json[QuestColumns.durationHours], 4);
      expect(json[QuestColumns.isActive], true);
      expect(json[QuestColumns.createdAt], '2026-05-03T12:00:00.000Z');
      expect(json[QuestColumns.updatedAt], '2026-05-04T09:30:00.000Z');
      expect(json.keys, hasLength(11));
    });

    test('a null updated_at serialises as null, not as a string', () {
      final row = questRow()..remove(QuestColumns.updatedAt);
      expect(QuestModel.fromJson(row).toJson()[QuestColumns.updatedAt], isNull);
    });

    test('round-trips through fromJson without drift', () {
      final original = QuestModel.fromJson(questRow());
      final restored = QuestModel.fromJson(original.toJson());

      expect(restored.id, original.id);
      expect(restored.title, original.title);
      expect(restored.description, original.description);
      expect(restored.category, original.category);
      expect(restored.difficulty, original.difficulty);
      expect(restored.xpReward, original.xpReward);
      expect(restored.durationHours, original.durationHours);
      expect(restored.isActive, original.isActive);
      expect(restored.createdBy, original.createdBy);
      expect(restored.createdAt, original.createdAt);
      expect(restored.updatedAt, original.updatedAt);
    });
  });

  group('QuestModel.copyWith', () {
    test('no-arg copy preserves every field', () {
      final original = QuestModel.fromJson(questRow());
      final copy = original.copyWith();

      expect(copy.id, original.id);
      expect(copy.title, original.title);
      expect(copy.xpReward, original.xpReward);
      expect(copy.durationHours, original.durationHours);
      expect(copy.isActive, original.isActive);
      expect(copy.createdBy, original.createdBy);
      expect(copy.createdAt, original.createdAt);
      expect(copy.updatedAt, original.updatedAt);
    });

    test('overrides the editable fields only', () {
      final original = QuestModel.fromJson(questRow());
      final copy = original.copyWith(
        title: 'Renamed',
        xpReward: 500,
        durationHours: 12,
        isActive: false,
      );

      expect(copy.title, 'Renamed');
      expect(copy.xpReward, 500);
      expect(copy.durationHours, 12);
      expect(copy.isActive, isFalse);
      // id / createdBy / timestamps are intentionally not overridable.
      expect(copy.id, 'quest-1');
      expect(copy.createdAt, original.createdAt);
    });

    test('copyWith re-normalises duration_hours', () {
      // Regression guard. The clamp used to be applied in fromJson only, so
      // copyWith(durationHours: 0) produced a quest that could never come
      // off the wire and that the DB CHECK would have rejected.
      final quest = QuestModel.fromJson(questRow());

      expect(quest.copyWith(durationHours: 0).durationHours, 4);
      expect(quest.copyWith(durationHours: -3).durationHours, 4);
      expect(quest.copyWith(durationHours: 100000).durationHours, 168);
      expect(quest.copyWith(durationHours: 12).durationHours, 12);
      // Omitting it still preserves the existing value.
      expect(quest.copyWith().durationHours, quest.durationHours);
    });
  });

  group('QuestModel value equality', () {
    // Regression guard. Equality used to be identity, so a quest re-fetch
    // that changed nothing still rebuilt every widget watching it.
    test('two quests parsed from the same row are equal', () {
      expect(QuestModel.fromJson(questRow()), QuestModel.fromJson(questRow()));
      expect(
        QuestModel.fromJson(questRow()).hashCode,
        QuestModel.fromJson(questRow()).hashCode,
      );
    });

    test('a no-arg copyWith is equal to its original', () {
      final original = QuestModel.fromJson(questRow());
      expect(original.copyWith(), original);
    });

    test('a differing field breaks equality', () {
      final original = QuestModel.fromJson(questRow());
      expect(original.copyWith(title: 'Renamed'), isNot(original));
    });
  });
}
