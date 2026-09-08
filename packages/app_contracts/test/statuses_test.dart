import 'package:app_contracts/app_contracts.dart';
import 'package:test/test.dart';

import 'contract_invariants.dart';

/// Hand-written enumerations of every status/enum constant. These mirror the
/// database CHECK constraints; changing one here without changing the
/// migration (or vice versa) is exactly the drift these tests exist to stop.
const Map<String, String> questCategories = {
  'fitness': QuestCategory.fitness,
  'creativity': QuestCategory.creativity,
  'social': QuestCategory.social,
  'learning': QuestCategory.learning,
  'adventure': QuestCategory.adventure,
};

const Map<String, String> questDifficulties = {
  'easy': QuestDifficulty.easy,
  'medium': QuestDifficulty.medium,
  'hard': QuestDifficulty.hard,
};

const Map<String, String> userQuestStatuses = {
  'assigned': UserQuestStatus.assigned,
  'submitted': UserQuestStatus.submitted,
  'approved': UserQuestStatus.approved,
  'rejected': UserQuestStatus.rejected,
  'expired': UserQuestStatus.expired,
};

const Map<String, String> submissionStatuses = {
  'pending': SubmissionStatus.pending,
  'approved': SubmissionStatus.approved,
  'rejected': SubmissionStatus.rejected,
};

const Map<String, String> reactionTypes = {
  'upvote': ReactionType.upvote,
  'downvote': ReactionType.downvote,
};

const Map<String, String> notificationTypes = {
  'questAssigned': NotificationType.questAssigned,
  'submissionApproved': NotificationType.submissionApproved,
  'submissionRejected': NotificationType.submissionRejected,
  'reactionReceived': NotificationType.reactionReceived,
  'levelUp': NotificationType.levelUp,
  'announcement': NotificationType.announcement,
  'newFollower': NotificationType.newFollower,
  'newComment': NotificationType.newComment,
  'questExpired': NotificationType.questExpired,
  'followQuestCompleted': NotificationType.followQuestCompleted,
  'reactionMilestone': NotificationType.reactionMilestone,
  'newSubmission': NotificationType.newSubmission,
  'appealSubmitted': NotificationType.appealSubmitted,
  'leaderboardOvertaken': NotificationType.leaderboardOvertaken,
  'top10Entry': NotificationType.top10Entry,
  'questTimerWarning': NotificationType.questTimerWarning,
  'pendingReviewReminder': NotificationType.pendingReviewReminder,
  'commentReply': NotificationType.commentReply,
  'mention': NotificationType.mention,
  'collabJoined': NotificationType.collabJoined,
  'collabPartnerApproved': NotificationType.collabPartnerApproved,
};

const Map<String, String> collabModes = {
  'with_': CollabMode.with_,
  'versus': CollabMode.versus,
};

const Map<String, String> collabGroupStatuses = {
  'open': CollabGroupStatus.open,
  'closed': CollabGroupStatus.closed,
  'expired': CollabGroupStatus.expired,
};

const Map<String, String> adminRoles = {
  'superAdmin': AdminRole.superAdmin,
  'moderator': AdminRole.moderator,
};

const Map<String, String> submissionVisibilities = {
  'visible': SubmissionVisibility.visible,
  'hiddenFromFeed': SubmissionVisibility.hiddenFromFeed,
  'deleted': SubmissionVisibility.deleted,
};

const Map<String, String> mediaTypes = {
  'image': MediaType.image,
  'video': MediaType.video,
  'mixed': MediaType.mixed,
};

/// Every enum-like class in statuses.dart, for the mechanical sweep.
const Map<String, Map<String, String>> allStatusClasses = {
  'QuestCategory': questCategories,
  'QuestDifficulty': questDifficulties,
  'UserQuestStatus': userQuestStatuses,
  'SubmissionStatus': submissionStatuses,
  'ReactionType': reactionTypes,
  'NotificationType': notificationTypes,
  'CollabMode': collabModes,
  'CollabGroupStatus': collabGroupStatuses,
  'AdminRole': adminRoles,
  'SubmissionVisibility': submissionVisibilities,
  'MediaType': mediaTypes,
};

