import 'package:supabase_contracts/supabase_contracts.dart';
import 'package:test/test.dart';

import 'contract_invariants.dart';

const Map<String, String> rpcNames = {
  'assignSpecificQuest': RpcNames.assignSpecificQuest,
  'expireUserQuest': RpcNames.expireUserQuest,
  'getLeaderboard': RpcNames.getLeaderboard,
  'getFeed': RpcNames.getFeed,
  'getFollowingActiveQuests': RpcNames.getFollowingActiveQuests,
  'getQuestOfTheDay': RpcNames.getQuestOfTheDay,
  'getSubmissionDetail': RpcNames.getSubmissionDetail,
  'sendNotification': RpcNames.sendNotification,
  'upsertFcmToken': RpcNames.upsertFcmToken,
  'deleteOwnFcmToken': RpcNames.deleteOwnFcmToken,
  'acceptTerms': RpcNames.acceptTerms,
  'reportContent': RpcNames.reportContent,
  'blockUser': RpcNames.blockUser,
  'unblockUser': RpcNames.unblockUser,
  'createCollabGroup': RpcNames.createCollabGroup,
  'getCollabGroupDetails': RpcNames.getCollabGroupDetails,
  'joinCollabGroup': RpcNames.joinCollabGroup,
  'getCollabGroupStatus': RpcNames.getCollabGroupStatus,
  'abandonQuest': RpcNames.abandonQuest,
  'voteCollab': RpcNames.voteCollab,
  'unvoteCollab': RpcNames.unvoteCollab,
  'injectQuestForUser': RpcNames.injectQuestForUser,
  'getQuestPickerOptions': RpcNames.getQuestPickerOptions,
  'adminSendNotification': RpcNames.adminSendNotification,
  'getFollowingLeaderboard': RpcNames.getFollowingLeaderboard,
  'deleteOwnAccount': RpcNames.deleteOwnAccount,
  'appealSubmission': RpcNames.appealSubmission,
  'getUserSavedPosts': RpcNames.getUserSavedPosts,
  'getMyAccountStatus': RpcNames.getMyAccountStatus,
  'adminApproveSubmission': RpcNames.adminApproveSubmission,
  'adminRejectSubmission': RpcNames.adminRejectSubmission,
  'broadcastAnnouncement': RpcNames.broadcastAnnouncement,
  'isQuestRetake': RpcNames.isQuestRetake,
  'setUserAccountStatus': RpcNames.setUserAccountStatus,
  'adminSetUserXp': RpcNames.adminSetUserXp,
  'adminRemovePost': RpcNames.adminRemovePost,
};

const Map<String, String> leaderboardRpcColumns = {
  'rank': LeaderboardRpcColumns.rank,
  'userId': LeaderboardRpcColumns.userId,
};

const Map<String, String> feedRpcColumns = {
  'submissionId': FeedRpcColumns.submissionId,
  'userId': FeedRpcColumns.userId,
  'questId': FeedRpcColumns.questId,
  'questTitle': FeedRpcColumns.questTitle,
  'questDescription': FeedRpcColumns.questDescription,
  'questCategory': FeedRpcColumns.questCategory,
  'xpReward': FeedRpcColumns.xpReward,
  'reactionCount': FeedRpcColumns.reactionCount,
  'upvoteCount': FeedRpcColumns.upvoteCount,
  'downvoteCount': FeedRpcColumns.downvoteCount,
  'netScore': FeedRpcColumns.netScore,
  'hotScore': FeedRpcColumns.hotScore,
};

const Map<String, String> xpStatsRpcColumns = {
  'totalXp': XpStatsRpcColumns.totalXp,
  'currentLevel': XpStatsRpcColumns.currentLevel,
  'xpToNextLevel': XpStatsRpcColumns.xpToNextLevel,
  'totalQuests': XpStatsRpcColumns.totalQuests,
  'rank': XpStatsRpcColumns.rank,
};

const Map<String, String> collabFeedRpcColumns = {
  'isCollab': CollabFeedRpcColumns.isCollab,
  'collabGroupId': CollabFeedRpcColumns.collabGroupId,
  'collabMode': CollabFeedRpcColumns.collabMode,
  'collabMemberCount': CollabFeedRpcColumns.collabMemberCount,
  'collabMembers': CollabFeedRpcColumns.collabMembers,
};

const Map<String, Map<String, String>> allRpcColumnClasses = {
  'LeaderboardRpcColumns': leaderboardRpcColumns,
  'FeedRpcColumns': feedRpcColumns,
  'XpStatsRpcColumns': xpStatsRpcColumns,
  'CollabFeedRpcColumns': collabFeedRpcColumns,
};

