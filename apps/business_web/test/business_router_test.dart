import 'dart:async';

import 'package:app_models/app_models.dart';
import 'package:app_repositories/app_repositories.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:business_web/core/providers/session_providers.dart';
import 'package:business_web/core/router/business_router.dart';

/// Where the router sends people.
///
/// The rule that matters: a signed-in user who is **not** a business member
/// gets an explanation, never a bounce to login. Bouncing would loop — their
/// credentials are valid, so they would sign in, be refused, and land back
/// at the form with nothing saying why.
///
/// The second rule: while the membership read is in flight, nothing is
/// decided. Treating "not resolved yet" as "not a member" would flash the
/// refusal page at every legitimate owner on every reload.
void main() {
  BusinessSummary summary() => const BusinessSummary(
        id: 'b1',
        name: 'Tawlet',
        slug: 'tawlet',
        status: BusinessStatus.active,
        membershipRole: BusinessMemberRole.owner,
        analyticsSubscribed: true,
      );

  Future<String> locationFor(
    WidgetTester tester, {
    required AuthUser? session,
    required BusinessRepository repository,
    bool settle = true,
  }) async {
    late ProviderContainer container;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionProvider.overrideWith((ref) => session),
          businessRepositoryProvider.overrideWithValue(repository),
        ],
        child: Consumer(
          builder: (context, ref, _) {
            container = ProviderScope.containerOf(context);
            return MaterialApp.router(
                routerConfig: ref.watch(businessRouterProvider));
          },
        ),
      ),
    );
    if (settle) await tester.pumpAndSettle();
    final router = container.read(businessRouterProvider);
    return router.routerDelegate.currentConfiguration.uri.path;
  }

  testWidgets('sends a signed-out visitor to login', (tester) async {
    final location = await locationFor(tester,
        session: null, repository: _Businesses(const []));

    expect(location, BusinessRoutes.login);
  });

  testWidgets('sends a member to the dashboard', (tester) async {
    final location = await locationFor(tester,
        session: const AuthUser(id: 'u1'),
        repository: _Businesses([summary()]));

    expect(location, BusinessRoutes.dashboard);
  });

  /// The loop this avoids. A valid account that simply is not a business
  /// member must be told so, not returned to a form that will accept them
  /// again and refuse them again.
  testWidgets('explains itself to a signed-in non-member', (tester) async {
    final location = await locationFor(tester,
        session: const AuthUser(id: 'u1'), repository: _Businesses(const []));

    expect(location, BusinessRoutes.notABusiness);
    expect(location, isNot(BusinessRoutes.login));
  });

  /// A failed membership read is recoverable, so it is left to the
  /// dashboard, which renders an error with a retry. Routing it to the
  /// refusal page would tell an owner they have no access because their
  /// wifi dropped.
  testWidgets('does not claim no-access when the read failed', (tester) async {
    final location = await locationFor(tester,
        session: const AuthUser(id: 'u1'), repository: _Failing());

    expect(location, isNot(BusinessRoutes.notABusiness));
    expect(location, BusinessRoutes.dashboard);
  });

  // While the read is in flight nothing is decided, so a legitimate owner
  // never sees the refusal page flash on the way in.
  testWidgets('decides nothing while the membership read is pending',
      (tester) async {
    final held = Completer<List<BusinessSummary>>();
    final location = await locationFor(
      tester,
      session: const AuthUser(id: 'u1'),
      repository: _Businesses.held(held.future),
      settle: false,
    );

    expect(location, isNot(BusinessRoutes.notABusiness));
    held.complete([summary()]);
    await tester.pumpAndSettle();
  });
}

class _Businesses implements BusinessRepository {
  _Businesses(this._rows) : _future = null;
  _Businesses.held(Future<List<BusinessSummary>> future)
      : _rows = const [],
        _future = future;

  final List<BusinessSummary> _rows;
  final Future<List<BusinessSummary>>? _future;

  @override
  Future<List<BusinessSummary>> mine() => _future ?? Future.value(_rows);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
      '${invocation.memberName} is not used by this test');
}

class _Failing implements BusinessRepository {
  @override
  Future<List<BusinessSummary>> mine() async => throw Exception('offline');

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
      '${invocation.memberName} is not used by this test');
}
