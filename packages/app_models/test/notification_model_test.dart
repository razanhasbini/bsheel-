import 'package:app_models/app_models.dart';
import 'package:supabase_contracts/supabase_contracts.dart';
import 'package:test/test.dart';

Map<String, dynamic> notificationRow({
  Map<String, dynamic> overrides = const {},
}) =>
    {
      NotificationColumns.id: 'notif-1',
      NotificationColumns.userId: 'user-1',
      NotificationColumns.title: 'Quest approved',
      NotificationColumns.body: 'Photo walk was approved.',
      NotificationColumns.type: NotificationType.submissionApproved,
      NotificationColumns.referenceId: 'sub-1',
      NotificationColumns.isRead: false,
      NotificationColumns.createdAt: '2026-05-03T12:00:00Z',
      NotificationColumns.actorId: 'user-2',
      ...overrides,
    };

void main() {
  group('NotificationModel.fromJson', () {
    test('parses the flat row', () {
      final n = NotificationModel.fromJson(notificationRow());

      expect(n.id, 'notif-1');
      expect(n.userId, 'user-1');
      expect(n.title, 'Quest approved');
      expect(n.body, 'Photo walk was approved.');
      expect(n.type, 'submission_approved');
      expect(n.referenceId, 'sub-1');
      expect(n.isRead, isFalse);
      expect(n.createdAt, DateTime.utc(2026, 5, 3, 12));
      expect(n.actorId, 'user-2');
      expect(n.actorAvatarUrl, isNull);
      expect(n.actorUsername, isNull);
    });

    test('missing text columns coerce to empty strings', () {
      final n = NotificationModel.fromJson({
        NotificationColumns.createdAt: '2026-05-03T12:00:00Z',
      });

      expect(n.id, isEmpty);
      expect(n.userId, isEmpty);
      expect(n.title, isEmpty);
      expect(n.body, isEmpty);
      expect(n.type, isEmpty);
      expect(n.referenceId, isNull);
      expect(n.isRead, isFalse);
      expect(n.actorId, isNull);
    });

    test('a missing or malformed created_at degrades to the epoch', () {
      // Regression guard. created_at used to be parsed with a hard cast, so
      // one bad row threw a TypeError that took down the whole
      // notification list instead of degrading that row's timestamp.
      final epoch = DateTime.utc(1970);

      expect(NotificationModel.fromJson({}).createdAt, epoch);
      expect(
        NotificationModel.fromJson(notificationRow(overrides: {
          NotificationColumns.createdAt: 'recently',
        })).createdAt,
        epoch,
      );
    });

    test('is_read fails closed on null / missing', () {
      expect(
        NotificationModel.fromJson(notificationRow(overrides: {
          NotificationColumns.isRead: null,
        })).isRead,
        isFalse,
      );
      final row = notificationRow()..remove(NotificationColumns.isRead);
      expect(NotificationModel.fromJson(row).isRead, isFalse);
    });

    test('a stringly-typed is_read coerces instead of throwing', () {
      // Regression guard. `as bool?` was a hard cast, so a JSONB round-trip
      // that stringified the flag threw on the whole row.
      expect(
        NotificationModel.fromJson(notificationRow(overrides: {
          NotificationColumns.isRead: 'true',
        })).isRead,
        isTrue,
      );
      expect(
        NotificationModel.fromJson(notificationRow(overrides: {
          NotificationColumns.isRead: 'false',
        })).isRead,
        isFalse,
      );
    });

    group('actor profile join', () {
      test('reads the aliased actor_profile join', () {
        final n = NotificationModel.fromJson(notificationRow(overrides: {
          'actor_profile': <String, dynamic>{
            'username': 'grace',
            'avatar_url': 'https://cdn.test/grace.jpg',
          },
        }));

        expect(n.actorUsername, 'grace');
        expect(n.actorAvatarUrl, 'https://cdn.test/grace.jpg');
      });

      test('falls back to a plain profiles join', () {
        final n = NotificationModel.fromJson(notificationRow(overrides: {
          Tables.profiles: <String, dynamic>{
            'username': 'grace',
            'avatar_url': 'https://cdn.test/grace.jpg',
          },
        }));

        expect(n.actorUsername, 'grace');
        expect(n.actorAvatarUrl, 'https://cdn.test/grace.jpg');
      });

      test('actor_profile wins over profiles when both are present', () {
        final n = NotificationModel.fromJson(notificationRow(overrides: {
          'actor_profile': <String, dynamic>{'username': 'from-alias'},
          Tables.profiles: <String, dynamic>{'username': 'from-plain'},
        }));

        expect(n.actorUsername, 'from-alias');
      });

      test('an array-shaped join is now tolerated', () {
        // Regression guard. This model cast the join straight to
        // Map<String, dynamic>?, so a PostgREST response that returned the
        // embed as an array blew up the parse where SubmissionModel coped.
        // All four join readers share `coerceEmbed` now.
        final fromPlain =
            NotificationModel.fromJson(notificationRow(overrides: {
          Tables.profiles: <dynamic>[
            <String, dynamic>{
              'username': 'grace',
              'avatar_url': 'https://cdn.test/grace.jpg',
            },
          ],
        }));

        expect(fromPlain.actorUsername, 'grace');
        expect(fromPlain.actorAvatarUrl, 'https://cdn.test/grace.jpg');

        final fromAlias =
            NotificationModel.fromJson(notificationRow(overrides: {
          'actor_profile': <dynamic>[
            <String, dynamic>{'username': 'grace'},
          ],
        }));

        expect(fromAlias.actorUsername, 'grace');
      });

      test('an empty array join leaves the actor fields null', () {
        final n = NotificationModel.fromJson(notificationRow(overrides: {
          Tables.profiles: <dynamic>[],
        }));

        expect(n.actorUsername, isNull);
        expect(n.actorAvatarUrl, isNull);
      });

      test('a join with no username/avatar leaves both null', () {
        final n = NotificationModel.fromJson(notificationRow(overrides: {
          'actor_profile': <String, dynamic>{'id': 'user-2'},
        }));

        expect(n.actorUsername, isNull);
        expect(n.actorAvatarUrl, isNull);
      });
    });
  });

  group('NotificationModel.toJson', () {
    test('emits all 9 own columns, actor_id included', () {
      // Regression guard. actor_id was read but never written, so a
      // notification serialised through toJson came back with no actor and
      // rendered without an avatar. The joined username/avatar stay out —
      // they live on `profiles`, not on this row.
      final json = NotificationModel.fromJson(notificationRow(overrides: {
        'actor_profile': <String, dynamic>{'username': 'grace'},
      })).toJson();

      expect(json.keys.toSet(), {
        NotificationColumns.id,
        NotificationColumns.userId,
        NotificationColumns.title,
        NotificationColumns.body,
        NotificationColumns.type,
        NotificationColumns.referenceId,
        NotificationColumns.isRead,
        NotificationColumns.createdAt,
        NotificationColumns.actorId,
      });
      expect(json[NotificationColumns.actorId], 'user-2');
      expect(json.containsKey('username'), isFalse);
      expect(json.containsKey('avatar_url'), isFalse);
      expect(json[NotificationColumns.createdAt], '2026-05-03T12:00:00.000Z');
    });

    test('round-trips the own columns, actor_id included', () {
      final original = NotificationModel.fromJson(notificationRow());
      final restored = NotificationModel.fromJson(original.toJson());

      expect(restored, original);
      expect(restored.actorId, 'user-2');
    });

    test('a null actor_id serialises as null', () {
      final row = notificationRow()..remove(NotificationColumns.actorId);
      final json = NotificationModel.fromJson(row).toJson();

      expect(json.containsKey(NotificationColumns.actorId), isTrue);
      expect(json[NotificationColumns.actorId], isNull);
    });
  });

  group('NotificationModel value equality', () {
    // Regression guard. Equality used to be identity, so marking one
    // notification read rebuilt the whole list.
    test('two notifications parsed from the same row are equal', () {
      expect(
        NotificationModel.fromJson(notificationRow()),
        NotificationModel.fromJson(notificationRow()),
      );
      expect(
        NotificationModel.fromJson(notificationRow()).hashCode,
        NotificationModel.fromJson(notificationRow()).hashCode,
      );
    });

    test('copyWith(isRead: true) is not equal to the unread original', () {
      final original = NotificationModel.fromJson(notificationRow());

      expect(original.copyWith(), original);
      expect(original.copyWith(isRead: true), isNot(original));
    });
  });

  group('NotificationModel.copyWith', () {
    test('flips isRead and keeps the joined actor fields', () {
      final original = NotificationModel.fromJson(notificationRow(overrides: {
        'actor_profile': <String, dynamic>{
          'username': 'grace',
          'avatar_url': 'https://cdn.test/grace.jpg',
        },
      }));
      final read = original.copyWith(isRead: true);

      expect(read.isRead, isTrue);
      expect(read.id, original.id);
      expect(read.type, original.type);
      expect(read.referenceId, original.referenceId);
      expect(read.createdAt, original.createdAt);
      expect(read.actorId, original.actorId);
      expect(read.actorUsername, 'grace');
      expect(read.actorAvatarUrl, 'https://cdn.test/grace.jpg');
    });

    test('a no-arg copy keeps isRead', () {
      final original = NotificationModel.fromJson(notificationRow(overrides: {
        NotificationColumns.isRead: true,
      }));

      expect(original.copyWith().isRead, isTrue);
    });
  });
}