const Map<String, Map<String, String>> allRpcParamClasses = {
  'AppealSubmissionParams': {
    'submissionId': AppealSubmissionParams.submissionId,
    'appealNote': AppealSubmissionParams.appealNote,
  },
  'AdminApproveSubmissionParams': {
    'submissionId': AdminApproveSubmissionParams.submissionId,
  },
  'AdminRejectSubmissionParams': {
    'submissionId': AdminRejectSubmissionParams.submissionId,
    'reviewNote': AdminRejectSubmissionParams.reviewNote,
  },
  'AdminRemovePostParams': {
    'submissionId': AdminRemovePostParams.submissionId,
    'reason': AdminRemovePostParams.reason,
  },
  'AdminSetUserXpParams': {
    'userId': AdminSetUserXpParams.userId,
    'xp': AdminSetUserXpParams.xp,
    'level': AdminSetUserXpParams.level,
    'questsCompleted': AdminSetUserXpParams.questsCompleted,
    'reason': AdminSetUserXpParams.reason,
  },
  'BroadcastAnnouncementParams': {
    'title': BroadcastAnnouncementParams.title,
    'body': BroadcastAnnouncementParams.body,
  },
  'UpsertFcmTokenParams': {'token': UpsertFcmTokenParams.token},
  'AssignSpecificQuestParams': {
    'userId': AssignSpecificQuestParams.userId,
    'questId': AssignSpecificQuestParams.questId,
  },
  'GetQuestPickerOptionsParams': {
    'count': GetQuestPickerOptionsParams.count,
  },
  'GetUserSavedPostsParams': {'userId': GetUserSavedPostsParams.userId},
  'ExpireUserQuestParams': {
    'userQuestId': ExpireUserQuestParams.userQuestId,
  },
};

