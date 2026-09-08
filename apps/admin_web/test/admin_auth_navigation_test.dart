import 'dart:async';

import 'package:admin_web/app.dart';
import 'package:admin_web/core/providers/admin_role_provider.dart';
import 'package:admin_web/core/providers/repository_providers.dart';
import 'package:admin_web/core/router/admin_router.dart';
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

/// Stands in for the network. Counts calls so the test can assert that a
/// sign-in causes a *new* role lookup rather than reusing a cached one.
class _CountingAdmin extends Fake implements AdminRepository {
  int calls = 0;

  @override
  Future<AdminRoleEnum?> getCurrentUserRole() async {
    calls += 1;
    return AdminRoleEnum.superAdmin;
  }
}

/// A repository whose identity changes, so a sign-in can be simulated
/// against the real `authUserIdProvider` → `adminRoleEnumProvider` chain
/// rather than by overriding the answer.
class _SigningInAuth extends Fake implements AuthRepository {
  final _changes = StreamController<AuthState>.broadcast();
  AuthUser? _user;

  @override
  AuthUser? get currentUser => _user;

  @override
  Stream<AuthState> get authStateChanges => _changes.stream;

  void signIn(AuthUser user) {
    _user = user;
    _changes.add(AuthState(
      AuthChangeEvent.signedIn,
      AuthSession(accessToken: 'token', user: user),
    ));
  }

  void dispose() => _changes.close();
}

void main() {
  testWidgets('signed-out visitor sees login and protected routes redirect',
      (tester) async {
    final container = ProviderContainer(overrides: [
      authRepositoryProvider.overrideWithValue(_Auth(null)),
      isAdminUserProvider.overrideWith((ref) async => false),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container, child: const AdminApp()));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNWidgets(2));
    container.read(adminRouterProvider).go('/dashboard');
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('pending role then denied role never creates a redirect loop',
      (tester) async {
    final role = Completer<bool>();
    final container = ProviderContainer(overrides: [
      authRepositoryProvider
          .overrideWithValue(_Auth(const AuthUser(id: 'viewer'))),
      isAdminUserProvider.overrideWith((ref) => role.future),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container, child: const AdminApp()));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(tester.takeException(), isNull);
    role.complete(false);
    await tester.pumpAndSettle();
    expect(find.text('SIGN OUT'), findsOneWidget);
    expect(find.textContaining('redirect'), findsNothing);
    container.read(adminRouterProvider).go('/dashboard');
    await tester.pumpAndSettle();
    expect(find.text('SIGN OUT'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('role resolution re-runs when the signed-in identity changes', () async {
    // The root cause of the login hang, isolated.
    //
    // The role was resolved once, at startup, while still signed out:
    // `GET admin/me` answered 401, the FutureProvider cached that failure,
    // and nothing invalidated it on sign-in. The router's redirect then read
    // `valueOrNull == null` forever and bounced every authenticated route
    // back to /login — so a correct login (HTTP 200, tokens stored) left the
    // user on the login page with no error to explain it.
    //
    // This overrides only the *network boundary* (`adminRepositoryProvider`)
    // and the auth repository. `adminRoleEnumProvider` itself is the real
    // one, because it is the thing under test. An earlier version of this
    // test overrode `adminRoleEnumProvider` with a copy that watched
    // identity — and therefore passed against the broken code, proving
    // nothing but its own override.
    final auth = _SigningInAuth();
    addTearDown(auth.dispose);
    final admin = _CountingAdmin();

    final container = ProviderContainer(overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      adminRepositoryProvider.overrideWithValue(admin),
    ]);
    addTearDown(container.dispose);

    // A listener keeps the provider subscribed, so it rebuilds when its
    // dependency changes instead of being read once and dropped.
    container.listen(adminRoleEnumProvider, (_, __) {});

    // Signed out: no identity, so no role — and crucially no network call,
    // because asking "am I an admin?" with no session is what produced the
    // cached 401 in the first place.
    expect(await container.read(adminRoleEnumProvider.future), isNull,
        reason: 'signed out, so there is no admin role to resolve');
    expect(admin.calls, 0,
        reason: 'the role must not be fetched before there is a session');

    auth.signIn(const AuthUser(id: 'boss'));
    await container.read(authUserIdProvider.future);
    await Future<void>.delayed(Duration.zero);

    // The identity changed, so the role is resolved for the new session
    // rather than served from the signed-out result.
    expect(await container.read(adminRoleEnumProvider.future),
        AdminRoleEnum.superAdmin);
    expect(admin.calls, 1,
        reason: 'signing in must trigger exactly one fresh role lookup');
  });
}
