import 'package:app_core/app_core.dart' show QuestTheme;
import 'package:app_models/app_models.dart';
import 'package:app_repositories/app_repositories.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
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
    List<BusinessPlacePerformance> places = const [],
    BusinessDailySeries? series,
    BusinessFunnel? funnel,
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
          dailyProvider.overrideWith((ref, arg) async =>
              series ??
              const BusinessDailySeries(
                  from: '2026-09-01', to: '2026-09-07', points: [])),
          questPerformanceProvider.overrideWith((ref, arg) async => quests),
          placePerformanceProvider.overrideWith((ref, arg) async => places),
          funnelProvider.overrideWith((ref, arg) async =>
              funnel ??
              const BusinessFunnel(
                from: '2026-09-01',
                to: '2026-09-07',
                participation: BusinessParticipation(
                    activations: 0, completions: 0, visitors: 0),
              )),
          visitorOriginsProvider.overrideWith((ref, arg) async =>
              origins ??
              const BusinessVisitorOrigins(
                  visitors: 0,
                  disclosed: 0,
                  undisclosed: 0,
                  countries: [],
                  suppressedCountries: 0,
                  suppressedVisitors: 0)),
          // Proof is a StateNotifier now; the fake repository below answers
          // its read, so no provider override is needed for it.
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

  BusinessPlacePerformance placeRow(String name,
          {int completions = 0, bool published = true}) =>
      BusinessPlacePerformance(
        placeId: 'p-$name',
        name: name,
        city: 'Beirut',
        countryCode: 'LB',
        quests: 1,
        starts: 1,
        completions: completions,
        visitors: completions,
        saves: 0,
        isPublished: published,
        cohortSuppressed: false,
      );

  group('the places section', () {
    // Controls on a list of three are furniture; finding one of three is
    // not work.
    testWidgets('offers no filter for a handful of places', (tester) async {
      await pump(tester, business: summary(), places: [
        placeRow('Mar Mikhael'),
        placeRow('Gemmayze'),
      ]);

      expect(find.text('Mar Mikhael'), findsOneWidget);
      expect(
          find.widgetWithText(
              ArcadeTextField, 'Filter by place, city or country'),
          findsNothing);
    });

    testWidgets('filters once there are enough places to search',
        (tester) async {
      await pump(tester, business: summary(), places: [
        placeRow('Mar Mikhael'),
        placeRow('Gemmayze'),
        placeRow('Hamra'),
        placeRow('Badaro'),
      ]);

      final field = find.byType(ArcadeTextField);
      expect(field, findsWidgets);
      await tester.enterText(field.first, 'hamra');
      await tester.pumpAndSettle();

      expect(find.text('Hamra'), findsOneWidget);
      expect(find.text('Mar Mikhael'), findsNothing);
    });

    testWidgets('says so when a filter matches nothing', (tester) async {
      await pump(tester, business: summary(), places: [
        placeRow('Mar Mikhael'),
        placeRow('Gemmayze'),
        placeRow('Hamra'),
        placeRow('Badaro'),
      ]);

      await tester.enterText(find.byType(ArcadeTextField).first, 'nowhere');
      await tester.pumpAndSettle();

      expect(find.textContaining('No places match'), findsOneWidget);
    });

    // An unpublished place reports nothing at all, which otherwise reads as
    // a broken dashboard rather than a place that is not live yet.
    testWidgets('flags a place that is not published', (tester) async {
      await pump(tester,
          business: summary(),
          places: [placeRow('Draft Spot', published: false)]);

      expect(find.textContaining('Not published'), findsOneWidget);
    });
  });

  /// The chart's window controls must never claim a preset while a range is
  /// being charted — a highlighted "30D" over a February chart is a lie the
  /// reader has no way to catch.
  group('the chart window', () {
    /// The dates come from the response, never recomputed here: a client
    /// deriving "today" itself disagrees by a day for anyone west of UTC,
    /// and a chart mislabelled by one day is not detectable by reading it.
    testWidgets('labels the window the server actually drew', (tester) async {
      await pump(
        tester,
        business: summary(),
        series: const BusinessDailySeries(
          from: '2026-02-01',
          to: '2026-02-03',
          points: [
            BusinessDailyPoint(date: '2026-02-01', completions: 1, visitors: 1),
            BusinessDailyPoint(date: '2026-02-02', completions: 0, visitors: 0),
            BusinessDailyPoint(date: '2026-02-03', completions: 2, visitors: 1),
          ],
        ),
      );

      expect(find.text('2026-02-01 → 2026-02-03'), findsOneWidget);
      // And the chart totals what the server sent rather than recounting.
      expect(find.text('3 completed'), findsOneWidget);
    });

    testWidgets('shows a preset as selected by default', (tester) async {
      await pump(tester, business: summary());

      expect(find.text('30D'), findsOneWidget);
      expect(find.text('DATES'), findsOneWidget);
    });
  });

  /// The funnel's whole point is that the two halves are not the same kind
  /// of number. Exposure is what a phone said it drew; participation is
  /// what the server recorded.
  group('the funnel', () {
    BusinessFunnel funnelWith({
      BusinessExposure? exposure,
      int activations = 0,
      int completions = 0,
      double? impressionToView,
      double? bsheeelToActivation,
    }) =>
        BusinessFunnel(
          from: '2026-09-01',
          to: '2026-09-07',
          exposure: exposure,
          participation: BusinessParticipation(
              activations: activations,
              completions: completions,
              visitors: completions),
          impressionToView: impressionToView,
          bsheeelToActivation: bsheeelToActivation,
        );

    /// Not zeroes. "The app has not reported any views" is a statement
    /// about Bsheel; showing 0 impressions would be a claim about the
    /// business, and a false one.
    testWidgets('says nothing was reported rather than showing zeroes',
        (tester) async {
      await pump(tester,
          business: summary(), funnel: funnelWith(completions: 3));

      expect(find.textContaining('has not reported any views'), findsOneWidget);
      expect(
          find.textContaining('not the same as nobody seeing'), findsOneWidget);
      expect(find.text('Times shown'), findsNothing);
    });

    // The label lives on the numbers. A caveat in a footnote gets quoted
    // without it.
    testWidgets('labels the reported half where the figures are',
        (tester) async {
      await pump(
        tester,
        business: summary(),
        funnel: funnelWith(
          exposure: const BusinessExposure(
              impressions: 100,
              detailViews: 40,
              bsheeels: 12,
              shares: 3,
              reach: 60),
          activations: 9,
          completions: 5,
          impressionToView: 0.4,
        ),
      );

      expect(find.text('reported by the app'), findsOneWidget);
      expect(find.text('recorded by Bsheel'), findsOneWidget);
      expect(find.text('100'), findsOneWidget);
      expect(find.text('40% of times shown'), findsOneWidget);
    });

    // Impressions counts screens; reach counts people. Conflating them
    // overstates an audience by however often it scrolled past.
    testWidgets('keeps screens and people apart', (tester) async {
      await pump(
        tester,
        business: summary(),
        funnel: funnelWith(
          exposure: const BusinessExposure(
              impressions: 100,
              detailViews: 0,
              bsheeels: 0,
              shares: 0,
              reach: 60),
        ),
      );

      expect(find.text('Screens, not people'), findsOneWidget);
      expect(find.text('60'), findsOneWidget);
    });

    /// A rate out of an unreported stage is absent, not 0% — which would
    /// read as a real conversion failure rather than a missing denominator.
    testWidgets('omits a rate whose denominator was never reported',
        (tester) async {
      await pump(tester,
          business: summary(),
          funnel: funnelWith(activations: 4, completions: 1));

      expect(find.textContaining('of BSHEEELs'), findsNothing);
      expect(find.text('0% of BSHEEELs'), findsNothing);
      // The server-authoritative half is still shown.
      expect(find.text('4'), findsWidgets);
    });
  });
}

class _FakeRepository implements BusinessRepository {
  _FakeRepository(this._businesses);

  final List<BusinessSummary> _businesses;

  @override
  Future<List<BusinessSummary>> mine() async => _businesses;

  @override
  Future<BusinessProofPage> proof(String businessId,
          {int limit = 20, BusinessProofCursor? cursor}) async =>
      const BusinessProofPage(items: []);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
      '${invocation.memberName} is not used by this test');
}
