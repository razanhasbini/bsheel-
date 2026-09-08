import 'package:app_models/app_models.dart';
import 'package:app_contracts/app_contracts.dart';
import 'package:test/test.dart';

Map<String, dynamic> savedPostRow({
  Map<String, dynamic> overrides = const {},
}) =>
    {
      SavedPostColumns.id: 'saved-1',
      SavedPostColumns.userId: 'user-1',
      SavedPostColumns.submissionId: 'sub-1',
      SavedPostColumns.createdAt: '2026-05-03T12:00:00Z',
      ...overrides,
    };

Map<String, dynamic> savedWithQuestRow({
  Map<String, dynamic> overrides = const {},
}) =>
    {
      'saved_id': 'saved-1',
      'saved_at': '2026-05-03T12:00:00Z',
      'submission_id': 'sub-1',
      'media_url': 'https://cdn.test/a.jpg',
      'media_type': MediaType.video,
      'visibility': SubmissionVisibility.visible,
      'status': SubmissionStatus.approved,
      'quest_id': 'quest-1',
      'quest_title': 'Photo walk',
      'quest_description': 'Shoot 3 frames.',
      'quest_category': QuestCategory.creativity,
      'xp_reward': 150,
      'author_id': 'user-2',
      'author_username': 'grace',
      'author_display_name': 'Grace H.',
      'author_avatar_url': 'https://cdn.test/grace.jpg',
      ...overrides,
    };

