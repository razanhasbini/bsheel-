import 'package:app_core/app_core.dart' show QuestTheme;
import 'package:app_models/app_models.dart';
import 'package:app_repositories/app_repositories.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/core/providers/auth_session_provider.dart';
import 'package:mobile_app/core/providers/business_provider.dart';
import 'package:mobile_app/features/profile/presentation/widgets/business_card.dart';

/// #14's business card — the only thing being a business changes in the
/// consumer app.
///
/// Four states matter, and each has a different fix that only the owner can
/// act on, which is why they are separate messages rather than one disabled
/// button: suspended, not subscribed, no dashboard URL in this build, and
/// ready. A fifth case is the important one — not a business at all — where
/// the card must contribute nothing whatsoever to the profile.
void main() {
  BusinessSummary business({
    BusinessStatus status = BusinessStatus.active,
    BusinessMemberRole role = BusinessMemberRole.owner,
    bool subscribed = true,
    List<BusinessPlace> places = const [],
  }) =>
      BusinessSummary(
        id: 'b1',
        name: 'Tawlet Beirut',
        slug: 'tawlet-beirut',
        status: status,
        membershipRole: role,
        analyticsSubscribed: subscribed,
        places: places,
      );

  BusinessPlace place({bool published = true}) => BusinessPlace(
        placeId: 'p1',
        name: 'Mar Mikhael',
        city: 'Beirut',
        countryCode: 'LB',
        category: 'landmark',
        isPublished: published,
      );

  Future<void> pump(
    WidgetTester tester, {
    required AsyncValue<List<BusinessSummary>> value,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          myBusinessesProvider
              .overrideWith((ref) async => value.valueOrNull ?? []),
        ],
        child: MaterialApp(
          theme: QuestTheme.light,
          home: const Scaffold(
            body: SingleChildScrollView(child: BusinessCard()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('contributes nothing for a user who is not a business',
      (tester) async {
    await pump(tester, value: const AsyncValue.data([]));

    // Not merely "no card" — no text, no pill, nothing that could push the
    // rest of the profile down for the overwhelming majority of users.
    expect(find.byType(Text), findsNothing);
    expect(tester.getSize(find.byType(BusinessCard)).height, 0);
  });

  testWidgets('names the business and the role for a member', (tester) async {
    await pump(
      tester,
      value: AsyncValue.data([
        business(places: [place()])
      ]),
    );

    expect(find.text('Tawlet Beirut'), findsOneWidget);
    expect(find.text('BUSINESS OWNER'), findsOneWidget);
    expect(find.text('1 place on the map'), findsOneWidget);
  });

  testWidgets('distinguishes a manager from an owner', (tester) async {
    await pump(
      tester,
      value: AsyncValue.data([business(role: BusinessMemberRole.manager)]),
    );

    expect(find.text('BUSINESS MANAGER'), findsOneWidget);
    expect(find.text('BUSINESS OWNER'), findsNothing);
  });

  // An unpublished place reports no activity at all. Saying so stops that
  // reading as a broken dashboard rather than a place that is not live yet.
  testWidgets('says when a claimed place is not published', (tester) async {
    await pump(
      tester,
      value: AsyncValue.data([
        business(places: [place(), place(published: false)]),
      ]),
    );

    expect(find.text('2 places · 1 not published yet'), findsOneWidget);
  });

  testWidgets('distinguishes no places claimed from no activity',
      (tester) async {
    await pump(tester, value: AsyncValue.data([business()]));

    expect(find.text('No places claimed yet'), findsOneWidget);
  });

  // The two refusals a member can actually be told apart. Collapsing them
  // into one disabled button would leave an owner unable to tell whether to
  // call Bsheel about a subscription or about a suspension.
  testWidgets('explains a suspension rather than offering a dead button',
      (tester) async {
    await pump(
      tester,
      value: AsyncValue.data([business(status: BusinessStatus.suspended)]),
    );

    expect(find.text('SUSPENDED'), findsOneWidget);
    expect(find.textContaining('suspended'), findsWidgets);
    expect(find.textContaining('claimed places are kept'), findsOneWidget);
    expect(find.text('OPEN DASHBOARD'), findsNothing);
  });

  testWidgets('explains an unsubscribed account', (tester) async {
    await pump(tester, value: AsyncValue.data([business(subscribed: false)]));

    expect(find.textContaining('not part of this account yet'), findsOneWidget);
    expect(find.text('OPEN DASHBOARD'), findsNothing);
    // Not the same message as a suspension: different cause, different fix.
    expect(find.text('SUSPENDED'), findsNothing);
  });

  // Suspension outranks the subscription: a suspended account reads nothing
  // whether or not it is paid up, and telling an owner to buy analytics they
  // already have would be actively wrong.
  testWidgets('reports the suspension when both apply', (tester) async {
    await pump(
      tester,
      value: AsyncValue.data([
        business(status: BusinessStatus.suspended, subscribed: false),
      ]),
    );

    expect(find.textContaining('claimed places are kept'), findsOneWidget);
    expect(find.textContaining('not part of this account yet'), findsNothing);
  });

  // Tests run without DASHBOARD_URL, so this is the "build was not told
  // where the dashboard lives" path — and it must say so rather than show a
  // button that goes nowhere.
  testWidgets('offers no link when the build has no dashboard URL',
      (tester) async {
    await pump(tester, value: AsyncValue.data([business()]));

    expect(find.textContaining('was not told where the dashboard lives'),
        findsOneWidget);
    expect(find.text('OPEN DASHBOARD'), findsNothing);
  });

  testWidgets('lists every business a member belongs to', (tester) async {
    await pump(
      tester,
      value: AsyncValue.data([
        business(),
        const BusinessSummary(
          id: 'b2',
          name: 'Second Location',
          slug: 'second-location',
          status: BusinessStatus.active,
          membershipRole: BusinessMemberRole.manager,
          analyticsSubscribed: true,
        ),
      ]),
    );

    expect(find.text('Tawlet Beirut'), findsOneWidget);
    expect(find.text('Second Location'), findsOneWidget);
  });

  /// A network blip on this call must not take the profile down with it: the
  /// card is an addition to someone's page, not the page.
  ///
  /// Overrides the *repository*, not `myBusinessesProvider`, so the real
  /// provider runs and its own error handling is what gets tested. An
  /// override that threw in the provider's place would only prove that
  /// Riverpod propagates errors.
  testWidgets('stays invisible while loading and after a failure',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authSessionProvider.overrideWith(
              (ref) => const AuthUser(id: 'u1', email: 'owner@example.com')),
          businessRepositoryProvider
              .overrideWithValue(_OfflineBusinessRepository()),
        ],
        child: MaterialApp(
          theme: QuestTheme.light,
          home: const Scaffold(body: BusinessCard()),
        ),
      ),
    );
    // Loading frame: nothing rendered yet.
    expect(find.byType(Text), findsNothing);
    await tester.pumpAndSettle();
    // Failed frame: still nothing, and no error widget either.
    expect(find.byType(Text), findsNothing);
    expect(tester.takeException(), isNull);
  });

  // Signed out, the card must not serve a business from the previous
  // session, and must not call the API at all.
  testWidgets('asks for nothing while signed out', (tester) async {
    final repository = _CountingBusinessRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authSessionProvider.overrideWith((ref) => null),
          businessRepositoryProvider.overrideWithValue(repository),
        ],
        child: MaterialApp(
          theme: QuestTheme.light,
          home: const Scaffold(body: BusinessCard()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(repository.calls, 0);
    expect(find.byType(Text), findsNothing);
  });
}

/// Fails every call, standing in for a device that has lost its connection.
class _OfflineBusinessRepository implements BusinessRepository {
  @override
  Future<List<BusinessSummary>> mine() async => throw Exception('offline');

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
      '${invocation.memberName} is not used by this test');
}

/// Records whether the card reached the API at all.
class _CountingBusinessRepository implements BusinessRepository {
  int calls = 0;

  @override
  Future<List<BusinessSummary>> mine() async {
    calls += 1;
    return const [];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
      '${invocation.memberName} is not used by this test');
}
