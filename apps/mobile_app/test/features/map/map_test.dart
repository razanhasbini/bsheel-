import 'dart:convert';
import 'dart:io';
import 'package:app_core/app_core.dart';
import 'package:app_models/app_models.dart';
import 'package:app_repositories/app_repositories.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/core/providers/auth_session_provider.dart';
import 'package:mobile_app/features/map/data/live_location_provider.dart';
import 'package:mobile_app/features/map/data/map_providers.dart';
import 'package:mobile_app/features/map/domain/map_geometry.dart';
import 'package:mobile_app/features/map/presentation/map_page.dart';
import 'package:mobile_app/features/auth/presentation/widgets/auth_field.dart';

class _MapRepo extends Fake implements MapRepository {
  bool saved = false;
  @override
  Future<List<MapCountry>> countries({String? userId}) async => [
        const MapCountry(
            code: 'LB',
            name: 'Lebanon',
            geometryId: '422',
            total: 2,
            discovered: 0,
            confirmed: 0,
            saved: 0)
      ];
  @override
  Future<List<MapPlace>> places(
          {String? country,
          String? category,
          String search = '',
          int offset = 0,
          bool savedOnly = false}) async =>
      category == 'hidden' ||
              (search.isNotEmpty &&
                  !'Test landmark'.toLowerCase().contains(search.toLowerCase()))
          ? []
          : [
              MapPlace(
                  id: 'place',
                  countryCode: 'LB',
                  name: 'Test landmark',
                  description: 'Fixture description',
                  city: 'Test',
                  category: 'landmark',
                  latitude: 33.9,
                  longitude: 35.5,
                  saved: saved)
            ];
  @override
  Future<MapPlaceDetail> detail(String id) async => const MapPlaceDetail(
      place: MapPlace(
          id: 'place',
          countryCode: 'LB',
          name: 'Test landmark',
          description: 'Fixture description',
          city: 'Test',
          category: 'landmark',
          latitude: 33.9,
          longitude: 35.5),
      quests: [],
      previews: []);

  /// Two moments at the one fixture place — the case the scatter exists
  /// for, since both carry that place's coordinate.
  @override
  Future<List<MapMoment>> moments({String? country, int limit = 60}) async => [
        MapMoment(
            id: 'moment-photo',
            mediaUrl: 'https://example.test/photo.png',
            mediaType: 'image',
            submittedAt: DateTime(2026, 9, 1),
            netScore: 3,
            caption: '',
            questId: 'quest',
            questTitle: 'Fixture quest',
            questCategory: 'adventure',
            placeId: 'place',
            placeName: 'Test landmark',
            city: 'Test',
            countryCode: 'LB',
            latitude: 33.9,
            longitude: 35.5,
            radiusM: 250,
            userId: 'u1',
            username: 'layla',
            moreCount: 4,
            questCount: 2),
        MapMoment(
            id: 'moment-video',
            mediaUrl: 'https://example.test/clip.mp4',
            mediaType: 'video',
            submittedAt: DateTime(2026, 9, 2),
            netScore: 8,
            caption: '',
            questId: 'quest',
            questTitle: 'Fixture quest',
            questCategory: 'creativity',
            placeId: 'place',
            placeName: 'Test landmark',
            city: 'Test',
            countryCode: 'LB',
            latitude: 33.9,
            longitude: 35.5,
            radiusM: 250,
            userId: 'u2',
            username: 'omar',
            questCount: 1),
      ];

  @override
  Future<void> save(String id, bool value) async {
    saved = value;
  }
}

