/// Single source of truth for Supabase RPC function names.
abstract final class RpcNames {
  static const String assignSpecificQuest = 'assign_specific_quest';
  // Expires ONE user_quest by id — not to be confused with the
  // `expire_overdue_quests` pg_cron bulk sweeper in the NOTE below.
  static const String expireUserQuest = 'expire_user_quest';
  static const String getLeaderboard = 'get_leaderboard';
  // NOTE: increment_xp / expire_overdue_quests / get_user_xp_stats /
  // assign_random_quest / get_reaction_counts exist in the DB but are never
  // called from Dart (SQL-only via triggers/other RPCs, or currently unused)
  // — so they have no constants here.
  static const String getFeed = 'get_feed';
  static const String getFollowingActiveQuests = 'get_following_active_quests';
  static const String getQuestOfTheDay = 'get_quest_of_the_day';
  static const String getSubmissionDetail = 'get_submission_detail';
  static const String sendNotification = 'send_notification';
  static const String upsertFcmToken = 'upsert_fcm_token';
  static const String deleteOwnFcmToken = 'delete_own_fcm_token';
  static const String acceptTerms = 'accept_terms';
  static const String reportContent = 'report_content';
  static const String blockUser = 'block_user';
  static const String unblockUser = 'unblock_user';
  static const String createCollabGroup = 'create_collab_group';
  static const String getCollabGroupDetails = 'get_collab_group_details';
  static const String joinCollabGroup = 'join_collab_group';
  static const String getCollabGroupStatus = 'get_collab_group_status';
  static const String abandonQuest = 'abandon_quest';
  static const String voteCollab = 'vote_collab';
  static const String unvoteCollab = 'unvote_collab';
  static const String injectQuestForUser = 'inject_quest_for_user';
  static const String getQuestPickerOptions = 'get_quest_picker_options';
  static const String adminSendNotification = 'admin_send_notification';
  static const String getFollowingLeaderboard = 'get_following_leaderboard';
  static const String deleteOwnAccount = 'delete_own_account';
  static const String appealSubmission = 'appeal_submission';
  static const String getUserSavedPosts = 'get_user_saved_posts';
  // Caller-scoped read of the caller's own account_status. User-facing
  // counterpart of the admin-only setUserAccountStatus below.
  static const String getMyAccountStatus = 'get_my_account_status';

  // ── Admin-only RPCs ─────────────────────────────────────────
  static const String adminApproveSubmission = 'admin_approve_submission';
  static const String adminRejectSubmission = 'admin_reject_submission';
  static const String broadcastAnnouncement = 'broadcast_announcement';
  static const String isQuestRetake = 'is_quest_retake';
  static const String setUserAccountStatus = 'set_user_account_status';
  static const String adminSetUserXp = 'admin_set_user_xp';
  static const String adminRemovePost = 'admin_remove_post';
}
