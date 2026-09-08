import 'package:app_models/app_models.dart';
import 'package:app_contracts/app_contracts.dart';
import 'package:test/test.dart';

Map<String, dynamic> nestedQuest({Map<String, dynamic> overrides = const {}}) =>
    {
      QuestColumns.id: 'quest-1',
      QuestColumns.title: 'Photo walk',
      QuestColumns.description: 'Shoot 3 frames.',
      QuestColumns.category: QuestCategory.creativity,
      QuestColumns.difficulty: QuestDifficulty.easy,
      QuestColumns.xpReward: 150,
      QuestColumns.durationHours: 4,
      QuestColumns.isActive: true,
      QuestColumns.createdAt: '2026-05-01T00:00:00Z',
      ...overrides,
    };

Map<String, dynamic> userQuestRow({
  Map<String, dynamic> overrides = const {},
}) =>
    {
      UserQuestColumns.id: 'uq-1',
      UserQuestColumns.userId: 'user-1',
      UserQuestColumns.questId: 'quest-1',
      UserQuestColumns.status: UserQuestStatus.assigned,
      UserQuestColumns.assignedAt: '2026-05-03T12:00:00Z',
      UserQuestColumns.completedAt: null,
      UserQuestColumns.expiresAt: '2026-05-03T16:00:00Z',
      ...overrides,
    };