void main() {
  late List<CountryGeometry> geometry;
  setUpAll(() {
    geometry = CountryGeometry.decode(
        jsonDecode(File('assets/map/countries-50m.json').readAsStringSync())
            as Map<String, dynamic>);
  });
  test(
      'real geometry includes Lebanon and Qatar and shares bounded pin projection',
      () {
    expect(geometry.length, greaterThan(170));
    final lebanon = geometry.firstWhere((g) => g.id == '422');
    expect(lebanon.name, 'Lebanon');
    expect(geometry.any((g) => g.id == '634'), isTrue);
    final projection = MapProjection([lebanon], const Size(350, 400));
    final pin = projection.project(const Offset(35.5, 33.9));
    expect(pin.dx, inInclusiveRange(0, 350));
    expect(pin.dy, inInclusiveRange(0, 400));
    expect(projection.path(lebanon).getBounds().width, greaterThan(10));
  });
  testWidgets(
      'password reveal is visible, reversible and keeps the entered value',
      (tester) async {
    final controller = TextEditingController(text: 'Secret-Example-9');
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
        theme: QuestTheme.light,
        home: Scaffold(
            body: AuthField(
                label: 'Password',
                controller: controller,
                obscureText: true))));
    expect(
        tester.widget<TextField>(find.byType(TextField)).obscureText, isTrue);
    await tester.tap(find.byTooltip('Show password'));
    await tester.pump();
    expect(
        tester.widget<TextField>(find.byType(TextField)).obscureText, isFalse);
    expect(controller.text, 'Secret-Example-9');
    await tester.tap(find.byTooltip('Hide password'));
    await tester.pump();
    expect(
        tester.widget<TextField>(find.byType(TextField)).obscureText, isTrue);
  });
  testWidgets('map renders at phone width, opens a place and persists save',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = _MapRepo();
    await tester.pumpWidget(ProviderScope(overrides: [
      authSessionProvider.overrideWith((ref) => null),
      mapRepositoryProvider.overrideWithValue(repo),
      mapGeometryProvider.overrideWith((ref) async => geometry),
      // No tile fetches and no GPS plugin under test: the fog, pins and
      // sheets are what this exercises.
      mapTilesEnabledProvider.overrideWithValue(false),
      liveLocationProvider.overrideWith((ref) =>
          Stream.value(const LiveLocation(LiveLocationStatus.unavailable))),
    ], child: MaterialApp(theme: QuestTheme.light, home: const MapPage())));
    await tester.pumpAndSettle();
    expect(find.text('EXPLORE'), findsOneWidget);
    expect(tester.takeException(), isNull);
    // The world view shows one badge per country, not pins. With no GPS fix
    // the intro timer flies the camera to Lebanon's places, after which the
    // pins are on screen.
    expect(find.bySemanticsLabel(RegExp(r'^Lebanon, ')), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 2300));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Test landmark'));
    await tester.pumpAndSettle();
    expect(find.text('Fixture description'), findsOneWidget);
    await tester.tap(find.text('SAVE FOR LATER'));
    await tester.pumpAndSettle();
    expect(repo.saved, isTrue);
    expect(find.text('SAVED'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('progress uses real zero and separates confirmed from pending',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: DiscoveryProgress(countries: [
      MapCountry(
          code: 'LB',
          name: 'Lebanon',
          geometryId: '422',
          total: 10,
          discovered: 3,
          confirmed: 2,
          saved: 5)
    ]))));
    // Exploration counts approved proof only: 2 of 10 places, not 3.
    expect(find.text('LEBANON · 20%'), findsOneWidget);
    expect(find.text('2 confirmed · 1 awaiting review'), findsOneWidget);
  });

  test('moments at one place scatter, stably and inside the radius', () {
    MapMoment at(String id, {int radiusM = 250}) => MapMoment(
        id: id,
        mediaUrl: '',
        mediaType: 'image',
        submittedAt: DateTime(2026, 9, 1),
        netScore: 0,
        caption: '',
        questId: 'q',
        questTitle: 't',
        questCategory: 'adventure',
        placeId: 'place',
        placeName: 'Test landmark',
        city: '',
        countryCode: 'LB',
        latitude: 33.9,
        longitude: 35.5,
        radiusM: radiusM,
        userId: 'u',
        username: 'u');

    final first = at('moment-a').scatterOffset;
    final second = at('moment-b').scatterOffset;

    // Stable: the same id must land in the same spot every time, or a tile
    // would appear to move between frames — which would read as the person
    // moving.
    expect(at('moment-a').scatterOffset, first);

    // Distinct: two moments at one place must not stack into one square.
    final apart =
        (first.east - second.east).abs() + (first.north - second.north).abs();
    expect(apart, greaterThan(1));

    // Bounded: never outside the place, and never further than 120 m however
    // large the geofence is. The offset is presentation, not a claim about
    // where anybody stood.
    for (final moment in ['a', 'b', 'c', 'd', 'e', 'f'].map(at)) {
      final offset = moment.scatterOffset;
      final distance =
          (offset.east * offset.east + offset.north * offset.north);
      expect(distance, lessThanOrEqualTo(175.0 * 175.0));
      expect(distance, greaterThan(0));
    }
    final wide = at('moment-a', radiusM: 10000).scatterOffset;
    expect(wide.east.abs(), lessThanOrEqualTo(120));
    expect(wide.north.abs(), lessThanOrEqualTo(120));
  });

  testWidgets('moments draw over the map and can be hidden', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ProviderScope(overrides: [
      authSessionProvider.overrideWith((ref) => null),
      mapRepositoryProvider.overrideWithValue(_MapRepo()),
      mapGeometryProvider.overrideWith((ref) async => geometry),
      mapTilesEnabledProvider.overrideWithValue(false),
      liveLocationProvider.overrideWith((ref) =>
          Stream.value(const LiveLocation(LiveLocationStatus.unavailable))),
    ], child: MaterialApp(theme: QuestTheme.light, home: const MapPage())));
    await tester.pumpAndSettle();
    // Zoomed out, the board is badges and nothing else: at world zoom every
    // tile would land on the same pixel.
    expect(find.bySemanticsLabel(RegExp('proof by')), findsNothing);

    await tester.pump(const Duration(milliseconds: 2300));
    await tester.pumpAndSettle();

    // Both moments, labelled by medium and author rather than as anonymous
    // squares — and carrying what the card shows: how much else stands at
    // the place, and that there is something here to DO.
    // Asserted on the Semantics widgets rather than through
    // `find.bySemanticsLabel`: each card is wrapped in a Tooltip, whose
    // message merges into the same semantics node, so an exact-string match
    // against the node can never succeed. Reading the widget's own label is
    // both what we mean and what survives that merge.
    List<String?> cardLabels() => tester
        .widgetList<Semantics>(find.byType(Semantics))
        .map((w) => w.properties.label)
        .where((l) => l != null && l.contains('proof by'))
        .toList();

    final labels = cardLabels();
    expect(
        labels,
        containsAll([
          // What the card carries: medium, author, place, how much else
          // stands here, and that there is something to DO.
          'Photo proof by layla, at Test landmark, and 4 more, 2 quests here',
          'Video proof by omar, at Test landmark, 1 quest here',
        ]),
        reason: 'labels on screen: $labels');
    // The "+N more" summary is drawn, not the four extra cards.
    expect(find.text('+4 more'), findsOneWidget);
    // The quest pin is still there — moments are an addition to the board,
    // never a replacement for the thing that starts a quest.
    expect(find.byTooltip('Test landmark'), findsOneWidget);

    await tester.tap(find.byTooltip('Hide quest moments'));
    await tester.pumpAndSettle();
    expect(cardLabels(), isEmpty);
    expect(find.byTooltip('Test landmark'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
