import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/auth_refresh_notifier_provider.dart';
import '../providers/admin_role_provider.dart';
import '../providers/repository_providers.dart';
import 'admin_route_access.dart';
import 'admin_route_names.dart';
import '../../features/admin_auth/presentation/pages/admin_login_page.dart';
import '../../features/admin_auth/presentation/pages/admin_access_denied_page.dart';
import '../../features/admin_auth/presentation/pages/confirm_email_page.dart';
import '../../features/dashboard/presentation/pages/admin_dashboard_page.dart';
import '../../features/moderation/presentation/pages/pending_submissions_page.dart';
import '../../features/moderation/presentation/pages/submission_review_page.dart';
import '../../features/moderation/presentation/pages/submission_history_page.dart';
import '../../features/feed_management/presentation/pages/feed_management_page.dart';
import '../../features/quest_management/presentation/pages/quest_management_page.dart';
import '../../features/quest_of_day/presentation/pages/qotd_management_page.dart';
import '../../features/map_places/presentation/pages/map_places_page.dart';
import '../../features/users/presentation/pages/users_page.dart';
import '../../features/announcements/presentation/pages/announcements_page.dart';
import '../../features/xp_management/presentation/pages/xp_management_page.dart';
import '../../features/auto_notifications/presentation/pages/auto_notifications_page.dart';
import '../../features/appeals/presentation/pages/appeals_page.dart';
import '../../features/reports/presentation/pages/reports_page.dart';
import '../../features/quest_injection/presentation/pages/quest_injection_page.dart';
import '../../features/settings/presentation/pages/app_settings_page.dart';
import '../../features/web_signups/presentation/pages/web_signups_page.dart';
import '../../features/web_quest_suggestions/presentation/pages/web_quest_suggestions_page.dart';
import '../../features/deletion_requests/presentation/pages/deletion_requests_page.dart';
import '../../shared/layout/admin_shell.dart';
import '../../features/legal/privacy_policy_page.dart';
import '../../features/legal/delete_account_page.dart';

