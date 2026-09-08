import 'package:supabase_contracts/supabase_contracts.dart';
import 'package:test/test.dart';

import 'contract_invariants.dart';

const Map<String, String> tables = {
  'profiles': Tables.profiles,
  'quests': Tables.quests,
  'userQuests': Tables.userQuests,
  'submissions': Tables.submissions,
  'reactions': Tables.reactions,
  'notifications': Tables.notifications,
  'admins': Tables.admins,
  'comments': Tables.comments,
  'follows': Tables.follows,
  'reports': Tables.reports,
  'blockedUsers': Tables.blockedUsers,
  'collabGroups': Tables.collabGroups,
  'collabGroupMembers': Tables.collabGroupMembers,
  'collabVotes': Tables.collabVotes,
  'adminQuestInjections': Tables.adminQuestInjections,
  'appConfig': Tables.appConfig,
  'savedPosts': Tables.savedPosts,
  'savedQuests': Tables.savedQuests,
  'questOfTheDay': Tables.questOfTheDay,
};

const Map<String, String> profileColumns = {
  'id': ProfileColumns.id,
  'username': ProfileColumns.username,
  'displayName': ProfileColumns.displayName,
  'avatarUrl': ProfileColumns.avatarUrl,
  'bio': ProfileColumns.bio,
  'xp': ProfileColumns.xp,
  'level': ProfileColumns.level,
  'questsCompleted': ProfileColumns.questsCompleted,
  'createdAt': ProfileColumns.createdAt,
  'fcmToken': ProfileColumns.fcmToken,
  'updatedAt': ProfileColumns.updatedAt,
  'profileCompleted': ProfileColumns.profileCompleted,
  'ageVerified': ProfileColumns.ageVerified,
  'analyticsConsentAt': ProfileColumns.analyticsConsentAt,
};

const Map<String, String> questColumns = {
  'id': QuestColumns.id,
  'title': QuestColumns.title,
  'description': QuestColumns.description,
  'category': QuestColumns.category,
  'difficulty': QuestColumns.difficulty,
  'xpReward': QuestColumns.xpReward,
  'durationHours': QuestColumns.durationHours,
  'isActive': QuestColumns.isActive,
  'createdBy': QuestColumns.createdBy,
  'createdAt': QuestColumns.createdAt,
  'updatedAt': QuestColumns.updatedAt,
};

const Map<String, String> userQuestColumns = {
  'id': UserQuestColumns.id,
  'userId': UserQuestColumns.userId,
  'questId': UserQuestColumns.questId,
  'status': UserQuestColumns.status,
  'assignedAt': UserQuestColumns.assignedAt,
  'completedAt': UserQuestColumns.completedAt,
  'expiresAt': UserQuestColumns.expiresAt,
};

const Map<String, String> submissionColumns = {
  'id': SubmissionColumns.id,
  'userQuestId': SubmissionColumns.userQuestId,
  'userId': SubmissionColumns.userId,
  'mediaUrl': SubmissionColumns.mediaUrl,
  'mediaType': SubmissionColumns.mediaType,
  'caption': SubmissionColumns.caption,
  'status': SubmissionColumns.status,
  'reviewedBy': SubmissionColumns.reviewedBy,
  'reviewNote': SubmissionColumns.reviewNote,
  'submittedAt': SubmissionColumns.submittedAt,
  'reviewedAt': SubmissionColumns.reviewedAt,
  'appealNote': SubmissionColumns.appealNote,
  'appealed': SubmissionColumns.appealed,
  'showInFeed': SubmissionColumns.showInFeed,
  'visibility': SubmissionColumns.visibility,
  'deletedAt': SubmissionColumns.deletedAt,
};

const Map<String, String> reactionColumns = {
  'id': ReactionColumns.id,
  'submissionId': ReactionColumns.submissionId,
  'userId': ReactionColumns.userId,
  'type': ReactionColumns.type,
  'createdAt': ReactionColumns.createdAt,
};

const Map<String, String> notificationColumns = {
  'id': NotificationColumns.id,
  'userId': NotificationColumns.userId,
  'title': NotificationColumns.title,
  'body': NotificationColumns.body,
  'type': NotificationColumns.type,
  'referenceId': NotificationColumns.referenceId,
  'isRead': NotificationColumns.isRead,
  'createdAt': NotificationColumns.createdAt,
  'actorId': NotificationColumns.actorId,
};