void main() {
  group('UserQuestModel.fromJson', () {
    test('parses the flat row', () {
      final uq = UserQuestModel.fromJson(userQuestRow());

      expect(uq.id, 'uq-1');
      expect(uq.userId, 'user-1');
      expect(uq.questId, 'quest-1');
      expect(uq.status, 'assigned');
      expect(uq.assignedAt, DateTime.utc(2026, 5, 3, 12));
      expect(uq.completedAt, isNull);
      expect(uq.expiresAt, DateTime.utc(2026, 5, 3, 16));
      expect(uq.quest, isNull);
    });

    test('missing string columns coerce to empty strings', () {
      final uq = UserQuestModel.fromJson({
        UserQuestColumns.assignedAt: '2026-05-03T12:00:00Z',
      });

      expect(uq.id, isEmpty);
      expect(uq.userId, isEmpty);
      expect(uq.questId, isEmpty);
      expect(uq.status, isEmpty);
      expect(uq.expiresAt, isNull);
    });

    test('an empty status is NOT defaulted to "assigned"', () {
      // ACTUAL behaviour: status falls back to '' rather than to a member of
      // UserQuestStatus, so any `status == UserQuestStatus.assigned` branch
      // silently takes the else-path on a partial select.
      final row = userQuestRow()..remove(UserQuestColumns.status);
      final uq = UserQuestModel.fromJson(row);

      expect(uq.status, isEmpty);
      expect(uq.status, isNot(UserQuestStatus.assigned));
    });

    test('a missing or malformed assigned_at degrades to the epoch', () {
      // Regression guard. assigned_at used to be `DateTime.parse(x as
      // String)`, so one bad row threw a TypeError that took down the whole
      // quest list.
      final epoch = DateTime.utc(1970);

      expect(UserQuestModel.fromJson({}).assignedAt, epoch);
      expect(
        UserQuestModel.fromJson(userQuestRow(overrides: {
          UserQuestColumns.assignedAt: 'this morning',
        })).assignedAt,
        epoch,
      );
    });

    test('an unparseable expires_at degrades to null, not to the epoch', () {
      expect(
        UserQuestModel.fromJson(userQuestRow(overrides: {
          UserQuestColumns.expiresAt: 'soon',
        })).expiresAt,
        isNull,
      );
    });

    test('a completed row carries completed_at', () {
      final uq = UserQuestModel.fromJson(userQuestRow(overrides: {
        UserQuestColumns.status: UserQuestStatus.approved,
        UserQuestColumns.completedAt: '2026-05-03T14:30:00Z',
      }));

      expect(uq.status, 'approved');
      expect(uq.completedAt, DateTime.utc(2026, 5, 3, 14, 30));
    });

    group('nested quest join', () {
      test('an object-shaped quests join builds a QuestModel', () {
        final uq = UserQuestModel.fromJson(userQuestRow(overrides: {
          EmbedKeys.quests: nestedQuest(),
        }));

        expect(uq.quest, isNotNull);
        expect(uq.quest!.id, 'quest-1');
        expect(uq.quest!.title, 'Photo walk');
        expect(uq.quest!.xpReward, 150);
        expect(uq.quest!.difficulty, 'easy');
      });

      test('an array-shaped quests join uses the first element', () {
        final uq = UserQuestModel.fromJson(userQuestRow(overrides: {
          EmbedKeys.quests: <dynamic>[
            nestedQuest(),
            nestedQuest(overrides: {QuestColumns.id: 'quest-2'}),
          ],
        }));

        expect(uq.quest!.id, 'quest-1');
      });

      test('an empty array join yields a null quest', () {
        final uq = UserQuestModel.fromJson(userQuestRow(overrides: {
          EmbedKeys.quests: <dynamic>[],
        }));

        expect(uq.quest, isNull);
      });

      test('a non-map, non-list quests value yields a null quest', () {
        final uq = UserQuestModel.fromJson(userQuestRow(overrides: {
          EmbedKeys.quests: 'quest-1',
        }));

        expect(uq.quest, isNull);
      });

      test('a nested quest missing created_at no longer takes the row down',
          () {
        // Regression guard. The nested parse is not shielded, so a joined
        // quest with a NULL created_at used to throw a TypeError that
        // destroyed the whole user_quest (and the list it was in). The
        // nested quest now degrades its own timestamp instead.
        final bad = nestedQuest()..remove(QuestColumns.createdAt);
        final uq = UserQuestModel.fromJson(
          userQuestRow(overrides: {EmbedKeys.quests: bad}),
        );

        expect(uq.quest, isNotNull);
        expect(uq.quest!.createdAt, DateTime.utc(1970));
        expect(uq.assignedAt, DateTime.utc(2026, 5, 3, 12));
      });
    });
  });

  group('UserQuestModel.toJson', () {
    test('emits the 7 flat columns and omits quests when absent', () {
      final json = UserQuestModel.fromJson(userQuestRow()).toJson();

      expect(json.keys.toSet(), {
        UserQuestColumns.id,
        UserQuestColumns.userId,
        UserQuestColumns.questId,
        UserQuestColumns.status,
        UserQuestColumns.assignedAt,
        UserQuestColumns.completedAt,
        UserQuestColumns.expiresAt,
      });
      expect(json[UserQuestColumns.assignedAt], '2026-05-03T12:00:00.000Z');
      expect(json[UserQuestColumns.completedAt], isNull);
      expect(json[UserQuestColumns.expiresAt], '2026-05-03T16:00:00.000Z');
    });

    test('nests the quest payload when the join was present', () {
      final json = UserQuestModel.fromJson(userQuestRow(overrides: {
        EmbedKeys.quests: nestedQuest(),
      })).toJson();

      expect(json.containsKey(EmbedKeys.quests), isTrue);
      final quest = json[EmbedKeys.quests] as Map<String, dynamic>;
      expect(quest[QuestColumns.id], 'quest-1');
      expect(quest[QuestColumns.xpReward], 150);
    });

    test('round-trips including the nested quest', () {
      final original = UserQuestModel.fromJson(userQuestRow(overrides: {
        EmbedKeys.quests: nestedQuest(),
        UserQuestColumns.completedAt: '2026-05-03T14:30:00Z',
      }));
      final restored = UserQuestModel.fromJson(original.toJson());

      expect(restored.id, original.id);
      expect(restored.userId, original.userId);
      expect(restored.questId, original.questId);
      expect(restored.status, original.status);
      expect(restored.assignedAt, original.assignedAt);
      expect(restored.completedAt, original.completedAt);
      expect(restored.expiresAt, original.expiresAt);
      expect(restored.quest!.id, original.quest!.id);
      expect(restored.quest!.title, original.quest!.title);
      expect(restored.quest!.durationHours, original.quest!.durationHours);
      expect(restored.quest!.createdAt, original.quest!.createdAt);
      // Value equality, nested quest included (it used to be identity, so
      // this was never true).
      expect(restored, original);
      expect(restored.hashCode, original.hashCode);
    });
  });

  group('UserQuestModel value equality', () {
    test('the nested quest participates in equality', () {
      final withQuest = UserQuestModel.fromJson(userQuestRow(overrides: {
        EmbedKeys.quests: nestedQuest(),
      }));

      expect(
        withQuest,
        UserQuestModel.fromJson(userQuestRow(overrides: {
          EmbedKeys.quests: nestedQuest(),
        })),
      );
      expect(
        withQuest,
        isNot(UserQuestModel.fromJson(userQuestRow(overrides: {
          EmbedKeys.quests:
              nestedQuest(overrides: {QuestColumns.title: 'Other'}),
        }))),
      );
      expect(withQuest, isNot(UserQuestModel.fromJson(userQuestRow())));
    });
  });
}