void main() {
  group('every status constant is a valid database literal', () {
    allStatusClasses.forEach((label, values) {
      test('$label values are non-empty, lowercase, snake_case and unique', () {
        expectValidContractValues(label, values);
      });
    });

    test('no status value carries whitespace or a trailing comment artefact',
        () {
      // MediaType.mixed is declared with a trailing `//` comment on the same
      // line; this pins that the comment did not leak into the literal.
      expect(MediaType.mixed, 'mixed');
      for (final values in allStatusClasses.values) {
        for (final value in values.values) {
          expect(value.contains(' '), isFalse, reason: '"$value" has a space');
          expect(value.contains('/'), isFalse, reason: '"$value" has a slash');
        }
      }
    });
  });

  group('exact CHECK-constraint membership', () {
    test('QuestCategory is exactly the 5 seeded categories', () {
      expect(questCategories.values.toSet(), {
        'fitness',
        'creativity',
        'social',
        'learning',
        'adventure',
      });
    });

    test('QuestDifficulty is exactly easy/medium/hard', () {
      expect(questDifficulties.values.toSet(), {'easy', 'medium', 'hard'});
    });

    test('UserQuestStatus is exactly the 5 lifecycle states', () {
      expect(userQuestStatuses.values.toSet(), {
        'assigned',
        'submitted',
        'approved',
        'rejected',
        'expired',
      });
    });

    test('SubmissionStatus is exactly the 3 review states', () {
      expect(submissionStatuses.values.toSet(), {
        'pending',
        'approved',
        'rejected',
      });
    });

    test('ReactionType is exactly upvote/downvote', () {
      expect(reactionTypes.values.toSet(), {'upvote', 'downvote'});
    });

    test('CollabMode is exactly with/versus', () {
      // `with` is a Dart-adjacent word, hence the trailing underscore on the
      // identifier — the wire value must stay bare.
      expect(collabModes.values.toSet(), {'with', 'versus'});
      expect(CollabMode.with_, 'with');
      expect(CollabMode.with_, isNot(contains('_')));
    });

    test('CollabGroupStatus is exactly open/closed/expired', () {
      expect(collabGroupStatuses.values.toSet(), {
        'open',
        'closed',
        'expired',
      });
    });

    test('AdminRole is exactly super_admin/moderator', () {
      expect(adminRoles.values.toSet(), {'super_admin', 'moderator'});
    });

    test('SubmissionVisibility is exactly the 3 moderation states', () {
      expect(submissionVisibilities.values.toSet(), {
        'visible',
        'hidden_from_feed',
        'deleted',
      });
    });

    test('MediaType is exactly image/video/mixed', () {
      expect(mediaTypes.values.toSet(), {'image', 'video', 'mixed'});
    });

    test('NotificationType is exactly the 21 shipped types', () {
      expect(notificationTypes.values.toSet(), {
        'quest_assigned',
        'submission_approved',
        'submission_rejected',
        'reaction_received',
        'level_up',
        'announcement',
        'new_follower',
        'new_comment',
        'quest_expired',
        'follow_quest_completed',
        'reaction_milestone',
        'new_submission',
        'appeal_submitted',
        'leaderboard_overtaken',
        'top_10_entry',
        'quest_timer_warning',
        'pending_review_reminder',
        'comment_reply',
        'mention',
        'collab_joined',
        'collab_partner_approved',
      });
      expect(notificationTypes, hasLength(21));
    });
  });

  group('cross-class agreement', () {
    test('the review verdicts shared with UserQuestStatus do not drift', () {
      // A submission verdict is copied onto the user_quest row, so these two
      // vocabularies have to agree on the shared words.
      expect(UserQuestStatus.approved, SubmissionStatus.approved);
      expect(UserQuestStatus.rejected, SubmissionStatus.rejected);
    });

    test('UserQuestStatus is a strict superset of SubmissionStatus verdicts',
        () {
      expect(
        userQuestStatuses.values.toSet(),
        containsAll({SubmissionStatus.approved, SubmissionStatus.rejected}),
      );
      // ...but "pending" is submission-only: a user_quest uses "submitted".
      expect(
        userQuestStatuses.values,
        isNot(contains(SubmissionStatus.pending)),
      );
      expect(UserQuestStatus.submitted, isNot(SubmissionStatus.pending));
    });

    test('the expired states in the two lifecycles agree', () {
      expect(CollabGroupStatus.expired, UserQuestStatus.expired);
    });

    test('"deleted" visibility never collides with a submission status', () {
      expect(
        submissionStatuses.values,
        isNot(contains(SubmissionVisibility.deleted)),
      );
    });

    test('a notification type is never bare-equal to a status value', () {
      // The two vocabularies live in different columns but are frequently
      // compared in the same switch; an overlap would make a bug very hard
      // to spot. `announcement` and `mention` are the only single-word
      // types, and neither is a status.
      final statusValues = <String>{
        ...questCategories.values,
        ...questDifficulties.values,
        ...userQuestStatuses.values,
        ...submissionStatuses.values,
        ...reactionTypes.values,
        ...collabGroupStatuses.values,
        ...submissionVisibilities.values,
        ...mediaTypes.values,
      };

      for (final type in notificationTypes.values) {
        expect(
          statusValues,
          isNot(contains(type)),
          reason: 'NotificationType "$type" collides with a status value',
        );
      }
    });

    test('every notification type naming a verdict uses the verdict word', () {
      expect(
        NotificationType.submissionApproved,
        'submission_${SubmissionStatus.approved}',
      );
      expect(
        NotificationType.submissionRejected,
        'submission_${SubmissionStatus.rejected}',
      );
      expect(
        NotificationType.questExpired,
        'quest_${UserQuestStatus.expired}',
      );
    });
  });
}
