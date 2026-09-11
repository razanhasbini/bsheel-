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
  // Every account must carry a CAMARA-verified phone number. Defaults to
  // "already verified" only so unrelated existing tests that don't pass it
  // keep exercising the paths they were written for.
  bool isPhoneVerified = true,
}) {
  final loc = location;
  // Splash is exempt from any redirect during its own playback — it owns
  // the initial frame and navigates to /home itself once its animation
  // finishes. (Skipping splash on warm rebuilds is handled by
  // `_splashShownThisProcess` in app_router.dart's initialLocation.)
  if (loc == RoutePaths.splash) return null;

  // Reachable regardless of auth state: it's the landing spot for the
  // CAMARA Number Verification redirect, which lands here BEFORE the user
  // is signed in when this is a brand-new phone sign-in (not just when
  // linking a phone to an already-signed-in account). It processes the
  // link and leaves immediately — never a real page to guard.
  if (loc == RoutePaths.phoneSigninCallback) return null;

  // TEMPORARY (hackathon demo): exempt so the floating badge always opens
  // the page. It needs a session to call anything, and says so plainly when
  // there is none — which is more useful to a judge than being silently
  // bounced to the login screen with no explanation.
  if (loc == RoutePaths.camaraDemo) return null;

  final isResetPassword = loc == RoutePaths.resetPassword;
  final isAuthRoute = loc == RoutePaths.login ||
      loc == RoutePaths.signup ||
      loc == RoutePaths.forgotPassword ||
      isResetPassword;
  final isOnboardingRoute = loc == RoutePaths.onboardingWalkthrough;
  final isVerifyPhoneRoute = loc == RoutePaths.verifyPhone;

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

  // Every account needs a CAMARA-verified phone number — it is the device
  // identifier location-based quest submissions are checked against, and
  // the anchor of the account itself. Applies however the account was
  // created (password/Google/Apple); an account created via phone sign-in
  // already has one and never lands here.
  //
  // Exempt while on the walkthrough. The onboarding rule above sends an
  // un-onboarded user there from anywhere — including from /verify-phone —
  // so without this exemption a user who is both un-onboarded and
  // unverified ping-pongs between the two until GoRouter gives up with
  // "redirect loop detected". Onboarding runs first; the walkthrough's own
  // exit goes to /home, where this rule catches them.
  if (isLoggedIn &&
      !isPhoneVerified &&
      !isVerifyPhoneRoute &&
      !isOnboardingRoute &&
      !isResetPassword) {
    return RoutePaths.verifyPhone;
  }

  // Verified but still sitting on the verify page — move on. Without this
  // the page has no way to leave itself once the redirect above stops firing.
  if (isLoggedIn && isVerifyPhoneRoute && isPhoneVerified) {
    return RoutePaths.home;
  }

  return null;
}
