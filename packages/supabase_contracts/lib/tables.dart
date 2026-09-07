/// Single source of truth for all Supabase table names.
abstract final class Tables {
  static const String profiles = 'profiles';
  static const String quests = 'quests';
  static const String userQuests = 'user_quests';
  static const String submissions = 'submissions';
  static const String reactions = 'reactions';
  static const String notifications = 'notifications';
  static const String admins = 'admins';
  static const String comments = 'comments';
  static const String follows = 'follows';
  static const String reports = 'reports';
  static const String blockedUsers = 'blocked_users';
  static const String collabGroups = 'collab_groups';
  static const String collabGroupMembers = 'collab_group_members';
  static const String collabVotes = 'collab_votes';
  static const String adminQuestInjections = 'admin_quest_injections';
  static const String appConfig = 'app_config';
  static const String savedPosts = 'saved_posts';
  static const String savedQuests = 'saved_quests';
  static const String questOfTheDay = 'quest_of_the_day';
}
