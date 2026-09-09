/// Single source of truth for all Supabase column names, grouped by table.
abstract final class ProfileColumns {
  static const String id = 'id';
  static const String username = 'username';
  static const String displayName = 'display_name';
  static const String avatarUrl = 'avatar_url';
  static const String bio = 'bio';
  static const String xp = 'xp';
  static const String level = 'level';
  static const String questsCompleted = 'quests_completed';
  static const String createdAt = 'created_at';
  static const String fcmToken = 'fcm_token';
  static const String updatedAt = 'updated_at';
  static const String profileCompleted = 'profile_completed';

  /// Migration 0142: signup checkbox confirming 13+. Default false.
  static const String ageVerified = 'age_verified';

  /// Migration 0142: timestamp the user accepted analytics opt-in.
  /// NULL = no consent yet — Mixpanel must stay disabled until set.
  static const String analyticsConsentAt = 'analytics_consent_at';
}

abstract final class QuestColumns {
  // #51 quest-type columns.
  static const String isHidden = 'is_hidden';
  static const String availableFrom = 'available_from';
  static const String availableUntil = 'available_until';
  static const String sponsorName = 'sponsor_name';

  static const String id = 'id';
  static const String title = 'title';
  static const String description = 'description';
  static const String category = 'category';
  static const String difficulty = 'difficulty';
  static const String xpReward = 'xp_reward';
  static const String durationHours = 'duration_hours';
  static const String isActive = 'is_active';
  static const String createdBy = 'created_by';
  static const String createdAt = 'created_at';
  static const String updatedAt = 'updated_at';
}

abstract final class UserQuestColumns {
  static const String id = 'id';
  static const String userId = 'user_id';
  static const String questId = 'quest_id';
  static const String status = 'status';
  static const String assignedAt = 'assigned_at';
  static const String completedAt = 'completed_at';
  static const String expiresAt = 'expires_at';

  /// Computed by the quest-history query, not a stored column.
  static const String appealAvailable = 'appeal_available';
}

abstract final class SubmissionColumns {
  static const String id = 'id';
  static const String userQuestId = 'user_quest_id';
  static const String userId = 'user_id';
  static const String mediaUrl = 'media_url';
  static const String mediaType = 'media_type';
  static const String caption = 'caption';
  static const String status = 'status';
  static const String reviewedBy = 'reviewed_by';
  static const String reviewNote = 'review_note';
  static const String submittedAt = 'submitted_at';
  static const String reviewedAt = 'reviewed_at';
  static const String appealNote = 'appeal_note';
  static const String appealed = 'appealed';
  static const String showInFeed = 'show_in_feed';
  static const String visibility = 'visibility';
  static const String deletedAt = 'deleted_at';
}

abstract final class ReactionColumns {
  static const String id = 'id';
  static const String submissionId = 'submission_id';
  static const String userId = 'user_id';
  static const String type = 'type';
  static const String createdAt = 'created_at';
}

abstract final class NotificationColumns {
  static const String id = 'id';
  static const String userId = 'user_id';
  static const String title = 'title';
  static const String body = 'body';
  static const String type = 'type';
  static const String referenceId = 'reference_id';
  static const String isRead = 'is_read';
  static const String createdAt = 'created_at';
  static const String actorId = 'actor_id';
}

abstract final class AdminColumns {
  static const String id = 'id';
  static const String userId = 'user_id';
  static const String role = 'role';
  static const String createdAt = 'created_at';
}

abstract final class BlockedUserColumns {
  static const String id = 'id';
  static const String blockerId = 'blocker_id';
  static const String blockedId = 'blocked_id';
  static const String createdAt = 'created_at';
}

abstract final class CommentColumns {
  static const String id = 'id';
  static const String submissionId = 'submission_id';
  static const String userId = 'user_id';
  static const String body = 'body';
  static const String createdAt = 'created_at';
  static const String parentId = 'parent_id';
}

abstract final class CollabGroupColumns {
  static const String id = 'id';
  static const String questId = 'quest_id';
  static const String creatorId = 'creator_id';
  static const String code = 'code';
  static const String mode = 'mode';
  static const String status = 'status';
  static const String maxMembers = 'max_members';
  static const String expiresAt = 'expires_at';
  static const String createdAt = 'created_at';
}

abstract final class CollabGroupMemberColumns {
  static const String id = 'id';
  static const String groupId = 'group_id';
  static const String userId = 'user_id';
  static const String userQuestId = 'user_quest_id';
  static const String joinedAt = 'joined_at';
  static const String submissionTimeSeconds = 'submission_time_seconds';
}

abstract final class CollabVoteColumns {
  static const String id = 'id';
  static const String groupId = 'group_id';
  static const String voterId = 'voter_id';
  static const String submissionId = 'submission_id';
  static const String createdAt = 'created_at';
}

abstract final class SavedPostColumns {
  static const String id = 'id';
  static const String userId = 'user_id';
  static const String submissionId = 'submission_id';
  static const String createdAt = 'created_at';
}

abstract final class SavedQuestColumns {
  static const String id = 'id';
  static const String userId = 'user_id';
  static const String questId = 'quest_id';
  static const String createdAt = 'created_at';
}

abstract final class FollowColumns {
  static const String id = 'id';
  static const String followerId = 'follower_id';
  static const String followingId = 'following_id';
  static const String createdAt = 'created_at';
}