final adminRouterProvider = Provider<GoRouter>((ref) {
  final refresh = ref.watch(authRefreshNotifierProvider);
  // Re-evaluate redirects when admin-role resolution flips (e.g. just
  // after login the FutureProvider goes loading → data, and we want
  // the gate from SEC-027 to immediately allow / deny once we know).
  //
  // This listens to the same provider the redirect reads. It used to
  // listen to `isAdminUserProvider`, which awaits `adminRoleEnumProvider`
  // and therefore resolves one microtask later — poking on the earlier of
  // the two while reading the later one is how a gate ends up waiting for
  // a notification that has already been sent.
  ref.listen(adminRoleEnumProvider, (_, __) => refresh.poke());

  return GoRouter(
    initialLocation: AdminRoutePaths.login,
    refreshListenable: refresh,
    redirect: (context, state) {
      final user = ref.read(authRepositoryProvider).currentUser;
      final path = state.uri.path;
      final loggingIn = path == AdminRoutePaths.login;
      final isPublic = path == AdminRoutePaths.privacy ||
          path == AdminRoutePaths.deleteAccount ||
          path == AdminRoutePaths.confirmEmail;
      if (user == null && !loggingIn && !isPublic) {
        return AdminRoutePaths.login;
      }
      // The signed-in admin's role, resolved once by `GET admin/me`. Both
      // gates below read it: "is this person an admin at all" and "is this
      // particular destination open to their role" are the same question
      // asked at two depths, and they must not be able to disagree.
      final role = ref.read(adminRoleEnumProvider).valueOrNull;
      if (user != null && loggingIn && role != null) {
        return AdminRoutePaths.dashboard;
      }
      // SEC-027: gate every authenticated, non-public route on admin
      // role at the redirect boundary instead of relying on AdminShell's
      // post-mount check. Stops feature pages from running their
      // FutureProviders for non-admin signed-in users.
      if (user != null && !loggingIn && !isPublic) {
        // null is either "not an admin" or "the role has not resolved
        // yet". Both mean we must not paint the page, so bounce to the
        // login gate; the poke above brings us back the moment it lands.
        if (role == null) {
          return AdminRoutePaths.login;
        }
        // Role gating, and the reason it lives here rather than only in
        // the sidebar: this is a web app, so a moderator can type
        // `/quests` and arrive at a screen whose every read is
        // `@Roles('super_admin')`. Hiding the link is not access control
        // — it only hides the 403. Refuse the navigation instead and land
        // them somewhere their role can actually use.
        if (!AdminRouteAccess.allows(path, role)) {
          return AdminRoutePaths.dashboard;
        }
      }
      return null;
    },
    routes: [
      GoRoute(
        path: AdminRoutePaths.login,
        name: AdminRouteNames.login,
        builder: (context, state) => Consumer(builder: (context, ref, _) {
          if (ref.watch(authRepositoryProvider).currentUser == null) {
            return const AdminLoginPage();
          }
          return ref.watch(isAdminUserProvider).when(
                loading: () => const Scaffold(
                  body: Center(child: CircularProgressIndicator()),
                ),
                error: (_, __) => const AdminAccessDeniedPage(),
                // A confirmed admin briefly lands here between resolving the
                // role and the redirect firing. This used to discard the
                // value and render "access denied" to a legitimate super
                // admin — alarming, and wrong. Wait for the redirect instead.
                data: (isAdmin) => isAdmin
                    ? const Scaffold(
                        body: Center(child: CircularProgressIndicator()),
                      )
                    : const AdminAccessDeniedPage(),
              );
        }),
      ),
      GoRoute(
        path: AdminRoutePaths.confirmEmail,
        name: AdminRouteNames.confirmEmail,
        builder: (context, state) => ConfirmEmailPage(
          token: state.uri.queryParameters['token'],
          // Lets the page draw its "check your email" state and target a
          // resend. Never used to confirm anything — the token does that.
          email: state.uri.queryParameters['email'],
        ),
      ),
      GoRoute(
        path: AdminRoutePaths.privacy,
        builder: (context, state) => const PrivacyPolicyPage(),
      ),
      GoRoute(
        path: AdminRoutePaths.deleteAccount,
        builder: (context, state) => const DeleteAccountPage(),
      ),
      ShellRoute(
        builder: (context, state, child) => AdminShell(child: child),
        routes: [
          GoRoute(
            path: AdminRoutePaths.dashboard,
            name: AdminRouteNames.dashboard,
            builder: (context, state) => const AdminDashboardPage(),
          ),
          GoRoute(
            path: AdminRoutePaths.pendingSubmissions,
            name: AdminRouteNames.pendingSubmissions,
            builder: (context, state) => const PendingSubmissionsPage(),
          ),
          GoRoute(
            path: AdminRoutePaths.submissionReview,
            name: AdminRouteNames.submissionReview,
            builder: (context, state) => SubmissionReviewPage(
              submissionId: state.pathParameters['id']!,
            ),
          ),
          GoRoute(
            path: AdminRoutePaths.submissionHistory,
            name: AdminRouteNames.submissionHistory,
            builder: (context, state) => const SubmissionHistoryPage(),
          ),
          GoRoute(
            path: AdminRoutePaths.feedManagement,
            name: AdminRouteNames.feedManagement,
            builder: (context, state) => const FeedManagementPage(),
          ),
          GoRoute(
            path: AdminRoutePaths.questManagement,
            name: AdminRouteNames.questManagement,
            builder: (context, state) => const QuestManagementPage(),
          ),
          GoRoute(
            path: AdminRoutePaths.questOfTheDay,
            name: AdminRouteNames.questOfTheDay,
            builder: (context, state) => const QotdManagementPage(),
          ),
          GoRoute(
            path: AdminRoutePaths.mapPlaces,
            name: AdminRouteNames.mapPlaces,
            builder: (context, state) => const MapPlacesPage(),
          ),
          GoRoute(
            path: AdminRoutePaths.users,
            name: AdminRouteNames.users,
            builder: (context, state) => UsersPage(
              initialQuery: state.uri.queryParameters['q'],
            ),
          ),
          GoRoute(
            path: AdminRoutePaths.xpManagement,
            name: AdminRouteNames.xpManagement,
            builder: (context, state) => const XpManagementPage(),
          ),
          GoRoute(
            path: AdminRoutePaths.announcements,
            name: AdminRouteNames.announcements,
            builder: (context, state) => const AnnouncementsPage(),
          ),
          GoRoute(
            path: AdminRoutePaths.autoNotifications,
            name: AdminRouteNames.autoNotifications,
            builder: (context, state) => const AutoNotificationsPage(),
          ),
          GoRoute(
            path: AdminRoutePaths.appeals,
            name: AdminRouteNames.appeals,
            builder: (context, state) => const AppealsPage(),
          ),
          GoRoute(
            path: AdminRoutePaths.reports,
            name: AdminRouteNames.reports,
            builder: (context, state) => const ReportsPage(),
          ),
          GoRoute(
            path: AdminRoutePaths.injection,
            name: AdminRouteNames.injection,
            builder: (context, state) => const QuestInjectionPage(),
          ),
          GoRoute(
            path: AdminRoutePaths.settings,
            name: AdminRouteNames.settings,
            builder: (context, state) => const AppSettingsPage(),
          ),
          GoRoute(
            path: AdminRoutePaths.webSignups,
            name: AdminRouteNames.webSignups,
            builder: (context, state) => const WebSignupsPage(),
          ),
          GoRoute(
            path: AdminRoutePaths.webQuestSuggestions,
            name: AdminRouteNames.webQuestSuggestions,
            builder: (context, state) => const WebQuestSuggestionsPage(),
          ),
          GoRoute(
            path: AdminRoutePaths.deletionRequests,
            name: AdminRouteNames.deletionRequests,
            builder: (context, state) => const DeletionRequestsPage(),
          ),
        ],
      ),
    ],
  );
});
