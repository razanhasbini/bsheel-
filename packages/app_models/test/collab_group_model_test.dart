import 'package:app_models/app_models.dart';
import 'package:app_contracts/app_contracts.dart';
import 'package:test/test.dart';

Map<String, dynamic> previewMemberRow({
  Map<String, dynamic> overrides = const {},
}) =>
    {
      'user_id': 'user-2',
      'username': 'grace',
      'display_name': 'Grace H.',
      'avatar_url': 'https://cdn.test/grace.jpg',
      ...overrides,
    };

Map<String, dynamic> previewRow({Map<String, dynamic> overrides = const {}}) =>
    {
      'group_id': 'group-1',
      'code': 'ABC123',
      'mode': CollabMode.with_,
      'status': CollabGroupStatus.open,
      'member_count': 2,
      'max_members': 4,
      'expires_at': '2026-05-03T16:00:00Z',
      'members': <dynamic>[previewMemberRow()],
      'quest_title': 'Photo walk',
      'quest_description': 'Shoot 3 frames.',
      'quest_category': QuestCategory.creativity,
      'quest_difficulty': QuestDifficulty.medium,
      'quest_xp_reward': 150,
      'quest_duration_hours': 6,
      'creator_username': 'ada',
      'creator_display_name': 'Ada L.',
      'creator_avatar_url': 'https://cdn.test/ada.jpg',
      ...overrides,
    };

Map<String, dynamic> memberStatusRow({
  Map<String, dynamic> overrides = const {},
}) =>
    {
      'user_id': 'user-2',
      'username': 'grace',
      'display_name': 'Grace H.',
      'avatar_url': 'https://cdn.test/grace.jpg',
      'quest_status': UserQuestStatus.submitted,
      'submission_status': SubmissionStatus.pending,
      'submission_time_seconds': 421,
      'vote_count': 3,
      ...overrides,
    };

Map<String, dynamic> statusRow({Map<String, dynamic> overrides = const {}}) => {
      'is_collab': true,
      'group_id': 'group-1',
      'mode': CollabMode.versus,
      'status': CollabGroupStatus.open,
      'code': 'ABC123',
      'max_members': 4,
      'expires_at': '2026-05-03T16:00:00Z',
      'members': <dynamic>[memberStatusRow()],
      ...overrides,
    };