void main() {
  group('RpcNames', () {
    test('names are non-empty, lowercase, snake_case and unique', () {
      expectValidContractValues('RpcNames', rpcNames);
    });

    test('is exactly the 36 functions Dart calls', () {
      expect(rpcNames.values.toSet(), {
        'assign_specific_quest',
        'expire_user_quest',
        'get_leaderboard',
        'get_feed',
        'get_following_active_quests',
        'get_quest_of_the_day',
        'get_submission_detail',
        'send_notification',
        'upsert_fcm_token',
        'delete_own_fcm_token',
        'accept_terms',
        'report_content',
        'block_user',
        'unblock_user',
        'create_collab_group',
        'get_collab_group_details',
        'join_collab_group',
        'get_collab_group_status',
        'abandon_quest',
        'vote_collab',
        'unvote_collab',
        'inject_quest_for_user',
        'get_quest_picker_options',
        'admin_send_notification',
        'get_following_leaderboard',
        'delete_own_account',
        'appeal_submission',
        'get_user_saved_posts',
        'get_my_account_status',
        'admin_approve_submission',
        'admin_reject_submission',
        'broadcast_announcement',
        'is_quest_retake',
        'set_user_account_status',
        'admin_set_user_xp',
        'admin_remove_post',
      });
      expect(rpcNames, hasLength(36));
    });

    test('every admin-prefixed Dart member names an admin_ function', () {
      rpcNames.forEach((name, value) {
        if (!name.startsWith('admin')) return;
        expect(
          value.startsWith('admin_'),
          isTrue,
          reason: 'RpcNames.$name = "$value" should be admin_-prefixed',
        );
      });
    });

    test('the single-quest expiry is not the bulk sweeper', () {
      // `expire_overdue_quests` is the pg_cron bulk job and must never be
      // callable from a client; only the per-row function is exposed here.
      expect(RpcNames.expireUserQuest, 'expire_user_quest');
      expect(rpcNames.values, isNot(contains('expire_overdue_quests')));
    });

    test('SQL-only functions are deliberately absent', () {
      for (final sqlOnly in [
        'increment_xp',
        'expire_overdue_quests',
        'get_user_xp_stats',
        'assign_random_quest',
        'get_reaction_counts',
      ]) {
        expect(
          rpcNames.values,
          isNot(contains(sqlOnly)),
          reason: '$sqlOnly is SQL-only and must not gain a Dart constant '
              'without a caller',
        );
      }
    });
  });

  group('RPC result columns', () {
    allRpcColumnClasses.forEach((label, columns) {
      test('$label is non-empty, lowercase, snake_case and unique', () {
        expectValidContractValues(label, columns);
      });
    });

    test('FeedRpcColumns covers all 12 aliases of get_feed', () {
      expect(feedRpcColumns.values.toSet(), {
        'submission_id',
        'user_id',
        'quest_id',
        'quest_title',
        'quest_description',
        'quest_category',
        'xp_reward',
        'reaction_count',
        'upvote_count',
        'downvote_count',
        'net_score',
        'hot_score',
      });
    });

    test('CollabFeedRpcColumns covers all 5 collab aliases', () {
      expect(collabFeedRpcColumns.values.toSet(), {
        'is_collab',
        'collab_group_id',
        'collab_mode',
        'collab_member_count',
        'collab_members',
      });
    });

    test('the feed alias for the submission PK is not the bare "id"', () {
      // FeedPostModel reads submission_id; if this ever became 'id' every
      // feed post would silently get an empty id.
      expect(FeedRpcColumns.submissionId, 'submission_id');
      expect(FeedRpcColumns.submissionId, isNot(SubmissionColumns.id));
    });

    test('the RPC aliases that shadow real columns keep the same spelling', () {
      // get_feed re-exposes these under the same names the tables use, so
      // FeedPostModel can index the row with either constant.
      expect(FeedRpcColumns.userId, SubmissionColumns.userId);
      expect(FeedRpcColumns.questId, UserQuestColumns.questId);
      expect(FeedRpcColumns.xpReward, QuestColumns.xpReward);
      // get_leaderboard aliases the profile PK as user_id, so the two must
      // stay different spellings.
      expect(LeaderboardRpcColumns.userId, 'user_id');
      expect(LeaderboardRpcColumns.userId, isNot(ProfileColumns.id));
    });
  });

  group('RPC parameter names', () {
    allRpcParamClasses.forEach((label, params) {
      test('$label is non-empty, lowercase, snake_case and unique', () {
        expectValidContractValues(label, params);
      });
    });

    test('every SECURITY DEFINER parameter carries the p_ prefix', () {
      // Postgres resolves named RPC arguments by exact name; a missing p_
      // becomes a runtime "function ... does not exist" fault.
      allRpcParamClasses.forEach((label, params) {
        params.forEach((name, value) {
          expect(
            value.startsWith('p_'),
            isTrue,
            reason: '$label.$name = "$value" is missing the p_ prefix',
          );
          expect(
            value.length,
            greaterThan(2),
            reason: '$label.$name is just the prefix',
          );
        });
      });
    });

    test('the p_ prefix is stripped to a snake_case column-ish name', () {
      expect(AppealSubmissionParams.submissionId, 'p_submission_id');
      expect(AppealSubmissionParams.appealNote, 'p_appeal_note');
      expect(ExpireUserQuestParams.userQuestId, 'p_user_quest_id');
      expect(AdminSetUserXpParams.questsCompleted, 'p_quests_completed');
    });

    test('the four submission-scoped RPCs agree on the parameter name', () {
      // Built as a list first so the analyzer does not fold the (currently
      // identical) constants into a single set literal element.
      final submissionParams = <String>[
        AppealSubmissionParams.submissionId,
        AdminApproveSubmissionParams.submissionId,
        AdminRejectSubmissionParams.submissionId,
        AdminRemovePostParams.submissionId,
      ];

      expect(submissionParams.toSet(), hasLength(1));
      expect(submissionParams.toSet().single, 'p_submission_id');
    });
  });

  group('EdgeFunctionNames', () {
    test('is exactly the 2 deployed functions', () {
      expect(
        {EdgeFunctionNames.adminManageUser, EdgeFunctionNames.sendPush},
        {'admin_manage_user', 'send-push'},
      );
    });

    test('both are non-empty and lowercase', () {
      for (final name in [
        EdgeFunctionNames.adminManageUser,
        EdgeFunctionNames.sendPush,
      ]) {
        expect(name, isNotEmpty);
        expect(name, name.toLowerCase());
        expect(name.trim(), name);
      }
    });

    test('send-push is kebab-case, not snake_case', () {
      // Documented inconsistency: the deployed function is literally
      // `send-push`, so the constant must NOT be normalised to snake_case.
      expect(EdgeFunctionNames.sendPush, 'send-push');
      expect(snakeCase.hasMatch(EdgeFunctionNames.sendPush), isFalse);
      expect(snakeCase.hasMatch(EdgeFunctionNames.adminManageUser), isTrue);
    });
  });
}
