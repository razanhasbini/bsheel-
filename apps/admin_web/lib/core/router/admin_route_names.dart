abstract final class AdminRouteNames {
  static const String login = 'adminLogin';
  static const String confirmEmail = 'confirmEmail';
  static const String dashboard = 'dashboard';
  static const String pendingSubmissions = 'pendingSubmissions';
  static const String unclearQueue = 'unclearQueue';
  static const String submissionReview = 'submissionReview';
  static const String submissionHistory = 'submissionHistory';
  static const String feedManagement = 'feedManagement';
  static const String questManagement = 'questManagement';
  static const String questOfTheDay = 'questOfTheDay';
  static const String questCampaigns = 'questCampaigns';
  static const String questAuthoring = 'questAuthoring';
  static const String mapPlaces = 'mapPlaces';
  static const String users = 'users';
  static const String announcements = 'announcements';
  static const String xpManagement = 'xpManagement';
  static const String autoNotifications = 'autoNotifications';
  static const String appeals = 'appeals';
  static const String reports = 'reports';
  static const String injection = 'injection';
  static const String settings = 'settings';
  static const String webSignups = 'webSignups';
  static const String webQuestSuggestions = 'webQuestSuggestions';
  static const String deletionRequests = 'deletionRequests';
}

abstract final class AdminRoutePaths {
  static const String login = '/login';
  static const String confirmEmail = '/confirm-email';
  static const String privacy = '/privacy';
  static const String deleteAccount = '/delete-account';
  static const String dashboard = '/';
  static const String pendingSubmissions = '/moderation';
  static const String unclearQueue = '/moderation/unclear';
  static const String submissionReview = '/moderation/review/:id';
  static const String submissionHistory = '/moderation/history';
  static const String feedManagement = '/feed';
  static const String questManagement = '/quests';
  static const String questOfTheDay = '/qotd';
  static const String questCampaigns = '/campaigns';
  static const String questAuthoring = '/authoring';
  static const String mapPlaces = '/destinations';
  static const String users = '/users';
  static const String announcements = '/announcements';
  static const String xpManagement = '/xp';
  static const String autoNotifications = '/auto-notifications';
  static const String appeals = '/appeals';
  static const String reports = '/reports';
  static const String injection = '/injection';
  static const String settings = '/settings';
  static const String webSignups = '/web-signups';
  static const String webQuestSuggestions = '/web-quest-suggestions';
  static const String deletionRequests = '/deletion-requests';
}
