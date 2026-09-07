import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'pending_deep_link.dart';
import 'route_names.dart';
import 'route_guards.dart';
import '../providers/auth_state_provider.dart';
import '../providers/auth_session_provider.dart';
import '../../features/onboarding/presentation/providers/onboarding_provider.dart';
import '../../features/auth/presentation/pages/login_page.dart';
import '../../features/auth/presentation/pages/signup_page.dart';
import '../../features/auth/presentation/pages/forgot_password_page.dart';
import '../../features/auth/presentation/pages/reset_password_page.dart';
import '../../features/onboarding/presentation/pages/onboarding_walkthrough_page.dart';
import '../../features/quests/presentation/pages/home_page.dart';
import '../../features/quests/presentation/pages/quest_details_page.dart';
import '../../features/quests/presentation/pages/quest_history_page.dart';
import '../../features/submissions/presentation/pages/submit_proof_page.dart';
import '../../features/submissions/presentation/pages/submission_status_page.dart';
import '../../features/feed/presentation/pages/feed_page.dart';
import '../../features/feed/presentation/pages/feed_post_details_page.dart';
import '../../features/search/presentation/pages/search_page.dart';
import '../../features/leaderboard/presentation/pages/leaderboard_page.dart';
import '../../features/profile/presentation/pages/profile_page.dart';
import '../../features/profile/presentation/pages/edit_profile_page.dart';
import '../../features/notifications/presentation/pages/notifications_page.dart';
import '../../features/collab/presentation/pages/collab_page.dart';
import '../../features/collab/presentation/pages/join_collab_page.dart';
import '../../features/settings/presentation/pages/blocked_users_page.dart';
import '../../features/settings/presentation/pages/settings_page.dart';
import '../../features/admin/presentation/pages/admin_page.dart';
import '../../features/legal/presentation/pages/privacy_policy_page.dart';
import '../../features/legal/presentation/pages/terms_page.dart';
import '../../shared/navigation/bottom_nav_shell.dart';
import '../../features/splash/arcade_splash_screen.dart';

// C4 (2026-05-17): deep-link parameter validation. Any unvalidated
// path or query param coming off a deep link is an injection surface —
// an attacker-crafted bitsheel:// or https://admin.bsheel.app/
// link with garbage IDs could crash the app, reach a confused page,
// or be reflected into logs. Validate strictly: route params that
// look like UUIDs must match the canonical UUID shape, and the collab
// join code must match the 8-char alphanumeric format.
final RegExp _uuidRe = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);
bool _isUuid(String? s) => s != null && _uuidRe.hasMatch(s);

final RegExp _collabCodeRe = RegExp(r'^[A-Za-z0-9]{4,16}$');
bool _isCollabCode(String? s) => s != null && _collabCodeRe.hasMatch(s);

/// True once the splash screen has played at least once on this device.
///
/// Persisted to SharedPreferences (loaded by [primeSplashShownFlag] during
/// bootstrap), so the Flutter splash plays exactly once after install —
/// the iOS LaunchScreen / Android system splash takes care of the rest of
/// the launches, matching Instagram-style behaviour.
///
/// Resets on uninstall/reinstall (prefs wiped). The in-memory portion also
/// guards against the same-process re-entry that used to play the splash
/// twice when GoRouter rebuilt mid-animation.
bool _splashShownThisProcess = false;
const String _splashShownPrefsKey = 'splash_shown_v1';

/// Called from `bootstrap()` so the value is ready synchronously by the
/// time `appRouterProvider` builds the GoRouter. Failures are swallowed —
/// the worst case is one extra splash play.
Future<void> primeSplashShownFlag() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    _splashShownThisProcess = prefs.getBool(_splashShownPrefsKey) ?? false;
  } catch (_) {
    _splashShownThisProcess = false;
  }
}

Future<void> _persistSplashShown() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_splashShownPrefsKey, true);
  } catch (_) {
    // Non-fatal: splash will just play once more next cold start.
  }
}

