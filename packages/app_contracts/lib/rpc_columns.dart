/// Column names returned by RPC functions that don't map directly to table columns.
/// These are aliases defined in the SQL function return types.

/// Columns returned by get_leaderboard RPC.
abstract final class LeaderboardRpcColumns {
  static const String rank = 'rank';
  static const String userId = 'user_id';
}

/// Columns returned by get_feed RPC.
abstract final class FeedRpcColumns {
  static const String submissionId = 'submission_id';
  static const String userId = 'user_id';
  static const String questId = 'quest_id';
  static const String questTitle = 'quest_title';
  static const String questDescription = 'quest_description';
  static const String questCategory = 'quest_category';
  static const String xpReward = 'xp_reward';
  static const String reactionCount = 'reaction_count';
  static const String upvoteCount = 'upvote_count';
  static const String downvoteCount = 'downvote_count';
  static const String netScore = 'net_score';
  static const String hotScore = 'hot_score';
}

/// Collab group fields returned by the updated get_feed RPC.
abstract final class CollabFeedRpcColumns {
  static const String isCollab = 'is_collab';
  static const String collabGroupId = 'collab_group_id';
  static const String collabMode = 'collab_mode';
  static const String collabMemberCount = 'collab_member_count';
  static const String collabMembers = 'collab_members';
}
