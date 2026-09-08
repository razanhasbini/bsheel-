import 'package:app_models/app_models.dart';
import 'package:app_contracts/app_contracts.dart';
import 'package:test/test.dart';

Map<String, dynamic> reactionRow({Map<String, dynamic> overrides = const {}}) =>
    {
      ReactionColumns.id: 'reaction-1',
      ReactionColumns.submissionId: 'sub-1',
      ReactionColumns.userId: 'user-1',
      ReactionColumns.type: ReactionType.upvote,
      ReactionColumns.createdAt: '2026-05-03T12:00:00Z',
      ...overrides,
    };

void main() {
  group('ReactionModel.fromJson', () {
    test('parses the row', () {
      final reaction = ReactionModel.fromJson(reactionRow());

      expect(reaction.id, 'reaction-1');
      expect(reaction.submissionId, 'sub-1');
      expect(reaction.userId, 'user-1');
      expect(reaction.type, 'upvote');
      expect(reaction.createdAt, DateTime.utc(2026, 5, 3, 12));
    });

    test('a downvote keeps its type verbatim', () {
      expect(
        ReactionModel.fromJson(reactionRow(overrides: {
          ReactionColumns.type: ReactionType.downvote,
        })).type,
        'downvote',
      );
    });

    test('missing string columns coerce to empty strings', () {
      final reaction = ReactionModel.fromJson({
        ReactionColumns.createdAt: '2026-05-03T12:00:00Z',
      });

      expect(reaction.id, isEmpty);
      expect(reaction.submissionId, isEmpty);
      expect(reaction.userId, isEmpty);
      expect(reaction.type, isEmpty);
    });

    test('an unknown type is NOT rejected or normalised', () {
      // ACTUAL behaviour: no validation against ReactionType, so a bad write
      // reaches the vote arithmetic as a third, silently-ignored kind.
      expect(
        ReactionModel.fromJson(reactionRow(overrides: {
          ReactionColumns.type: 'sideways',
        })).type,
        'sideways',
      );
    });

    test('a missing or malformed created_at degrades to the epoch', () {
      // Regression guard. created_at used to be parsed with a hard cast, so
      // one bad row threw a TypeError instead of degrading that row.
      final epoch = DateTime.utc(1970);

      expect(ReactionModel.fromJson({}).createdAt, epoch);
      expect(
        ReactionModel.fromJson(reactionRow(overrides: {
          ReactionColumns.createdAt: 'moments ago',
        })).createdAt,
        epoch,
      );
    });

    test('a DateTime instance passes through', () {
      final at = DateTime.utc(2026, 5, 3, 12);
      expect(
        ReactionModel.fromJson(reactionRow(overrides: {
          ReactionColumns.createdAt: at,
        })).createdAt,
        at,
      );
    });
  });

  group('ReactionModel.toJson', () {
    test('emits all 5 columns and round-trips', () {
      final original = ReactionModel.fromJson(reactionRow());
      final json = original.toJson();

      expect(json.keys.toSet(), {
        ReactionColumns.id,
        ReactionColumns.submissionId,
        ReactionColumns.userId,
        ReactionColumns.type,
        ReactionColumns.createdAt,
      });
      expect(json[ReactionColumns.createdAt], '2026-05-03T12:00:00.000Z');

      final restored = ReactionModel.fromJson(json);
      expect(restored.id, original.id);
      expect(restored.submissionId, original.submissionId);
      expect(restored.userId, original.userId);
      expect(restored.type, original.type);
      expect(restored.createdAt, original.createdAt);
      // Value equality (it used to be identity, so this was never true).
      expect(restored, original);
      expect(restored.hashCode, original.hashCode);
    });

    test('a differing type breaks equality', () {
      expect(
        ReactionModel.fromJson(reactionRow(overrides: {
          ReactionColumns.type: ReactionType.downvote,
        })),
        isNot(ReactionModel.fromJson(reactionRow())),
      );
    });
  });
}
