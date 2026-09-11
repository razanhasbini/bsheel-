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
}
