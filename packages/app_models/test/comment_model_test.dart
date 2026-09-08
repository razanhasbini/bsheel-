import 'package:app_models/app_models.dart';
import 'package:supabase_contracts/supabase_contracts.dart';
import 'package:test/test.dart';

/// The alias PostgREST needs to disambiguate the two profile FKs on
/// `comments`. Hard-coded on purpose: it is the string the select builds.
const String fkAlias = 'profiles!comments_user_id_fkey';

Map<String, dynamic> commentRow({Map<String, dynamic> overrides = const {}}) =>
    {
      CommentColumns.id: 'comment-1',
      CommentColumns.submissionId: 'sub-1',
      CommentColumns.userId: 'user-1',
      CommentColumns.body: 'nice frame',
      CommentColumns.createdAt: '2026-05-03T12:00:00Z',
      CommentColumns.parentId: null,
      ...overrides,
    };

void main() {
  group('CommentModel.fromJson', () {
    test('reads the author from the FK-aliased profiles embed', () {
      final comment = CommentModel.fromJson(commentRow(overrides: {
        fkAlias: <String, dynamic>{
          ProfileColumns.username: 'ada',
          ProfileColumns.displayName: 'Ada L.',
          ProfileColumns.avatarUrl: 'https://cdn.test/ada.jpg',
        },
      }));

      expect(comment.id, 'comment-1');
      expect(comment.submissionId, 'sub-1');
      expect(comment.userId, 'user-1');
      expect(comment.body, 'nice frame');
      expect(comment.createdAt, DateTime.utc(2026, 5, 3, 12));
      expect(comment.username, 'ada');
      expect(comment.displayName, 'Ada L.');
      expect(comment.avatarUrl, 'https://cdn.test/ada.jpg');
      expect(comment.parentId, isNull);
      expect(comment.replies, isEmpty);
    });

    test('falls back to a plain profiles embed', () {
      final comment = CommentModel.fromJson(commentRow(overrides: {
        Tables.profiles: <String, dynamic>{
          ProfileColumns.username: 'ada',
          ProfileColumns.displayName: 'Ada L.',
        },
      }));

      expect(comment.username, 'ada');
      expect(comment.displayName, 'Ada L.');
    });

    test('the aliased embed wins over the plain one', () {
      final comment = CommentModel.fromJson(commentRow(overrides: {
        fkAlias: <String, dynamic>{ProfileColumns.username: 'from-alias'},
        Tables.profiles: <String, dynamic>{
          ProfileColumns.username: 'from-plain',
        },
      }));

      expect(comment.username, 'from-alias');
    });

    test('falls back to flattened author columns when there is no embed', () {
      // Shape returned when the caller selected the author fields inline
      // rather than as an embed.
      final comment = CommentModel.fromJson(commentRow(overrides: {
        'username': 'ada',
        'display_name': 'Ada L.',
        'avatar_url': 'https://cdn.test/ada.jpg',
      }));

      expect(comment.username, 'ada');
      expect(comment.displayName, 'Ada L.');
      expect(comment.avatarUrl, 'https://cdn.test/ada.jpg');
    });

    test('an embed missing a field falls through to the flat column', () {
      final comment = CommentModel.fromJson(commentRow(overrides: {
        fkAlias: <String, dynamic>{ProfileColumns.username: 'ada'},
        'display_name': 'Flat Name',
      }));

      expect(comment.username, 'ada');
      expect(comment.displayName, 'Flat Name');
    });

    test('with neither embed nor flat columns the author reads empty', () {
      final comment = CommentModel.fromJson(commentRow());

      expect(comment.username, isEmpty);
      expect(comment.displayName, isEmpty);
      expect(comment.avatarUrl, isNull);
    });

    test('an array-shaped profiles embed is now tolerated', () {
      // Regression guard. SubmissionModel tolerated the array shape and
      // this model hard-cast to Map, so the same PostgREST response threw
      // here. All four join readers share `coerceEmbed` now.
      final fromPlain = CommentModel.fromJson(commentRow(overrides: {
        Tables.profiles: <dynamic>[
          <String, dynamic>{
            ProfileColumns.username: 'ada',
            ProfileColumns.displayName: 'Ada L.',
          },
        ],
      }));

      expect(fromPlain.username, 'ada');
      expect(fromPlain.displayName, 'Ada L.');

      final fromAlias = CommentModel.fromJson(commentRow(overrides: {
        fkAlias: <dynamic>[
          <String, dynamic>{ProfileColumns.username: 'ada'},
        ],
      }));

      expect(fromAlias.username, 'ada');
    });

    test('an empty array embed falls through to the flat columns', () {
      final comment = CommentModel.fromJson(commentRow(overrides: {
        Tables.profiles: <dynamic>[],
        'username': 'flat-ada',
      }));

      expect(comment.username, 'flat-ada');
    });

    test('missing id / submission_id / body coerce to empty strings', () {
      final comment = CommentModel.fromJson({
        CommentColumns.createdAt: '2026-05-03T12:00:00Z',
      });

      expect(comment.id, isEmpty);
      expect(comment.submissionId, isEmpty);
      expect(comment.userId, isEmpty);
      expect(comment.body, isEmpty);
    });

    test('a missing or malformed created_at degrades to the epoch', () {
      // Regression guard. created_at used to be `DateTime.parse(x as
      // String)`, so one malformed comment threw a TypeError that took down
      // the whole thread.
      final epoch = DateTime.utc(1970);

      expect(CommentModel.fromJson({}).createdAt, epoch);
      expect(
        CommentModel.fromJson(commentRow(overrides: {
          CommentColumns.createdAt: 'a while ago',
        })).createdAt,
        epoch,
      );
    });

    test('a reply carries parent_id', () {
      final comment = CommentModel.fromJson(commentRow(overrides: {
        CommentColumns.parentId: 'comment-0',
      }));

      expect(comment.parentId, 'comment-0');
    });

    test('fromJson never populates replies — the tree is built by callers', () {
      final comment = CommentModel.fromJson(commentRow(overrides: {
        'replies': <dynamic>[
          commentRow(overrides: {'id': 'comment-2'})
        ],
      }));

      expect(comment.replies, isEmpty);
    });
  });

  group('CommentModel.copyWithReplies', () {
    test('attaches replies and preserves every other field', () {
      final parent = CommentModel.fromJson(commentRow(overrides: {
        fkAlias: <String, dynamic>{
          ProfileColumns.username: 'ada',
          ProfileColumns.displayName: 'Ada L.',
          ProfileColumns.avatarUrl: 'https://cdn.test/ada.jpg',
        },
      }));
      final reply = CommentModel.fromJson(commentRow(overrides: {
        CommentColumns.id: 'comment-2',
        CommentColumns.parentId: 'comment-1',
      }));

      final threaded = parent.copyWithReplies([reply]);

      expect(threaded.replies, hasLength(1));
      expect(threaded.replies.single.id, 'comment-2');
      expect(threaded.id, parent.id);
      expect(threaded.submissionId, parent.submissionId);
      expect(threaded.userId, parent.userId);
      expect(threaded.body, parent.body);
      expect(threaded.createdAt, parent.createdAt);
      expect(threaded.username, parent.username);
      expect(threaded.displayName, parent.displayName);
      expect(threaded.avatarUrl, parent.avatarUrl);
      expect(threaded.parentId, parent.parentId);
      // The original is untouched.
      expect(parent.replies, isEmpty);
    });

    test('an empty list clears the replies', () {
      final parent = CommentModel.fromJson(commentRow())
          .copyWithReplies([CommentModel.fromJson(commentRow())]);

      expect(parent.copyWithReplies(const []).replies, isEmpty);
    });
  });

  group('CommentModel equality', () {
    test('is deliberately still identity, unlike the other models', () {
      // Documents the one opt-out from the package-wide value equality:
      // `replies` is a recursive tree, so `==` would walk the whole thread
      // on every Riverpod rebuild check, and its depth is unbounded. The
      // repository rebuilds the thread list wholesale anyway, so identity
      // is the cheaper trade here.
      final a = CommentModel.fromJson(commentRow());
      final b = CommentModel.fromJson(commentRow());

      expect(a, isNot(b));
      expect(a, a);
    });
  });
}
