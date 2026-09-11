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

  // ── Multi-stage journeys ────────────────────────────────────
  /// A checkpoint opened for this user. References the chain RUN, so a tap
  /// lands on the journey rather than on a bare quest.
  static const String journeyStageUnlocked = 'journey_stage_unlocked';

  /// Somebody cleared their checkpoint on a relay and the baton moved on.
  static const String journeyTeammateAdvanced = 'journey_teammate_advanced';

  /// Every checkpoint on a journey is verified.
  static const String journeyCompleted = 'journey_completed';

  /// 30-minute warning before a quest expires.
  static const String questTimerWarning = 'quest_timer_warning';

  /// Admin reminder: pending submissions older than 24 hours.
  static const String pendingReviewReminder = 'pending_review_reminder';

  /// The user's streak expires at the end of today (#46). Emitted by the
  /// hourly streak sweep, at most once per user per UTC day.
  static const String streakAtRisk = 'streak_at_risk';

  /// Another user commented on the same submission (reply-in-thread).
  static const String commentReply = 'comment_reply';

  /// AI proof verification (#47) could not decide on a submission, so the
  /// committee must. Sent to admins only, and cleared from the "unclear"
  /// queue as soon as a moderator approves or rejects it.
  static const String proofUnclear = 'proof_unclear';

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

/// `reports.status` CHECK constraint values (migration
/// `0001_initial_domain_schema.sql`).
///
/// [pending] is the column default — the state a report is in the moment a
/// user files it, and the one the queue index and the `pendingReports`
/// stat count. It is deliberately **not** in [reviewable]: the review
/// endpoint `PATCH /admin/reports/:id` validates its body against those
/// three values only, so there is no API transition back to the untriaged
/// queue. Sending `pending` is a 400, not a reopen.
abstract final class ReportStatus {
  static const String pending = 'pending';
  static const String reviewed = 'reviewed';
  static const String dismissed = 'dismissed';
  static const String actioned = 'actioned';

  /// The only statuses `PATCH /admin/reports/:id` accepts, in the order
  /// the backend DTO lists them.
  static const List<String> reviewable = [reviewed, dismissed, actioned];

  /// Every legal column value, including the [pending] default.
  static const List<String> all = [pending, reviewed, dismissed, actioned];

  /// `GET /admin/reports?status=` also takes this pseudo-status, meaning
  /// "do not filter". It is not a value the column can hold.
  static const String anyStatus = 'all';
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
  static const String mixed =
      'mixed'; // multiple files with both images and videos
}

/// `map_places.category` CHECK constraint values (migration 0022).
///
/// [hidden] is not a visibility flag — it is a category whose places stay
/// server-side until the requesting user has current CAMARA geofence
/// evidence, which is why the admin console marks those rows separately
/// from an unpublished draft.
abstract final class MapPlaceCategory {
  static const String landmark = 'landmark';
  static const String culture = 'culture';
  static const String pilgrimage = 'pilgrimage';
  static const String heritage = 'heritage';
  static const String hidden = 'hidden';

  /// Every legal value, in the order the admin filter row draws them.
  static const List<String> all = [
    landmark,
    culture,
    pilgrimage,
    heritage,
    hidden,
  ];
}
