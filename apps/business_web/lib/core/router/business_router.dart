import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/session_providers.dart';
import '../../features/auth/business_login_page.dart';
import '../../features/dashboard/dashboard_page.dart';
import '../../features/dashboard/not_a_business_page.dart';

abstract final class BusinessRoutes {
  static const String login = '/login';
  static const String dashboard = '/';
  static const String notABusiness = '/no-access';
}

/// Re-evaluates redirects when the session or the membership read settles.
class _Refresh extends ChangeNotifier {
  void poke() => notifyListeners();
}

/// The router, and the one thing it must get right.
///
/// A signed-in user who is not a business member is sent to an explanatory
/// page rather than bounced to login. Bouncing would be a loop: their
/// credentials are valid, so they would sign in, be refused, and land back
/// at the form with nothing telling them why. This app is not an authority
/// boundary — the API refuses a non-member with a 404 whatever the client
/// does — so the client's job here is to explain, not to defend.
///
/// While the membership read is in flight nothing is decided. Treating
/// "not resolved yet" as "not a member" would flash the refusal page at
/// every legitimate owner on every reload.
final businessRouterProvider = Provider<GoRouter>((ref) {
  final refresh = _Refresh();
  ref.listen(sessionProvider, (_, __) => refresh.poke());
  ref.listen(myBusinessesProvider, (_, __) => refresh.poke());
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: BusinessRoutes.dashboard,
    refreshListenable: refresh,
    redirect: (context, state) {
      final session = ref.read(sessionProvider);
      final path = state.uri.path;
      final loggingIn = path == BusinessRoutes.login;

      if (session == null) return loggingIn ? null : BusinessRoutes.login;

      final businesses = ref.read(myBusinessesProvider);
      // Still asking. Decide nothing.
      if (businesses.isLoading) return null;
      // Could not ask. Also decide nothing — the dashboard renders the
      // error, which is recoverable, rather than claiming no access.
      if (businesses.hasError) {
        return loggingIn ? BusinessRoutes.dashboard : null;
      }

      final isMember = (businesses.valueOrNull ?? const []).isNotEmpty;
      if (!isMember) {
        return path == BusinessRoutes.notABusiness
            ? null
            : BusinessRoutes.notABusiness;
      }
      if (loggingIn || path == BusinessRoutes.notABusiness) {
        return BusinessRoutes.dashboard;
      }
      return null;
    },
    routes: [
      GoRoute(
        path: BusinessRoutes.login,
        builder: (context, state) => const BusinessLoginPage(),
      ),
      GoRoute(
        path: BusinessRoutes.notABusiness,
        builder: (context, state) => const NotABusinessPage(),
      ),
      GoRoute(
        path: BusinessRoutes.dashboard,
        builder: (context, state) => DashboardPage(
          // The mobile card appends ?business=<id> so an owner of two lands
          // on the right one. Validated against membership, never trusted.
          requestedBusinessId: state.uri.queryParameters['business'],
        ),
      ),
    ],
  );
});
