import 'package:admin_web/app.dart';
import 'package:admin_web/core/providers/admin_counts_provider.dart';
import 'package:admin_web/core/providers/admin_role_provider.dart';
import 'package:admin_web/core/providers/repository_providers.dart';
import 'package:admin_web/core/router/admin_route_access.dart';
import 'package:admin_web/core/router/admin_route_names.dart';
import 'package:admin_web/core/router/admin_router.dart';
import 'package:admin_web/features/quest_management/presentation/pages/quest_management_page.dart';
import 'package:app_repositories/app_repositories.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Auth extends Fake implements AuthRepository {
  _Auth(this.currentUser);

  @override
  final AuthUser? currentUser;

  @override
  Stream<AuthState> get authStateChanges => const Stream.empty();
}

/// The network boundary for `GET admin/me`. The role chain
/// (`authUserIdProvider` → `adminRoleEnumProvider`) is the real one, so
/// the gate under test reads the role the same way the app does.
class _RoleLookup extends Fake implements AdminRepository {
  _RoleLookup(this.role);

  final AdminRoleEnum role;

  @override
  Future<AdminRoleEnum?> getCurrentUserRole() async => role;
}

/// The console, signed in as an admin holding [role], at desktop width so
/// the sidebar is a rail rather than a drawer.
Future<ProviderContainer> _pumpConsole(
  WidgetTester tester,
  AdminRoleEnum role,
) async {
  // Tall enough to build every destination row. The sidebar's list is a
  // lazy `ListView`, so at 1000px the last few were never constructed —
  // which broke the super-admin assertion for SETTINGS and, worse, made the
  // moderator's `findsNothing` for SETTINGS and INJECTION pass because they
  // were off-screen rather than because they were filtered out. Presence and
  // absence only mean anything when every row is realised.
  tester.view.physicalSize = const Size(1600, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final container = ProviderContainer(overrides: [
    authRepositoryProvider
        .overrideWithValue(_Auth(const AuthUser(id: 'the-admin'))),
    adminRepositoryProvider.overrideWithValue(_RoleLookup(role)),
    // The badge counts and their realtime socket are not the subject and
    // would reach for an uninitialised transport.
    adminCountsProvider.overrideWith((ref) async => const AdminCounts.zero()),
    adminCountsRealtimeProvider.overrideWith((ref) {}),
  ]);
  addTearDown(container.dispose);

  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: const AdminApp(),
  ));
  await _settle(tester);
  return container;
}

/// Fixed pumps rather than `pumpAndSettle`.
///
/// The feature pages behind the shell read an uninitialised backend and
/// land in their error states, which is fine — this is about which page
/// the router is willing to show, not what it manages to load. But those
/// states sit next to indeterminate progress indicators that never
/// settle, so `pumpAndSettle` would time out rather than assert.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

String _location(ProviderContainer container) => container
    .read(adminRouterProvider)
    .routerDelegate
    .currentConfiguration
    .uri
    .path;

void main() {
  testWidgets('a moderator typing a super-admin path is refused, not served',
      (tester) async {
    final container = await _pumpConsole(tester, AdminRoleEnum.moderator);
    expect(_location(container), AdminRoutePaths.dashboard,
        reason: 'a signed-in admin lands on the dashboard');

    // Direct navigation, through the platform route channel the browser
    // address bar actually pushes — not the sidebar, which no longer
    // offers the link. Every read behind that page is
    // `@Roles('super_admin')`.
    final router = container.read(adminRouterProvider);
    await router.routeInformationProvider.didPushRouteInformation(
      RouteInformation(uri: Uri.parse(AdminRoutePaths.questManagement)),
    );
    await _settle(tester);

    expect(_location(container), AdminRoutePaths.dashboard,
        reason: 'a typed URL must be refused, not just unlinked');
    expect(find.byType(QuestManagementPage), findsNothing,
        reason: 'the page must never build, so its reads never fire');

    // And the same refusal for an in-app navigation, which is the other
    // way a stale link or a bookmark gets there.
    router.go(AdminRoutePaths.questManagement);
    await _settle(tester);
    expect(_location(container), AdminRoutePaths.dashboard);
    expect(find.byType(QuestManagementPage), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a moderator is not shown super-admin destinations',
      (tester) async {
    await _pumpConsole(tester, AdminRoleEnum.moderator);

    // Hidden: the five whose endpoints are super-admin only.
    expect(find.text('QUESTS'), findsNothing);
    expect(find.text('DESTINATIONS'), findsNothing);
    expect(find.text('XP'), findsNothing);
    expect(find.text('SETTINGS'), findsNothing);
    expect(find.text('INJECTION'), findsNothing);

    // Still there: the work a moderator is employed to do.
    expect(find.text('MODERATION'), findsOneWidget);
    expect(find.text('APPEALS'), findsOneWidget);
    expect(find.text('REPORTS'), findsOneWidget);
  });

  testWidgets('a super admin keeps every destination and reaches them',
      (tester) async {
    final container = await _pumpConsole(tester, AdminRoleEnum.superAdmin);

    expect(find.text('QUESTS'), findsOneWidget);
    expect(find.text('SETTINGS'), findsOneWidget);

    container.read(adminRouterProvider).go(AdminRoutePaths.questManagement);
    await _settle(tester);
    expect(_location(container), AdminRoutePaths.questManagement);
    expect(find.byType(QuestManagementPage), findsOneWidget);
  });

  group('AdminRouteAccess mirrors the backend @Roles decorators', () {
    test('super-admin-only paths are closed to a moderator', () {
      for (final path in AdminRouteAccess.superAdminOnly) {
        expect(AdminRouteAccess.allows(path, AdminRoleEnum.moderator), isFalse,
            reason: '$path is @Roles(\'super_admin\') on the API');
        expect(AdminRouteAccess.allows(path, AdminRoleEnum.superAdmin), isTrue);
      }
    });

    test('a nested path under a gated one is gated too', () {
      // Prefix-matched on a segment boundary: a child of /quests is
      // gated, a sibling path that merely starts with the same letters
      // is not.
      expect(AdminRouteAccess.requiresSuperAdmin('/quests/abc'), isTrue);
      expect(AdminRouteAccess.requiresSuperAdmin('/quests-archive'), isFalse);
    });

    test('the moderator-and-super-admin endpoints stay open to both', () {
      const shared = [
        AdminRoutePaths.dashboard,
        AdminRoutePaths.pendingSubmissions,
        AdminRoutePaths.submissionHistory,
        AdminRoutePaths.appeals,
        AdminRoutePaths.reports,
        AdminRoutePaths.feedManagement,
        AdminRoutePaths.questOfTheDay,
        AdminRoutePaths.users,
        AdminRoutePaths.announcements,
        AdminRoutePaths.autoNotifications,
        AdminRoutePaths.webSignups,
        AdminRoutePaths.webQuestSuggestions,
      ];
      for (final path in shared) {
        expect(AdminRouteAccess.allows(path, AdminRoleEnum.moderator), isTrue,
            reason: '$path is @Roles(\'moderator\', \'super_admin\')');
      }
    });

    test('no role at all is allowed nothing', () {
      expect(AdminRouteAccess.allows(AdminRoutePaths.dashboard, null), isFalse);
      expect(AdminRouteAccess.allows(AdminRoutePaths.questManagement, null),
          isFalse);
    });
  });
}
