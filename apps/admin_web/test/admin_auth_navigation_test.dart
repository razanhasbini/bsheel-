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

void main() {
  testWidgets('signed-out visitor sees login and protected routes redirect', (tester) async {
    final container = ProviderContainer(overrides: [
      authRepositoryProvider.overrideWithValue(_Auth(null)),
      isAdminUserProvider.overrideWith((ref) async => false),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const AdminApp()));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNWidgets(2));
    container.read(adminRouterProvider).go('/dashboard');
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('pending role then denied role never creates a redirect loop', (tester) async {
    final role = Completer<bool>();
    final container = ProviderContainer(overrides: [
      authRepositoryProvider.overrideWithValue(_Auth(const AuthUser(id: 'viewer'))),
      isAdminUserProvider.overrideWith((ref) => role.future),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const AdminApp()));
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
}