const Map<String, String> adminColumns = {
  'id': AdminColumns.id,
  'userId': AdminColumns.userId,
  'role': AdminColumns.role,
  'createdAt': AdminColumns.createdAt,
};

const Map<String, String> blockedUserColumns = {
  'id': BlockedUserColumns.id,
  'blockerId': BlockedUserColumns.blockerId,
  'blockedId': BlockedUserColumns.blockedId,
  'createdAt': BlockedUserColumns.createdAt,
};

const Map<String, String> commentColumns = {
  'id': CommentColumns.id,
  'submissionId': CommentColumns.submissionId,
  'userId': CommentColumns.userId,
  'body': CommentColumns.body,
  'createdAt': CommentColumns.createdAt,
  'parentId': CommentColumns.parentId,
};

const Map<String, String> collabGroupColumns = {
  'id': CollabGroupColumns.id,
  'questId': CollabGroupColumns.questId,
  'creatorId': CollabGroupColumns.creatorId,
  'code': CollabGroupColumns.code,
  'mode': CollabGroupColumns.mode,
  'status': CollabGroupColumns.status,
  'maxMembers': CollabGroupColumns.maxMembers,
  'expiresAt': CollabGroupColumns.expiresAt,
  'createdAt': CollabGroupColumns.createdAt,
};

const Map<String, String> collabGroupMemberColumns = {
  'id': CollabGroupMemberColumns.id,
  'groupId': CollabGroupMemberColumns.groupId,
  'userId': CollabGroupMemberColumns.userId,
  'userQuestId': CollabGroupMemberColumns.userQuestId,
  'joinedAt': CollabGroupMemberColumns.joinedAt,
  'submissionTimeSeconds': CollabGroupMemberColumns.submissionTimeSeconds,
};

const Map<String, String> collabVoteColumns = {
  'id': CollabVoteColumns.id,
  'groupId': CollabVoteColumns.groupId,
  'voterId': CollabVoteColumns.voterId,
  'submissionId': CollabVoteColumns.submissionId,
  'createdAt': CollabVoteColumns.createdAt,
};

const Map<String, String> savedPostColumns = {
  'id': SavedPostColumns.id,
  'userId': SavedPostColumns.userId,
  'submissionId': SavedPostColumns.submissionId,
  'createdAt': SavedPostColumns.createdAt,
};

const Map<String, String> savedQuestColumns = {
  'id': SavedQuestColumns.id,
  'userId': SavedQuestColumns.userId,
  'questId': SavedQuestColumns.questId,
  'createdAt': SavedQuestColumns.createdAt,
};

const Map<String, String> followColumns = {
  'id': FollowColumns.id,
  'followerId': FollowColumns.followerId,
  'followingId': FollowColumns.followingId,
  'createdAt': FollowColumns.createdAt,
};

const Map<String, Map<String, String>> allColumnClasses = {
  'ProfileColumns': profileColumns,
  'QuestColumns': questColumns,
  'UserQuestColumns': userQuestColumns,
  'SubmissionColumns': submissionColumns,
  'ReactionColumns': reactionColumns,
  'NotificationColumns': notificationColumns,
  'AdminColumns': adminColumns,
  'BlockedUserColumns': blockedUserColumns,
  'CommentColumns': commentColumns,
  'CollabGroupColumns': collabGroupColumns,
  'CollabGroupMemberColumns': collabGroupMemberColumns,
  'CollabVoteColumns': collabVoteColumns,
  'SavedPostColumns': savedPostColumns,
  'SavedQuestColumns': savedQuestColumns,
  'FollowColumns': followColumns,
};

