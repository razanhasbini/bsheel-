import 'route_names.dart';

/// Global auth redirect logic.
///
/// [location] is the router's matched location. [isOnboardingComplete] is
/// nullable — pass `null` while the pref hasn't loaded yet so we don't
/// bounce the user to onboarding on a false negative.
String? authRedirect({
  required String location,
  required bool isLoggedIn,
  bool? isOnboardingComplete,
}) {
  final loc = location;
  // Splash is exempt from any redirect during its own playback — it owns
  // the initial frame and navigates to /home itself once its animation
  // finishes. (Skipping splash on warm rebuilds is handled by
  // `_splashShownThisProcess` in app_router.dart's initialLocation.)
  if (loc == RoutePaths.splash) return null;

  final isResetPassword = loc == RoutePaths.resetPassword;
  final isAuthRoute = loc == RoutePaths.login ||
      loc == RoutePaths.signup ||
      loc == RoutePaths.forgotPassword ||
      isResetPassword;
  final isOnboardingRoute = loc == RoutePaths.onboardingWalkthrough;

  // Not logged in → force to login (allow nothing else)
  if (!isLoggedIn && !isAuthRoute) {
    return RoutePaths.login;
  }

  // Logged in on an auth page → send to home (except reset-password
  // which is legitimately reachable via deep link while signed in).
  if (isLoggedIn && isAuthRoute && !isResetPassword) {
    return RoutePaths.home;
  }

  // Logged in, onboarding not complete → force to walkthrough.
  // Skip if pref hasn't loaded yet (null) or if already on an onboarding route.
  if (isLoggedIn &&
      isOnboardingComplete == false &&
      !isOnboardingRoute &&
      !isResetPassword) {
    return RoutePaths.onboardingWalkthrough;
  }

  return null;
}
