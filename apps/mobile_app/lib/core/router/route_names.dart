/// Named route constants for the mobile app.
abstract final class RouteNames {
  // Splash
  static const String splash = 'splash';

  // Auth
  static const String login = 'login';
  static const String signup = 'signup';
  static const String forgotPassword = 'forgotPassword';
  static const String resetPassword = 'resetPassword';
  static const String phoneSigninCallback = 'phoneSigninCallback';
  static const String verifyPhone = 'verifyPhone';
  static const String onboardingWalkthrough = 'onboardingWalkthrough';

  // Main tabs
  static const String home = 'home';
  static const String map = 'map';
  static const String feed = 'feed';
  static const String collab = 'collab';
  static const String leaderboard = 'leaderboard';
  static const String profile = 'profile';

  // Quest
  static const String questDetails = 'questDetails';
  static const String journeyDetail = 'journeyDetail';
  static const String questHistory = 'questHistory';

  // Submissions
  static const String submitProof = 'submitProof';
  static const String submissionStatus = 'submissionStatus';

  // Feed
  static const String feedPostDetails = 'feedPostDetails';
  static const String search = 'search';

  // Profile
  static const String editProfile = 'editProfile';
  static const String userProfile = 'userProfile';

  // Notifications
  static const String notifications = 'notifications';

  // Collab
  static const String joinCollab = 'joinCollab';

  // Settings & Legal
  static const String settings = 'settings';

  /// Temporary hackathon demo surface (CAMARA live calls).
  static const String camaraDemo = 'camaraDemo';
  static const String blockedUsers = 'blockedUsers';
  static const String admin = 'admin';
  static const String privacyPolicy = 'privacyPolicy';
  static const String terms = 'terms';
}

abstract final class RoutePaths {
  static const String splash = '/splash';
  static const String login = '/login';
  static const String signup = '/signup';
  static const String forgotPassword = '/forgot-password';
  static const String resetPassword = '/reset-password';
  static const String phoneSigninCallback = '/phone-signin-callback';
  static const String verifyPhone = '/verify-phone';
  static const String onboardingWalkthrough = '/onboarding-walkthrough';
  static const String home = '/';
  static const String map = '/map';
  static const String feed = '/feed';
  static const String collab = '/collab';
  static const String leaderboard = '/leaderboard';
  static const String profile = '/profile';
  static const String questDetails = '/quest/:id';
  static const String journeyDetail = '/journey/:runId';
  static const String questHistory = '/quest-history';
  static const String submitProof = '/submit/:userQuestId';
  static const String submissionStatus = '/submission/:id';
  static const String feedPostDetails = '/post/:id';
  static const String search = '/search';
  static const String editProfile = '/profile/edit';
  static const String userProfile = '/user/:userId';
  static const String notifications = '/notifications';
  static const String joinCollab = '/join/:code';
  static const String settings = '/settings';

  /// Temporary hackathon demo surface (CAMARA live calls).
  static const String camaraDemo = '/camara-demo';
  static const String blockedUsers = '/settings/blocked-users';
  static const String admin = '/admin';
  static const String privacyPolicy = '/privacy';
  static const String terms = '/terms';
}
