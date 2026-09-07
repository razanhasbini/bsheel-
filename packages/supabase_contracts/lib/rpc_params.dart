/// Parameter names for SECURITY DEFINER RPCs. Centralised so callers
/// don't sprinkle magic strings like `'p_submission_id'` through the
/// app — renaming a parameter then becomes a compile-time error
/// instead of a runtime "function argument mismatch" fault.
library;

abstract final class AppealSubmissionParams {
  static const String submissionId = 'p_submission_id';
  static const String appealNote = 'p_appeal_note';
}

abstract final class AdminApproveSubmissionParams {
  static const String submissionId = 'p_submission_id';
}

abstract final class AdminRejectSubmissionParams {
  static const String submissionId = 'p_submission_id';
  static const String reviewNote = 'p_review_note';
}

abstract final class AdminRemovePostParams {
  static const String submissionId = 'p_submission_id';
  static const String reason = 'p_reason';
}

abstract final class AdminSetUserXpParams {
  static const String userId = 'p_user_id';
  static const String xp = 'p_xp';
  static const String level = 'p_level';
  static const String questsCompleted = 'p_quests_completed';
  static const String reason = 'p_reason';
}

abstract final class BroadcastAnnouncementParams {
  static const String title = 'p_title';
  static const String body = 'p_body';
}

abstract final class UpsertFcmTokenParams {
  static const String token = 'p_token';
}

abstract final class AssignSpecificQuestParams {
  static const String userId = 'p_user_id';
  static const String questId = 'p_quest_id';
}

abstract final class GetQuestPickerOptionsParams {
  static const String count = 'p_count';
}

abstract final class GetUserSavedPostsParams {
  static const String userId = 'p_user_id';
}

abstract final class ExpireUserQuestParams {
  static const String userQuestId = 'p_user_quest_id';
}