final appRouterProvider = Provider<GoRouter>((ref) {
  // IMPORTANT: read these providers, do NOT watch them.
  //
  // Watching `authSessionProvider` / `onboardingCompleteProvider` here
  // causes the provider to rebuild — and therefore re-create the GoRouter
  // — every time auth or onboarding state changes during cold start.
  // Each new GoRouter freshly mounts its `initialLocation`, which is
  // `splash` until the splash flag flips, so the splash widget kept
  // remounting mid-animation and the user saw the splash play twice.
  //
  // The AuthNotifier already drives GoRouter via `refreshListenable`, so
  // redirects re-run on auth ticks without us recreating the router.
  // Inside `redirect` we `ref.read` the latest values on demand, which
  // keeps guard logic up-to-date with no router rebuild.
  final authNotifier = ref.read(authNotifierProvider);

  // Onboarding state isn't part of authNotifier, but we still need
  // GoRouter to re-evaluate guards when SharedPreferences resolves. Use
  // a tiny ticker that bumps whenever the onboarding-complete value
  // changes, and merge it with the auth notifier as the refreshListenable.
  final onboardingTicker = ValueNotifier<int>(0);
  ref.listen(onboardingCompleteProvider, (prev, next) {
    if (prev?.valueOrNull != next.valueOrNull) onboardingTicker.value++;
  });
  ref.onDispose(onboardingTicker.dispose);
  final routerRefresh = Listenable.merge([authNotifier, onboardingTicker]);

  return GoRouter(
    // Splash is the cold-start entry; on warm router rebuilds (auth state
    // change, theme change, etc.) jump straight to /home so users don't
    // see the splash again.
    initialLocation:
        _splashShownThisProcess ? RoutePaths.home : RoutePaths.splash,
    refreshListenable: routerRefresh,
    redirect: (context, state) {
      final currentUser = ref.read(authSessionProvider);
      final onboardingAsync = ref.read(onboardingCompleteProvider);
      final result = authRedirect(
        location: state.matchedLocation,
        isLoggedIn: currentUser != null,
        isOnboardingComplete: onboardingAsync.valueOrNull,
      );
      // UX-002: remember where a logged-out user was trying to go so we
      // can land them there after sign-in.
      if (result == RoutePaths.login && currentUser == null) {
        ref.read(pendingDeepLinkProvider.notifier).save(state.uri.toString());
        return result;
      }
      // UX-002: when the auth redirect is about to send a freshly-logged-
      // in user to /home, consume the pending deep link instead. Skip the
      // override if the saved path is /home or matches the pending nav
      // (avoids redirect loops).
      if (result == RoutePaths.home && currentUser != null) {
        final pending = ref.read(pendingDeepLinkProvider.notifier).consume();
        if (pending != null && pending != RoutePaths.home) {
          return pending;
        }
      }
      return result;
    },
    routes: [
      // Splash — initial route. On animation completion, navigates to
      // RoutePaths.home; the auth redirect chain takes it from there
      // (login if not signed in, walkthrough if onboarding incomplete,
      // bottom-nav shell otherwise).
      //
      // Exception: if a `passwordRecovery` deep link fired during the
      // splash animation, `passwordRecoveryProvider` will be true and
      // `app.dart`'s listener will have already queued a go-to-reset-
      // password navigation. Don't overwrite it with /home here.
      GoRoute(
        path: RoutePaths.splash,
        name: RouteNames.splash,
        builder: (context, state) => Consumer(
          builder: (context, cref, _) => ArcadeSplashScreen(
            onReady: () {
              _splashShownThisProcess = true;
              // Persist so subsequent cold starts skip the Flutter splash
              // entirely — iOS LaunchScreen / Android system splash is
              // enough on every launch after the first install.
              // ignore: unawaited_futures
              _persistSplashShown();
              if (!context.mounted) return;
              if (cref.read(passwordRecoveryProvider)) return;
              context.go(RoutePaths.home);
            },
          ),
        ),
      ),
      // Auth routes
      GoRoute(
        path: RoutePaths.login,
        name: RouteNames.login,
        builder: (context, state) => const LoginPage(),
      ),
      GoRoute(
        path: RoutePaths.signup,
        name: RouteNames.signup,
        builder: (context, state) => const SignupPage(),
      ),
      GoRoute(
        path: RoutePaths.forgotPassword,
        name: RouteNames.forgotPassword,
        builder: (context, state) => const ForgotPasswordPage(),
      ),
      GoRoute(
        path: RoutePaths.resetPassword,
        name: RouteNames.resetPassword,
        builder: (context, state) => ResetPasswordPage(
          recoveryToken: state.uri.queryParameters['token'],
        ),
      ),
      GoRoute(
        path: RoutePaths.onboardingWalkthrough,
        name: RouteNames.onboardingWalkthrough,
        builder: (context, state) => const OnboardingWalkthroughPage(),
      ),

      // Main shell with bottom navigation
      ShellRoute(
        builder: (context, state, child) => BottomNavShell(child: child),
        routes: [
          GoRoute(
            path: RoutePaths.home,
            name: RouteNames.home,
            builder: (context, state) => const HomePage(),
          ),
          GoRoute(
            path: RoutePaths.feed,
            name: RouteNames.feed,
            builder: (context, state) => const FeedPage(),
          ),
          GoRoute(
            path: RoutePaths.collab,
            name: RouteNames.collab,
            builder: (context, state) => const CollabPage(),
          ),
          GoRoute(
            path: RoutePaths.leaderboard,
            name: RouteNames.leaderboard,
            builder: (context, state) => const LeaderboardPage(),
          ),
          GoRoute(
            path: RoutePaths.profile,
            name: RouteNames.profile,
            builder: (context, state) => const ProfilePage(),
          ),
        ],
      ),

      // Detail routes
      GoRoute(
        path: RoutePaths.questDetails,
        name: RouteNames.questDetails,
        builder: (context, state) =>
            QuestDetailsPage(questId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: RoutePaths.questHistory,
        name: RouteNames.questHistory,
        builder: (context, state) => const QuestHistoryPage(),
      ),
      GoRoute(
        path: RoutePaths.submitProof,
        name: RouteNames.submitProof,
        redirect: (context, state) =>
            _isUuid(state.pathParameters['userQuestId'])
                ? null
                : RoutePaths.home,
        builder: (context, state) =>
            SubmitProofPage(userQuestId: state.pathParameters['userQuestId']!),
      ),
      GoRoute(
        path: RoutePaths.submissionStatus,
        name: RouteNames.submissionStatus,
        redirect: (context, state) =>
            _isUuid(state.pathParameters['id']) ? null : RoutePaths.home,
        builder: (context, state) =>
            SubmissionStatusPage(submissionId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: RoutePaths.feedPostDetails,
        name: RouteNames.feedPostDetails,
        redirect: (context, state) =>
            _isUuid(state.pathParameters['id']) ? null : RoutePaths.home,
        builder: (context, state) =>
            FeedPostDetailsPage(postId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: RoutePaths.search,
        name: RouteNames.search,
        builder: (context, state) => const SearchPage(),
      ),
      GoRoute(
        path: RoutePaths.editProfile,
        name: RouteNames.editProfile,
        builder: (context, state) => const EditProfilePage(),
      ),
      GoRoute(
        path: RoutePaths.userProfile,
        name: RouteNames.userProfile,
        redirect: (context, state) {
          final id = state.pathParameters['userId'];
          // userId is optional on this route (own profile view), but if
          // present it must be a valid UUID — never a tampered string.
          if (id == null) return null;
          return _isUuid(id) ? null : RoutePaths.home;
        },
        builder: (context, state) => ProfilePage(
          userId: state.pathParameters['userId'],
        ),
      ),
      GoRoute(
        path: RoutePaths.notifications,
        name: RouteNames.notifications,
        builder: (context, state) => const NotificationsPage(),
      ),
      GoRoute(
        path: RoutePaths.settings,
        name: RouteNames.settings,
        builder: (context, state) => const SettingsPage(),
      ),
      GoRoute(
        path: RoutePaths.blockedUsers,
        name: RouteNames.blockedUsers,
        builder: (context, state) => const BlockedUsersPage(),
      ),
      GoRoute(
        path: RoutePaths.admin,
        name: RouteNames.admin,
        redirect: (context, state) {
          if (ref.read(authSessionProvider) == null) return RoutePaths.home;
          final isAdmin = ref.read(isAdminProvider);
          final value = isAdmin.valueOrNull;
          if (value == false) return RoutePaths.home;
          return null;
        },
        builder: (context, state) => const AdminPage(),
      ),
      GoRoute(
        path: RoutePaths.joinCollab,
        name: RouteNames.joinCollab,
        redirect: (context, state) =>
            _isCollabCode(state.pathParameters['code'])
                ? null
                : RoutePaths.home,
        builder: (context, state) =>
            JoinCollabPage(code: state.pathParameters['code']!),
      ),
      GoRoute(
        path: RoutePaths.privacyPolicy,
        name: RouteNames.privacyPolicy,
        builder: (context, state) => const PrivacyPolicyPage(),
      ),
      GoRoute(
        path: RoutePaths.terms,
        name: RouteNames.terms,
        builder: (context, state) => const TermsPage(),
      ),
    ],
  );
});