void main() {
  group('CollabGroupPreviewModel.fromJson', () {
    test('parses the full get_collab_group_details payload', () {
      final preview = CollabGroupPreviewModel.fromJson(previewRow());

      expect(preview.groupId, 'group-1');
      expect(preview.code, 'ABC123');
      expect(preview.mode, 'with');
      expect(preview.status, 'open');
      expect(preview.memberCount, 2);
      expect(preview.maxMembers, 4);
      expect(preview.expiresAt, DateTime.utc(2026, 5, 3, 16));
      expect(preview.members, hasLength(1));
      expect(preview.members.single.userId, 'user-2');
      expect(preview.questTitle, 'Photo walk');
      expect(preview.questDescription, 'Shoot 3 frames.');
      expect(preview.questCategory, 'creativity');
      expect(preview.questDifficulty, 'medium');
      expect(preview.questXpReward, 150);
      expect(preview.questDurationHours, 6);
      expect(preview.creatorUsername, 'ada');
      expect(preview.creatorDisplayName, 'Ada L.');
      expect(preview.creatorAvatarUrl, 'https://cdn.test/ada.jpg');
    });

    test('group_id / code / mode / status are required', () {
      // Identity/enum columns keep their non-nullable casts: without them
      // there is no group to preview. (expires_at deliberately no longer
      // belongs in this list — see the next test.)
      for (final key in ['group_id', 'code', 'mode', 'status']) {
        final row = previewRow()..remove(key);
        expect(
          () => CollabGroupPreviewModel.fromJson(row),
          throwsA(anyOf(isA<TypeError>(), isA<ArgumentError>())),
          reason: 'a missing $key should throw',
        );
      }
    });

    test('a missing or malformed expires_at degrades to the epoch', () {
      // Regression guard. This required timestamp used to throw, taking the
      // whole join screen down with it; it now degrades, and an
      // already-expired epoch is the safe way for a countdown to read.
      final epoch = DateTime.utc(1970);
      final row = previewRow()..remove('expires_at');

      expect(CollabGroupPreviewModel.fromJson(row).expiresAt, epoch);
      expect(
        CollabGroupPreviewModel.fromJson(
          previewRow(overrides: {'expires_at': 'never'}),
        ).expiresAt,
        epoch,
      );
    });

    test('the join-screen defaults kick in for a sparse payload', () {
      final row = previewRow()
        ..remove('member_count')
        ..remove('max_members')
        ..remove('members')
        ..remove('quest_title')
        ..remove('quest_description')
        ..remove('quest_category')
        ..remove('quest_difficulty')
        ..remove('quest_xp_reward')
        ..remove('quest_duration_hours')
        ..remove('creator_username')
        ..remove('creator_display_name')
        ..remove('creator_avatar_url');
      final preview = CollabGroupPreviewModel.fromJson(row);

      expect(preview.memberCount, 0);
      // 5 is the party-size cap the join screen assumes.
      expect(preview.maxMembers, 5);
      expect(preview.members, isEmpty);
      expect(preview.questTitle, isEmpty);
      expect(preview.questDescription, isEmpty);
      expect(preview.questCategory, isEmpty);
      expect(preview.questDifficulty, isEmpty);
      // These two differ from every other default in the package.
      expect(preview.questXpReward, 10);
      expect(preview.questDurationHours, 4);
      expect(preview.creatorUsername, isEmpty);
      expect(preview.creatorDisplayName, isEmpty);
      expect(preview.creatorAvatarUrl, isNull);
    });

    test('num-typed counts are accepted and truncated', () {
      final preview = CollabGroupPreviewModel.fromJson(previewRow(overrides: {
        'member_count': 2.0,
        'max_members': 4.9,
        'quest_xp_reward': 150.0,
      }));

      expect(preview.memberCount, 2);
      expect(preview.maxMembers, 4);
      expect(preview.questXpReward, 150);
    });

    test('a stringly-typed count now parses, exactly like QuestModel', () {
      // Regression guard. `as num?` was a hard cast, so the '2' PostgREST
      // sends for a bigint count threw here while QuestModel parsed it.
      // Every int in the package goes through one shared coercion now.
      final preview = CollabGroupPreviewModel.fromJson(previewRow(overrides: {
        'member_count': '2',
        'max_members': '4',
        'quest_xp_reward': '150.9',
      }));

      expect(preview.memberCount, 2);
      expect(preview.maxMembers, 4);
      expect(preview.questXpReward, 150);
    });

    test('a garbage count falls back to that column default', () {
      final preview = CollabGroupPreviewModel.fromJson(previewRow(overrides: {
        'member_count': 'two',
        'max_members': 'lots',
        'quest_xp_reward': 'plenty',
      }));

      expect(preview.memberCount, 0);
      expect(preview.maxMembers, 5);
      expect(preview.questXpReward, 10);
    });

    test('the duration is clamped to the same 1..168 range as QuestModel', () {
      // Regression guard. This model applied no bounds at all, so a bad
      // duration_hours reached the join screen unchanged. Mirrors the DB
      // CHECK `duration_hours between 1 and 168`.
      for (final entry
          in <Object?, int>{0: 4, -3: 4, 100000: 168, 168: 168}.entries) {
        expect(
          CollabGroupPreviewModel.fromJson(
            previewRow(overrides: {'quest_duration_hours': entry.key}),
          ).questDurationHours,
          entry.value,
          reason: 'quest_duration_hours=${entry.key}',
        );
      }
    });

    test('an empty members array yields an empty list', () {
      expect(
        CollabGroupPreviewModel.fromJson(
          previewRow(overrides: {'members': <dynamic>[]}),
        ).members,
        isEmpty,
      );
    });

    test('a null members value falls back to an empty list', () {
      expect(
        CollabGroupPreviewModel.fromJson(
          previewRow(overrides: {'members': null}),
        ).members,
        isEmpty,
      );
    });

    test('multiple members keep their order', () {
      final preview = CollabGroupPreviewModel.fromJson(previewRow(overrides: {
        'members': <dynamic>[
          previewMemberRow(),
          previewMemberRow(overrides: {'user_id': 'user-3'}),
        ],
      }));

      expect(preview.members.map((m) => m.userId), ['user-2', 'user-3']);
    });
  });

  group('CollabGroupPreviewMember.fromJson', () {
    test('parses a member', () {
      final member = CollabGroupPreviewMember.fromJson(previewMemberRow());

      expect(member.userId, 'user-2');
      expect(member.username, 'grace');
      expect(member.displayName, 'Grace H.');
      expect(member.avatarUrl, 'https://cdn.test/grace.jpg');
    });

    test('user_id is required, the rest degrade to empty / null', () {
      expect(
        () => CollabGroupPreviewMember.fromJson(const <String, dynamic>{}),
        throwsA(isA<TypeError>()),
      );

      final member = CollabGroupPreviewMember.fromJson(
        const <String, dynamic>{'user_id': 'user-9'},
      );
      expect(member.username, isEmpty);
      expect(member.displayName, isEmpty);
      expect(member.avatarUrl, isNull);
    });
  });

  group('CollabGroupStatusModel.fromJson', () {
    test('parses the full get_collab_group_status payload', () {
      final status = CollabGroupStatusModel.fromJson(statusRow());

      expect(status.isCollab, isTrue);
      expect(status.groupId, 'group-1');
      expect(status.mode, 'versus');
      expect(status.status, 'open');
      expect(status.code, 'ABC123');
      expect(status.maxMembers, 4);
      expect(status.expiresAt, DateTime.utc(2026, 5, 3, 16));
      expect(status.members, hasLength(1));
    });

    test('the solo-quest response ({is_collab: false}) parses cleanly', () {
      // This is the payload for a user who is NOT in a collab, so every
      // optional field must survive being absent.
      final status = CollabGroupStatusModel.fromJson(
        const <String, dynamic>{'is_collab': false},
      );

      expect(status.isCollab, isFalse);
      expect(status.groupId, isNull);
      expect(status.mode, isNull);
      expect(status.status, isNull);
      expect(status.code, isNull);
      expect(status.maxMembers, isNull);
      expect(status.expiresAt, isNull);
      expect(status.members, isEmpty);
    });

    test('an entirely empty payload fails closed to is_collab = false', () {
      final status = CollabGroupStatusModel.fromJson(
        const <String, dynamic>{},
      );

      expect(status.isCollab, isFalse);
      expect(status.members, isEmpty);
    });

    test('a null expires_at stays null', () {
      expect(
        CollabGroupStatusModel.fromJson(
          statusRow(overrides: {'expires_at': null}),
        ).expiresAt,
        isNull,
      );
    });

    test('an unparseable expires_at degrades to null', () {
      // Regression guard. This used DateTime.parse, so a malformed
      // timestamp threw a FormatException that lost the entire collab
      // status instead of just the countdown. Optional timestamps become
      // null everywhere in the package now.
      expect(
        CollabGroupStatusModel.fromJson(
          statusRow(overrides: {'expires_at': 'never'}),
        ).expiresAt,
        isNull,
      );
    });

    test('a stringly-typed max_members parses, garbage stays null', () {
      expect(
        CollabGroupStatusModel.fromJson(
          statusRow(overrides: {'max_members': '4'}),
        ).maxMembers,
        4,
      );
      expect(
        CollabGroupStatusModel.fromJson(
          statusRow(overrides: {'max_members': 'four'}),
        ).maxMembers,
        isNull,
      );
    });

    test('a null members value falls back to an empty list', () {
      expect(
        CollabGroupStatusModel.fromJson(
          statusRow(overrides: {'members': null}),
        ).members,
        isEmpty,
      );
    });
  });

  group('CollabMemberStatus.fromJson', () {
    test('parses a member status row', () {
      final member = CollabMemberStatus.fromJson(memberStatusRow());

      expect(member.userId, 'user-2');
      expect(member.username, 'grace');
      expect(member.displayName, 'Grace H.');
      expect(member.avatarUrl, 'https://cdn.test/grace.jpg');
      expect(member.questStatus, 'submitted');
      expect(member.submissionStatus, 'pending');
      expect(member.submissionTimeSeconds, 421);
      expect(member.voteCount, 3);
    });

    test('a member who has not posted yet has null statuses', () {
      final member = CollabMemberStatus.fromJson(
        const <String, dynamic>{'user_id': 'user-9'},
      );

      expect(member.username, isEmpty);
      expect(member.displayName, isEmpty);
      expect(member.avatarUrl, isNull);
      expect(member.questStatus, isNull);
      expect(member.submissionStatus, isNull);
      // Null, not 0 — "no submission" must be distinguishable from
      // "submitted instantly" for the versus timing display.
      expect(member.submissionTimeSeconds, isNull);
      expect(member.voteCount, 0);
    });

    test('user_id is required', () {
      expect(
        () => CollabMemberStatus.fromJson(const <String, dynamic>{}),
        throwsA(isA<TypeError>()),
      );
    });

    test('num-typed vote counts and times truncate', () {
      final member = CollabMemberStatus.fromJson(memberStatusRow(overrides: {
        'vote_count': 3.9,
        'submission_time_seconds': 421.5,
      }));

      expect(member.voteCount, 3);
      expect(member.submissionTimeSeconds, 421);
    });

    test('a null vote_count reads as 0', () {
      expect(
        CollabMemberStatus.fromJson(
          memberStatusRow(overrides: {'vote_count': null}),
        ).voteCount,
        0,
      );
    });
  });

  group('collab value equality', () {
    // Regression guard. Equality used to be identity on all four classes,
    // so polling the collab status rebuilt the whole screen every time.
    // The member lists are bounded by the party size, so element-wise
    // comparison stays cheap.
    test('two previews parsed from the same payload are equal', () {
      final a = CollabGroupPreviewModel.fromJson(previewRow());
      final b = CollabGroupPreviewModel.fromJson(previewRow());

      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('a differing member breaks preview equality', () {
      expect(
        CollabGroupPreviewModel.fromJson(previewRow(overrides: {
          'members': <dynamic>[
            previewMemberRow(overrides: {'user_id': 'x'})
          ],
        })),
        isNot(CollabGroupPreviewModel.fromJson(previewRow())),
      );
    });

    test('two statuses parsed from the same payload are equal', () {
      final a = CollabGroupStatusModel.fromJson(statusRow());
      final b = CollabGroupStatusModel.fromJson(statusRow());

      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('a differing vote count breaks status equality', () {
      expect(
        CollabGroupStatusModel.fromJson(statusRow(overrides: {
          'members': <dynamic>[
            memberStatusRow(overrides: {'vote_count': 9})
          ],
        })),
        isNot(CollabGroupStatusModel.fromJson(statusRow())),
      );
    });
  });
}
