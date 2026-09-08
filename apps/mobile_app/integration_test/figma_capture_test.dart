// Captures screenshots of every logged-in screen for Figma import.
//
// Run with:
//   ./scripts/capture_for_figma.sh
//
// Or manually:
//   flutter drive \
//     --driver=test_driver/integration_test.dart \
//     --target=integration_test/figma_capture_test.dart \
//     -d <iphone-17-udid> \
//     --dart-define-from-file=.env.test \
//     --dart-define=API_URL=https://api.bsheel.app/api/v1 \
//     --dart-define=MIXPANEL_TOKEN=...

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mobile_app/app.dart';
import 'package:mobile_app/core/backend/app_backend.dart';
import 'package:mobile_app/bootstrap.dart';

const _testEmail = String.fromEnvironment('TEST_EMAIL');
const _testPassword = String.fromEnvironment('TEST_PASSWORD');

// (path, figma-filename-label)
//
// Order chosen so anything that depends on freshly-mounted shell state
// (bottom-nav highlight, etc.) settles first. Add path-param routes here
// once you know real ids — quest/:id, post/:id, submission/:id, user/:userId.
const _routesToCapture = <(String, String)>[
  ('/', 'home-default'),
  ('/feed', 'feed-default'),
  ('/collab', 'collab-default'),
  ('/leaderboard', 'leaderboard-default'),
  ('/profile', 'profile-default'),
  ('/quest-history', 'home-quest-history'),
  ('/submission-history', 'home-submission-history'),
  ('/search', 'discovery-search'),
  ('/profile/edit', 'profile-edit'),
  ('/notifications', 'notifications-default'),
  ('/settings', 'settings-default'),
  ('/privacy', 'legal-privacy'),
  ('/terms', 'legal-terms'),
];

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Capture all logged-in screens for Figma', (tester) async {
    expect(_testEmail, isNotEmpty,
        reason: 'TEST_EMAIL not set — pass --dart-define-from-file=.env.test');
    expect(_testPassword, isNotEmpty, reason: 'TEST_PASSWORD not set');

    // Initialise the backend before pumping the app — same as production
    // main().
    await bootstrap();

    // Skip the onboarding walkthrough so navigations don't get redirected
    // back to /onboarding-walkthrough. This is what `SharedPreferences`
    // would record after a real user clicks through the walkthrough once.
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_complete', true);

    // Sign in through the auth repository (no UI tap). The auth notifier
    // picks the session up when the app mounts and redirects past /login.
    final auth = AppBackend.repositories.auth;
    if (auth.currentUser == null) {
      await auth.signInWithEmail(_testEmail, _testPassword);
    }
    expect(
      auth.currentUser,
      isNotNull,
      reason: 'Sign-in failed — check creds in .env.test',
    );

    await tester.pumpWidget(const ProviderScope(child: QuestApp()));

    // Wait through splash (2.4s animation) + auth/onboarding redirect chain
    // so we land on /home before we start navigating. We can't pumpAndSettle
    // here because /home has perpetual animations (timer ticks, shimmer loaders)
    // that never quiesce. Just pump fixed durations long enough for the splash
    // to finish + post-redirect mount work to complete.
    await tester.pump();
    await tester.pump(const Duration(seconds: 4));
    await tester.pump(const Duration(seconds: 3));

    // Grab a context that's a descendant of the GoRouter so GoRouter.of works.
    final navFinder = find.byType(Navigator);
    expect(navFinder, findsWidgets,
        reason: 'No Navigator mounted — splash may have stalled');
    final BuildContext ctx = tester.element(navFinder.first);

    for (final entry in _routesToCapture) {
      final path = entry.$1;
      final label = entry.$2;

      // ignore: use_build_context_synchronously
      GoRouter.of(ctx).go(path);

      // Initial mount + first frame.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Let network-bound screens settle. pumpAndSettle bails on infinite
      // animations (shimmer), so we cap with a finite extra pump after.
      try {
        await tester.pumpAndSettle(const Duration(seconds: 4));
      } catch (_) {
        // pumpAndSettle threw because of an always-running animation. Fine —
        // we still got several frames in. Capture anyway.
      }
      await tester.pump(const Duration(milliseconds: 400));

      await binding.takeScreenshot(label);
    }
  }, timeout: const Timeout(Duration(minutes: 15)));
}
