import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:mobile_app/core/router/app_router.dart';
import 'package:mobile_app/core/router/route_names.dart';
import 'package:mobile_app/features/dev/presentation/demo_launcher_overlay.dart';

/// The launcher badge floats above the app's Navigator, which is what makes
/// it reachable from every screen and also what breaks the obvious ways of
/// implementing it. Two things went wrong there and neither showed up as an
/// error on screen — the button simply did nothing:
///
///  1. `Draggable` asserts without an Overlay ancestor, and there is none
///     above the Navigator.
///  2. `Navigator.of(context)` finds nothing from `MaterialApp.builder`, so
///     the tap handler threw into the void.
///
/// So this test taps the real badge in a real MaterialApp.builder position
/// and asserts a route was actually pushed.
void main() {
  testWidgets('the demo badge is tappable from above the Navigator',
      (tester) async {
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (_, __) => const Text('home')),
        GoRoute(
          path: '/camara-demo',
          name: RouteNames.camaraDemo,
          builder: (_, __) => const Text('demo-opened'),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appRouterProvider.overrideWithValue(router)],
        child: MaterialApp.router(
          routerConfig: router,
          // Exactly where the real app mounts it: above the Navigator.
          builder: (context, child) => DemoLauncherOverlay(
            child: child ?? const SizedBox.shrink(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // It rendered at all — the Draggable regression made this throw.
    expect(find.text('CAMARA'), findsOneWidget);
    expect(find.text('home'), findsOneWidget);

    await tester.tap(find.text('CAMARA'));
    await tester.pumpAndSettle();

    // And the tap went somewhere, which the Navigator.of version did not.
    expect(find.text('demo-opened'), findsOneWidget);
  });
}
