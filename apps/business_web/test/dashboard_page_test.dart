import 'package:app_core/app_core.dart' show QuestTheme;
import 'package:app_models/app_models.dart';
import 'package:app_repositories/app_repositories.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:business_web/core/providers/analytics_providers.dart';
import 'package:business_web/core/providers/session_providers.dart';
import 'package:business_web/features/dashboard/dashboard_page.dart';

/// The dashboard's job is to be read correctly, so these tests are mostly
/// about the sentences around the numbers rather than the numbers.
void main() {
  BusinessSummary summary({
    BusinessStatus status = BusinessStatus.active,
    bool subscribed = true,
  }) =>
      BusinessSummary(
        id: 'b1',
        name: 'Tawlet Beirut',
        slug: 'tawlet-beirut',
        status: status,
        membershipRole: BusinessMemberRole.owner,
        analyticsSubscribed: subscribed,
      );

  BusinessAnalyticsSummary stats({
    int completions = 12,
    int visitors = 9,
    DateTime? firstActivity,
  }) =>
      BusinessAnalyticsSummary(
        places: 1,
        completions: completions,
        visitors: visitors,
        awaitingReview: 2,
        rejected: 1,
        saves: 30,
        publicProof: 4,
        xpAwarded: 120,
        minReportableCohort: 5,
        firstActivityAt: firstActivity ?? DateTime(2026, 9, 1),
        lastActivityAt: DateTime(2026, 9, 10),
      );

  /// A tall viewport, because the page is one long scroll and `ListView`
  /// only builds what is on screen — the origins and quest sections are
  /// below the fold at the default 800x600 and would never mount.
  void useTallSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(1400, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> pump(
    WidgetTester tester, {
    required BusinessSummary business,
    BusinessAnalyticsSummary? analytics,
    List<BusinessQuestPerformance> quests = const [],
    BusinessVisitorOrigins? origins,
  }) async {
    useTallSurface(tester);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionProvider.overrideWith((ref) => const AuthUser(id: 'u1')),
          businessRepositoryProvider
              .overrideWithValue(_FakeRepository([business])),
          analyticsSummaryProvider
              .overrideWith((ref, arg) async => analytics ?? stats()),
          dailyProvider.overrideWith((ref, arg) async => const []),
          questPerformanceProvider.overrideWith((ref, arg) async => quests),
          placePerformanceProvider.overrideWith((ref, arg) async => const []),
          visitorOriginsProvider.overrideWith((ref, arg) async =>
              origins ??
              const BusinessVisitorOrigins(
                  visitors: 0,
                  disclosed: 0,
                  undisclosed: 0,
                  countries: [],
                  suppressedCountries: 0,
                  suppressedVisitors: 0)),
          publicProofProvider.overrideWith(
              (ref, arg) async => const BusinessProofPage(items: [])),
        ],
        child: MaterialApp(
          theme: QuestTheme.light,
          home: const DashboardPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  // A suspended or unsubscribed account has every analytics route refused,
  // so rendering the sections would show six failures in a row and leave an
  // owner guessing which of two causes it was.
  testWidgets('explains a suspension instead of failing six sections',
      (tester) async {
    await pump(tester, business: summary(status: BusinessStatus.suspended));

    expect(find.textContaining('suspended'), findsWidgets);
    expect(find.textContaining('claimed places are kept'), findsOneWidget);
    expect(find.text('IMPACT'), findsNothing);
  });

  testWidgets('explains an unsubscribed account', (tester) async {
    await pump(tester, business: summary(subscribed: false));

    expect(find.textContaining('not part of this account yet'), findsOneWidget);
    expect(find.text('IMPACT'), findsNothing);
  });

  testWidgets('shows the sections for a live account', (tester) async {
    await pump(tester, business: summary());

    expect(find.text('IMPACT'), findsOneWidget);
    expect(find.text('Tawlet Beirut'), findsOneWidget);
  });

  // "Nothing has happened yet" and "zero this period" read completely
  // differently to somebody who has just claimed a place.
  testWidgets('distinguishes never-any-activity from a quiet period',
      (tester) async {
    await pump(
      tester,
      business: summary(),
      analytics: BusinessAnalyticsSummary(
        places: 1,
        completions: 0,
        visitors: 0,
        awaitingReview: 0,
        rejected: 0,
        saves: 0,
        publicProof: 0,
        xpAwarded: 0,
        minReportableCohort: 5,
        firstActivityAt: null,
        lastActivityAt: null,
      ),
    );

    expect(find.textContaining('Nothing has happened at your places yet'),
        findsOneWidget);
  });

  // A quest nobody has started has no rate. Printing 0% would rank it as
  // the worst performer and read as advice to change something untried.
  testWidgets('renders no completion rate as a dash, not zero per cent',
      (tester) async {
    await pump(
      tester,
      business: summary(),
      quests: const [
        BusinessQuestPerformance(
          questId: 'q1',
          title: 'Fold your first manoushe',
          placeName: 'Mar Mikhael',
          starts: 0,
          completions: 0,
          awaitingReview: 0,
          cohortSuppressed: false,
          completionRate: null,
        ),
      ],
    );

    expect(find.text('—'), findsOneWidget);
    expect(find.text('0%'), findsNothing);
  });

  /// The honest empty state. With nobody disclosing a country, "no data"
  /// would read as "nobody came" — the opposite of true.
  testWidgets('says nobody disclosed a country rather than nobody came',
      (tester) async {
    await pump(
      tester,
      business: summary(),
      origins: const BusinessVisitorOrigins(
        visitors: 40,
        disclosed: 0,
        undisclosed: 40,
        countries: [],
        suppressedCountries: 0,
        suppressedVisitors: 0,
      ),
    );

    expect(find.textContaining('None of your 40 visitors have shared'),
        findsOneWidget);
  });

  /// The denominator has to be on screen. A share of the disclosed
  /// population is not a share of the visitors, and reading one as the
  /// other turns an eighth of the traffic into all of it.
  testWidgets('states how many visitors the country split is based on',
      (tester) async {
    await pump(
      tester,
      business: summary(),
      origins: const BusinessVisitorOrigins(
        visitors: 40,
        disclosed: 5,
        undisclosed: 35,
        countries: [
          BusinessOriginBucket(
              countryCode: 'LB', visitors: 5, shareOfDisclosed: 1),
        ],
        suppressedCountries: 0,
        suppressedVisitors: 0,
      ),
    );

    expect(find.textContaining('Based on 5 of 40 visitors'), findsOneWidget);
    expect(find.textContaining('35 have not shared a country'), findsOneWidget);
  });

  testWidgets('accounts for countries too small to name', (tester) async {
    await pump(
      tester,
      business: summary(),
      origins: const BusinessVisitorOrigins(
        visitors: 12,
        disclosed: 8,
        undisclosed: 4,
        countries: [
          BusinessOriginBucket(
              countryCode: 'LB', visitors: 6, shareOfDisclosed: 0.75),
        ],
        suppressedCountries: 2,
        suppressedVisitors: 2,
      ),
    );

    expect(find.textContaining('2 more countries'), findsOneWidget);
    expect(find.textContaining('too few people to name'), findsOneWidget);
  });
}

class _FakeRepository implements BusinessRepository {
  _FakeRepository(this._businesses);

  final List<BusinessSummary> _businesses;

  @override
  Future<List<BusinessSummary>> mine() async => _businesses;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
      '${invocation.memberName} is not used by this test');
}