void main() {
  group('Tables', () {
    test('names are non-empty, lowercase, snake_case and unique', () {
      expectValidContractValues('Tables', tables);
    });

    test('is exactly the 19 tables the Dart clients touch', () {
      expect(tables.values.toSet(), {
        'profiles',
        'quests',
        'user_quests',
        'submissions',
        'reactions',
        'notifications',
        'admins',
        'comments',
        'follows',
        'reports',
        'blocked_users',
        'collab_groups',
        'collab_group_members',
        'collab_votes',
        'admin_quest_injections',
        'app_config',
        'saved_posts',
        'saved_quests',
        'quest_of_the_day',
      });
      expect(tables, hasLength(19));
    });

    test('the join keys the models read are the plain table names', () {
      // SubmissionModel / UserQuestModel / CommentModel index the embedded
      // rows by these exact strings.
      expect(Tables.userQuests, 'user_quests');
      expect(Tables.quests, 'quests');
      expect(Tables.profiles, 'profiles');
    });
  });

  group('column names are valid identifiers', () {
    allColumnClasses.forEach((label, columns) {
      test('$label is non-empty, lowercase, snake_case and unique', () {
        expectValidContractValues(label, columns);
      });
    });

    test('every primary key is plain "id"', () {
      allColumnClasses.forEach((label, columns) {
        expect(columns['id'], 'id', reason: '$label.id must be "id"');
      });
    });

    test('every Dart *Id member maps to an "_id"-suffixed column', () {
      allColumnClasses.forEach((label, columns) {
        columns.forEach((name, value) {
          if (name == 'id' || !name.endsWith('Id')) return;
          expect(
            value.endsWith('_id'),
            isTrue,
            reason: '$label.$name = "$value" should end in _id',
          );
        });
      });
    });

    test('every Dart *At member maps to an "_at"-suffixed column', () {
      allColumnClasses.forEach((label, columns) {
        columns.forEach((name, value) {
          if (!name.endsWith('At')) return;
          expect(
            value.endsWith('_at'),
            isTrue,
            reason: '$label.$name = "$value" should end in _at',
          );
        });
      });
    });

    test('no column name collides with a table name', () {
      // A select string like `profiles(...)` is ambiguous if a column is
      // also called `profiles`.
      final tableNames = tables.values.toSet();
      allColumnClasses.forEach((label, columns) {
        columns.forEach((name, value) {
          expect(
            tableNames,
            isNot(contains(value)),
            reason: '$label.$name = "$value" shadows a table name',
          );
        });
      });
    });
  });

  group('exact column sets for the tables Dart writes to', () {
    test('ProfileColumns covers all 14 columns incl. the 0142 consent pair',
        () {
      expect(profileColumns.values.toSet(), {
        'id',
        'username',
        'display_name',
        'avatar_url',
        'bio',
        'xp',
        'level',
        'quests_completed',
        'created_at',
        'fcm_token',
        'updated_at',
        'profile_completed',
        'age_verified',
        'analytics_consent_at',
      });
      // Migration 0142 — the analytics gate reads this exact column.
      expect(ProfileColumns.ageVerified, 'age_verified');
      expect(ProfileColumns.analyticsConsentAt, 'analytics_consent_at');
    });

    test('QuestColumns covers all 11 columns', () {
      expect(questColumns.values.toSet(), {
        'id',
        'title',
        'description',
        'category',
        'difficulty',
        'xp_reward',
        'duration_hours',
        'is_active',
        'created_by',
        'created_at',
        'updated_at',
      });
    });

    test('UserQuestColumns covers all 7 columns', () {
      expect(userQuestColumns.values.toSet(), {
        'id',
        'user_id',
        'quest_id',
        'status',
        'assigned_at',
        'completed_at',
        'expires_at',
      });
    });

    test('SubmissionColumns covers all 16 columns incl. moderation state', () {
      expect(submissionColumns.values.toSet(), {
        'id',
        'user_quest_id',
        'user_id',
        'media_url',
        'media_type',
        'caption',
        'status',
        'reviewed_by',
        'review_note',
        'submitted_at',
        'reviewed_at',
        'appeal_note',
        'appealed',
        'show_in_feed',
        'visibility',
        'deleted_at',
      });
    });

    test('NotificationColumns covers all 9 columns', () {
      expect(notificationColumns.values.toSet(), {
        'id',
        'user_id',
        'title',
        'body',
        'type',
        'reference_id',
        'is_read',
        'created_at',
        'actor_id',
      });
    });

    test('the two block/follow join tables use distinct directional pairs', () {
      expect(FollowColumns.followerId, 'follower_id');
      expect(FollowColumns.followingId, 'following_id');
      expect(BlockedUserColumns.blockerId, 'blocker_id');
      expect(BlockedUserColumns.blockedId, 'blocked_id');
      // A swapped pair here would invert the direction of every block/follow
      // query, so pin that the four are all different.
      expect(
        {
          FollowColumns.followerId,
          FollowColumns.followingId,
          BlockedUserColumns.blockerId,
          BlockedUserColumns.blockedId,
        },
        hasLength(4),
      );
    });
  });
}