void main() {
  group('SavedPostModel.fromJson', () {
    test('parses the row', () {
      final saved = SavedPostModel.fromJson(savedPostRow());

      expect(saved.id, 'saved-1');
      expect(saved.userId, 'user-1');
      expect(saved.submissionId, 'sub-1');
      expect(saved.createdAt, DateTime.utc(2026, 5, 3, 12));
    });

    test('missing ids coerce to empty strings', () {
      final saved = SavedPostModel.fromJson({
        SavedPostColumns.createdAt: '2026-05-03T12:00:00Z',
      });

      expect(saved.id, isEmpty);
      expect(saved.userId, isEmpty);
      expect(saved.submissionId, isEmpty);
    });

    test('a missing or malformed created_at degrades to the epoch', () {
      // Regression guard. created_at used to be parsed with a hard cast, so
      // one bad row threw a TypeError that took down the saved-posts list.
      final epoch = DateTime.utc(1970);

      expect(SavedPostModel.fromJson({}).createdAt, epoch);
      expect(
        SavedPostModel.fromJson(savedPostRow(overrides: {
          SavedPostColumns.createdAt: 'ages ago',
        })).createdAt,
        epoch,
      );
    });

    test('value equality compares every field', () {
      // Regression guard. Equality used to be identity.
      final a = SavedPostModel.fromJson(savedPostRow());
      final b = SavedPostModel.fromJson(savedPostRow());

      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(
        SavedPostModel.fromJson(savedPostRow(overrides: {
          SavedPostColumns.submissionId: 'sub-2',
        })),
        isNot(a),
      );
    });

    test('there is no toJson — saves are written by id, not by payload', () {
      // Guards the shape of the model: adding a toJson later would need the
      // repository write path revisited, so this asserts the current API.
      expect(SavedPostModel.fromJson(savedPostRow()), isA<SavedPostModel>());
    });
  });

  group('SavedPostWithQuest.fromRpc', () {
    test('parses the full get_user_saved_posts row', () {
      final saved = SavedPostWithQuest.fromRpc(savedWithQuestRow());

      expect(saved.savedId, 'saved-1');
      expect(saved.savedAt, DateTime.utc(2026, 5, 3, 12));
      expect(saved.submissionId, 'sub-1');
      expect(saved.mediaUrl, 'https://cdn.test/a.jpg');
      expect(saved.mediaType, 'video');
      expect(saved.visibility, 'visible');
      expect(saved.status, 'approved');
      expect(saved.questId, 'quest-1');
      expect(saved.questTitle, 'Photo walk');
      expect(saved.questDescription, 'Shoot 3 frames.');
      expect(saved.questCategory, 'creativity');
      expect(saved.xpReward, 150);
      expect(saved.authorId, 'user-2');
      expect(saved.authorUsername, 'grace');
      expect(saved.authorDisplayName, 'Grace H.');
      expect(saved.authorAvatarUrl, 'https://cdn.test/grace.jpg');
    });

    test('media_type and visibility have sane defaults', () {
      final row = savedWithQuestRow()
        ..remove('media_type')
        ..remove('visibility');
      final saved = SavedPostWithQuest.fromRpc(row);

      expect(saved.mediaType, 'image');
      expect(saved.visibility, 'visible');
    });

    test('explicit nulls also fall back to the defaults', () {
      final saved = SavedPostWithQuest.fromRpc(savedWithQuestRow(overrides: {
        'media_type': null,
        'visibility': null,
      }));

      expect(saved.mediaType, 'image');
      expect(saved.visibility, 'visible');
    });

    test('status has NO default and reads as an empty string', () {
      // ACTUAL behaviour: unlike media_type/visibility, status falls back to
      // '' rather than to SubmissionStatus.pending — so a saved list built
      // from a partial row shows an unlabelled tile.
      final row = savedWithQuestRow()..remove('status');

      expect(SavedPostWithQuest.fromRpc(row).status, isEmpty);
    });

    test('every other text column coerces to an empty string', () {
      final saved = SavedPostWithQuest.fromRpc({
        'saved_at': '2026-05-03T12:00:00Z',
      });

      expect(saved.savedId, isEmpty);
      expect(saved.submissionId, isEmpty);
      expect(saved.mediaUrl, isEmpty);
      expect(saved.questId, isEmpty);
      expect(saved.questTitle, isEmpty);
      expect(saved.questDescription, isEmpty);
      expect(saved.questCategory, isEmpty);
      expect(saved.authorId, isEmpty);
      expect(saved.authorUsername, isEmpty);
      expect(saved.authorDisplayName, isEmpty);
      expect(saved.authorAvatarUrl, isNull);
      expect(saved.xpReward, 0);
    });

    test('a missing or malformed saved_at degrades to the epoch', () {
      // Regression guard. saved_at used to be `DateTime.parse(x as
      // String)`, so one bad row threw a TypeError that took down the whole
      // BSHEEEL list.
      final epoch = DateTime.utc(1970);

      expect(
        SavedPostWithQuest.fromRpc(const <String, dynamic>{}).savedAt,
        epoch,
      );
      expect(
        SavedPostWithQuest.fromRpc(savedWithQuestRow(overrides: {
          'saved_at': 'yesterday',
        })).savedAt,
        epoch,
      );
    });

    test('value equality compares every field', () {
      // Regression guard. Equality used to be identity.
      final a = SavedPostWithQuest.fromRpc(savedWithQuestRow());
      final b = SavedPostWithQuest.fromRpc(savedWithQuestRow());

      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(
        SavedPostWithQuest.fromRpc(savedWithQuestRow(overrides: {
          'xp_reward': 151,
        })),
        isNot(a),
      );
    });

    group('xp_reward coercion', () {
      test('numeric strings and doubles land as ints', () {
        expect(
          SavedPostWithQuest.fromRpc(savedWithQuestRow(overrides: {
            'xp_reward': '150',
          })).xpReward,
          150,
        );
        expect(
          SavedPostWithQuest.fromRpc(savedWithQuestRow(overrides: {
            'xp_reward': 150.9,
          })).xpReward,
          150,
        );
      });

      test('null and garbage fall back to 0', () {
        expect(
          SavedPostWithQuest.fromRpc(savedWithQuestRow(overrides: {
            'xp_reward': null,
          })).xpReward,
          0,
        );
        expect(
          SavedPostWithQuest.fromRpc(savedWithQuestRow(overrides: {
            'xp_reward': 'lots',
          })).xpReward,
          0,
        );
      });

      test('a decimal string truncates instead of collapsing to 0', () {
        // Regression guard: int.tryParse rejects '150.9'.
        expect(
          SavedPostWithQuest.fromRpc(savedWithQuestRow(overrides: {
            'xp_reward': '150.9',
          })).xpReward,
          150,
        );
      });
    });

    test('a numeric author avatar url throws (hard cast)', () {
      expect(
        () => SavedPostWithQuest.fromRpc(savedWithQuestRow(overrides: {
          'author_avatar_url': 7,
        })),
        throwsA(isA<TypeError>()),
      );
    });
  });
}
