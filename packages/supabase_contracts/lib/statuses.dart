/// Single source of truth for all status and enum string values used in the database.
library;

/// Quest category CHECK constraint values.
abstract final class QuestCategory {
  static const String fitness = 'fitness';
  static const String creativity = 'creativity';
  static const String social = 'social';
  static const String learning = 'learning';
  static const String adventure = 'adventure';
}

/// Quest difficulty CHECK constraint values.
abstract final class QuestDifficulty {
  static const String easy = 'easy';
  static const String medium = 'medium';
  static const String hard = 'hard';
}

abstract final class UserQuestStatus {
  static const String assigned = 'assigned';
  static const String submitted = 'submitted';
  static const String approved = 'approved';
  static const String rejected = 'rejected';
  static const String expired = 'expired';
}

abstract final class SubmissionStatus {
  static const String pending = 'pending';
  static const String approved = 'approved';
  static const String rejected = 'rejected';
}

abstract final class ReactionType {
  static const String upvote = 'upvote';
  static const String downvote = 'downvote';
}

abstract final class NotificationType {
  static const String questAssigned = 'quest_assigned';
  static const String submissionApproved = 'submission_approved';
  static const String submissionRejected = 'submission_rejected';
  static const String reactionReceived = 'reaction_received';
  static const String levelUp = 'level_up';
  static const String announcement = 'announcement';
  static const String newFollower = 'new_follower';
  static const String newComment = 'new_comment';

  // ── New types added in migration 0036–0039 ──────────────────
  /// Quest timer expired without submission.
  static const String questExpired = 'quest_expired';
  /// A follower completed a quest and had it approved.
  static const String followQuestCompleted = 'follow_quest_completed';
  /// A submission reached a reaction milestone (10 / 25 / 50).
  static const String reactionMilestone = 'reaction_milestone';
  /// A new submission arrived for admin review.
  static const String newSubmission = 'new_submission';
  /// A user resubmitted after a rejection (appeal).
  static const String appealSubmitted = 'appeal_submitted';
  /// Another user overtook this user on the leaderboard.
  static const String leaderboardOvertaken = 'leaderboard_overtaken';
  /// This user entered the top 10 on the leaderboard.
  static const String top10Entry = 'top_10_entry';
  /// 30-minute warning before a quest expires.
  static const String questTimerWarning = 'quest_timer_warning';
  /// Admin reminder: pending submissions older than 24 hours.
  static const String pendingReviewReminder = 'pending_review_reminder';
  /// Another user commented on the same submission (reply-in-thread).
  static const String commentReply = 'comment_reply';
  /// Another user mentioned this user in a comment.
  static const String mention = 'mention';

  // ── Collab types added in migration 0072–0074 ──────────────────
  /// A user accepted your collab invite.
  static const String collabJoined = 'collab_joined';
  /// Your collab partner's submission was approved.
  static const String collabPartnerApproved = 'collab_partner_approved';
}

/// Collab group modes.
abstract final class CollabMode {
  static const String with_ = 'with';
  static const String versus = 'versus';
}

/// Collab group status values.
abstract final class CollabGroupStatus {
  static const String open = 'open';
  static const String closed = 'closed';
  static const String expired = 'expired';
}

abstract final class AdminRole {
  static const String superAdmin = 'super_admin';
  static const String moderator = 'moderator';
}

/// Submission visibility states.
abstract final class SubmissionVisibility {
  static const String visible = 'visible';
  static const String hiddenFromFeed = 'hidden_from_feed';
  static const String deleted = 'deleted';
}

abstract final class MediaType {
  static const String image = 'image';
  static const String video = 'video';
  static const String mixed = 'mixed'; // multiple files with both images and videos
}
