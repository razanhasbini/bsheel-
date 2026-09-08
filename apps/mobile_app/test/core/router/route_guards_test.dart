import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/core/router/route_guards.dart';
import 'package:mobile_app/core/router/route_names.dart';

void main() {
  group('authRedirect — signed OUT', () {
    test('any protected route bounces to login', () {
      for (final loc in [
        RoutePaths.home,
        RoutePaths.feed,
        RoutePaths.settings,
        '/post/abc',
        '/user/xyz',
      ]) {
        expect(
          authRedirect(location: loc, isLoggedIn: false),
          RoutePaths.login,
          reason: loc,
        );
      }
    });

    test('auth routes are reachable while signed out', () {
      for (final loc in [
        RoutePaths.login,
        RoutePaths.signup,
        RoutePaths.forgotPassword,
        RoutePaths.resetPassword,
      ]) {
        expect(authRedirect(location: loc, isLoggedIn: false), isNull,
            reason: loc);
      }
    });

    test('splash is exempt from redirects', () {
      expect(
          authRedirect(location: RoutePaths.splash, isLoggedIn: false), isNull);
    });
  });

  group('authRedirect — signed IN', () {
    test('login/signup/forgot bounce to home', () {
      for (final loc in [
        RoutePaths.login,
        RoutePaths.signup,
        RoutePaths.forgotPassword,
      ]) {
        expect(
          authRedirect(
              location: loc, isLoggedIn: true, isOnboardingComplete: true),
          RoutePaths.home,
          reason: loc,
        );
      }
    });

    test('reset-password stays reachable while signed in (recovery link)', () {
      expect(
        authRedirect(
            location: RoutePaths.resetPassword,
            isLoggedIn: true,
            isOnboardingComplete: true),
        isNull,
      );
    });

    test('protected routes pass through when onboarded', () {
      expect(
        authRedirect(
            location: RoutePaths.home,
            isLoggedIn: true,
            isOnboardingComplete: true),
        isNull,
      );
    });
  });

  group('authRedirect — onboarding gate', () {
    test('incomplete onboarding forces the walkthrough', () {
      expect(
        authRedirect(
            location: RoutePaths.home,
            isLoggedIn: true,
            isOnboardingComplete: false),
        RoutePaths.onboardingWalkthrough,
      );
    });

    test('already on the walkthrough → no redirect loop', () {
      expect(
        authRedirect(
            location: RoutePaths.onboardingWalkthrough,
            isLoggedIn: true,
            isOnboardingComplete: false),
        isNull,
      );
    });

    test(
        'unknown onboarding state (null) does not bounce — avoids a false '
        'negative while the pref loads', () {
      expect(
        authRedirect(
            location: RoutePaths.home,
            isLoggedIn: true,
            isOnboardingComplete: null),
        isNull,
      );
    });

    test('recovery link wins over the onboarding gate', () {
      expect(
        authRedirect(
            location: RoutePaths.resetPassword,
            isLoggedIn: true,
            isOnboardingComplete: false),
        isNull,
      );
    });
  });
}
