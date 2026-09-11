import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:app_core/app_core.dart';
import 'package:app_models/app_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../core/providers/current_profile_provider.dart';
import '../../../core/router/route_names.dart';
import '../data/live_location_provider.dart';
import '../data/map_providers.dart';
import '../domain/map_geometry.dart';

/// Natural Earth country outlines, decoded once. Still used — not to draw the
/// map any more, but to cut the fog of war along real borders.
final mapGeometryProvider = FutureProvider<List<CountryGeometry>>((ref) async =>
    CountryGeometry.decode(
        jsonDecode(await rootBundle.loadString('assets/map/countries-50m.json'))
            as Map<String, dynamic>));

/// Free tiles from OpenStreetMap. Their usage policy asks for a real
/// User-Agent (the package name below) and attribution, which the map shows;
/// heavy production traffic should move to a keyed provider.
const _osmTiles = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
const _userAgent = 'com.questapp.mobileApp';

/// An approved quest at one place uncovers the hidden places within this
/// distance — the same number the server uses to decide what is locked, so
/// the cleared circle on the map is exactly the area that is really open.
const double _revealRadiusM = 10000;

/// Where the map opens before anything is known: Beirut, the home market.
const _home = LatLng(33.8938, 35.5018);

class MapPage extends ConsumerStatefulWidget {
  const MapPage({super.key});
  @override
  ConsumerState<MapPage> createState() => _MapPageState();
}

class _MapPageState extends ConsumerState<MapPage> {
  String? _country, _category;
  String _search = '';
  bool _savedOnly = false;
  Timer? _debounce;
  final _searchController = TextEditingController();
  final _map = MapController();

  /// Snapchat-style: the camera rides along with the player until they pan.
  bool _follow = false;
  bool _fittedOnce = false;
  LatLng? _lastFix;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _map.dispose();
    super.dispose();
  }

  MapFilter get _filter => (
        country: _country,
        category: _category,
        search: _search,
        offset: 0,
        savedOnly: _savedOnly
      );

  @override
  Widget build(BuildContext context) {
    final countries = ref.watch(mapCountriesProvider);
    final geometry = ref.watch(mapGeometryProvider);
    final places = ref.watch(mapPlacesProvider(_filter));
    // The fog and the totals follow every place, whatever the filters say.
    final allPlaces = ref.watch(mapPlacesProvider(mapAllPlacesFilter));
    final live =
        ref.watch(liveLocationProvider).valueOrNull ?? LiveLocation.pending;
    final tiles = ref.watch(mapTilesEnabledProvider);
    final me = ref.watch(currentProfileProvider).valueOrNull;

    final countryRows = countries.valueOrNull ?? const <MapCountry>[];
    final rows = (places.valueOrNull ?? const <MapPlace>[])
        .where((p) => !_savedOnly || p.saved)
        .toList();
    final everyPlace = allPlaces.valueOrNull ?? const <MapPlace>[];
    final confirmedPoints = [
      for (final p in everyPlace)
        if (p.confirmed) LatLng(p.latitude, p.longitude),
    ];

    // Follow the player: move the camera on each new fix while following.
    final fix = live.point;
    if (fix != null && fix != _lastFix) {
      _lastFix = fix;
      if (_follow) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _map.move(fix, math.max(_map.camera.zoom, 14));
        });
      }
    }
    // First load: frame every pin once, so the player sees the whole board.
    if (!_fittedOnce && rows.isNotEmpty) {
      _fittedOnce = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _fitTo(rows);
      });
    }

    return Scaffold(
      backgroundColor: QuestColors.osBg,
      body: Stack(
        children: [
          Positioned.fill(
            child: FlutterMap(
              mapController: _map,
              options: MapOptions(
                initialCenter: _home,
                initialZoom: 8,
                minZoom: 2,
                maxZoom: 18,
                backgroundColor: QuestColors.osSurface,
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                ),
                onPositionChanged: (camera, hasGesture) {
                  // A pan or pinch takes the camera away from the player.
                  if (hasGesture && _follow) setState(() => _follow = false);
                },
              ),
              children: [
                if (tiles)
                  TileLayer(
                    urlTemplate: _osmTiles,
                    userAgentPackageName: _userAgent,
                    maxNativeZoom: 19,
                  ),
                // ── Fog of war ────────────────────────────────────────
                // Countries that hold quests start under ink. A confirmed
                // quest cuts a clear circle out of the fog around its place,
                // and once a country has any discovery its fog thins.
                if (geometry.hasValue && countryRows.isNotEmpty)
                  PolygonLayer(
                    polygons: _fogPolygons(
                      geometry.value!,
                      countryRows,
                      confirmedPoints,
                    ),
                  ),
                CircleLayer(
                  circles: [
                    // The cleared zone reads as a soft jade halo.
                    for (final point in confirmedPoints)
                      CircleMarker(
                        point: point,
                        radius: _revealRadiusM,
                        useRadiusInMeter: true,
                        color: QuestColors.osSuccess.withAlpha(28),
                        borderColor: QuestColors.osSuccess.withAlpha(140),
                        borderStrokeWidth: 1.5,
                      ),
                    // Each open place's geofence — the circle the network
                    // checks the player against.
                    for (final p in rows)
                      if (!p.locked)
                        CircleMarker(
                          point: LatLng(p.latitude, p.longitude),
                          radius: p.radiusM.toDouble(),
                          useRadiusInMeter: true,
                          color: QuestColors.osPrimary.withAlpha(30),
                          borderColor: QuestColors.osPrimary.withAlpha(150),
                          borderStrokeWidth: 1.5,
                        ),
                    if (fix != null && (live.accuracyM ?? 0) > 20)
                      CircleMarker(
                        point: fix,
                        radius: live.accuracyM!,
                        useRadiusInMeter: true,
                        color: QuestColors.osCool.withAlpha(35),
                        borderColor: QuestColors.osCool.withAlpha(90),
                        borderStrokeWidth: 1,
                      ),
                  ],
                ),
                MarkerLayer(
                  markers: [
                    for (final p in rows)
                      Marker(
                        point: LatLng(p.latitude, p.longitude),
                        width: 48,
                        height: 58,
                        alignment: Alignment.topCenter,
                        child: _PlacePin(place: p, onTap: () => _openPlace(p)),
                      ),
                    if (fix != null)
                      Marker(
                        point: fix,
                        width: 60,
                        height: 60,
                        child: _PlayerMarker(
                          avatarUrl: me?.avatarUrl,
                          username: me?.username ?? '',
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),

          // OSM's tile policy requires attribution on the map. Drawn here
          // rather than with flutter_map's own widget, whose row cannot
          // shrink on a narrow screen.
          if (tiles)
            Positioned(
              left: 14,
              bottom: 78,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: QuestColors.osCard.withAlpha(210),
                  borderRadius: BorderRadius.circular(QuestSpacing.radiusBadge),
                ),
                child: Text(
                  '© OpenStreetMap contributors',
                  style: QuestTypography.osLabelSmall
                      .copyWith(fontSize: 9, height: 1.2),
                ),
              ),
            ),

          // ── Header overlay ────────────────────────────────────────────
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        _Panel(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                          child: Text(
                            'EXPLORE',
                            style: QuestTypography.osDisplaySmall
                                .copyWith(fontSize: 22, height: 1),
                          ),
                        ),
                        const Spacer(),
                        _RoundButton(
                          icon: Icons.info_outline,
                          tooltip: 'Map legend',
                          onTap: () => showModalBottomSheet<void>(
                              context: context,
                              isScrollControlled: true,
                              useSafeArea: true,
                              backgroundColor: QuestColors.osBg,
                              builder: (_) => const MapLegend()),
                        ),
                        const SizedBox(width: 8),
                        _RoundButton(
                          icon: Icons.person_search_outlined,
                          tooltip: 'Search people and quests',
                          onTap: () => context.pushNamed(RouteNames.search),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _Panel(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: TextField(
                        controller: _searchController,
                        style: QuestTypography.osBodyMedium,
                        decoration: InputDecoration(
                          hintText: 'Search a place, city or country',
                          hintStyle: QuestTypography.osBodyMedium
                              .copyWith(color: QuestColors.osTextMuted),
                          prefixIcon: const Icon(Icons.search, size: 20),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding:
                              const EdgeInsets.symmetric(vertical: 12),
                        ),
                        onChanged: (value) {
                          _debounce?.cancel();
                          _debounce =
                              Timer(const Duration(milliseconds: 300), () {
                            if (mounted) setState(() => _search = value);
                          });
                        },
                      ),
                    ),
                    const SizedBox(height: 8),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _FilterChip(
                            label: 'WORLD',
                            selected: _country == null,
                            onTap: () => _setCountry(null, rows),
                          ),
                          for (final c in countryRows) ...[
                            const SizedBox(width: 6),
                            _FilterChip(
                              label: c.name.toUpperCase(),
                              selected: _country == c.code,
                              onTap: () => _setCountry(c.code, rows),
                            ),
                          ],
                          const SizedBox(width: 14),
                          for (final entry in <String?, String>{
                            null: 'ALL',
                            'landmark': 'LANDMARKS',
                            'culture': 'CULTURE',
                            'pilgrimage': 'ROUTES',
                            'heritage': 'HERITAGE',
                            'hidden': 'HIDDEN'
                          }.entries) ...[
                            _FilterChip(
                              label: entry.value,
                              selected: _category == entry.key,
                              accent: true,
                              onTap: () =>
                                  setState(() => _category = entry.key),
                            ),
                            const SizedBox(width: 6),
                          ],
                          _FilterChip(
                            label: 'SAVED PLACES',
                            selected: _savedOnly,
                            accent: true,
                            icon: Icons.bookmark,
                            onTap: () =>
                                setState(() => _savedOnly = !_savedOnly),
                          ),
                        ],
                      ),
                    ),
                    if (live.status != LiveLocationStatus.live &&
                        live.status != LiveLocationStatus.pending &&
                        live.status != LiveLocationStatus.unavailable) ...[
                      const SizedBox(height: 8),
                      _LocationBanner(status: live.status),
                    ],
                    if (places.hasError) ...[
                      const SizedBox(height: 8),
                      _Panel(
                        child: Row(children: [
                          Expanded(
                              child: Text('Places could not be loaded.',
                                  style: QuestTypography.osBodySmall)),
                          TextButton(
                              onPressed: () =>
                                  ref.invalidate(mapPlacesProvider(_filter)),
                              child: const Text('RETRY')),
                        ]),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),

          // ── Right rail: locate + fit ──────────────────────────────────
          Positioned(
            right: 14,
            bottom: 14,
            child: Column(
              children: [
                _RoundButton(
                  icon: _follow
                      ? Icons.my_location
                      : Icons.location_searching_rounded,
                  tooltip: 'Show me on the map',
                  active: _follow,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    final point = live.point;
                    if (point == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(_locationHint(live.status))));
                      return;
                    }
                    setState(() => _follow = true);
                    _map.move(point, math.max(_map.camera.zoom, 15));
                  },
                ),
                const SizedBox(height: 8),
                _RoundButton(
                  icon: Icons.center_focus_strong,
                  tooltip: 'Show every quest place',
                  onTap: () {
                    setState(() => _follow = false);
                    _fitTo(rows);
                  },
                ),
              ],
            ),
          ),

          // ── Bottom: progress + places list ────────────────────────────
          Positioned(
            left: 14,
            right: 78,
            bottom: 14,
            child: Row(
              children: [
                if (countryRows.isNotEmpty)
                  Expanded(
                    child: _ProgressPill(
                      countries: _country == null
                          ? countryRows
                          : countryRows
                              .where((c) => c.code == _country)
                              .toList(),
                      onTap: () => showModalBottomSheet<void>(
                          context: context,
                          useSafeArea: true,
                          backgroundColor: QuestColors.osBg,
                          builder: (_) => Padding(
                              padding: const EdgeInsets.all(20),
                              child: DiscoveryProgress(
                                  countries: _country == null
                                      ? countryRows
                                      : countryRows
                                          .where((c) => c.code == _country)
                                          .toList()))),
                    ),
                  ),
                const SizedBox(width: 8),
                _Panel(
                  padding: EdgeInsets.zero,
                  child: Semantics(
                    button: true,
                    label: 'Places list',
                    child: InkWell(
                      onTap: () => _openList(rows, places.isLoading),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.list_rounded, size: 18),
                          const SizedBox(width: 6),
                          Text('${rows.length}',
                              style: QuestTypography.osHeadlineSmall),
                        ]),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _locationHint(LiveLocationStatus status) => switch (status) {
        LiveLocationStatus.serviceOff =>
          'Turn on location services to see yourself on the map.',
        LiveLocationStatus.denied ||
        LiveLocationStatus.deniedForever =>
          'Allow location access to see yourself on the map.',
        LiveLocationStatus.unavailable =>
          'Live location is not available on this device.',
        LiveLocationStatus.pending || LiveLocationStatus.live => 'Finding you…',
      };

  void _setCountry(String? code, List<MapPlace> current) {
    setState(() {
      _country = code;
      _follow = false;
    });
    // Frame the country as soon as its places are known.
    _fittedOnce = false;
  }

  void _fitTo(List<MapPlace> places) {
    if (places.isEmpty) {
      _map.move(_home, 8);
      return;
    }
    final points = [for (final p in places) LatLng(p.latitude, p.longitude)];
    if (points.length == 1) {
      _map.move(points.first, 13);
      return;
    }
    _map.fitCamera(CameraFit.bounds(
      bounds: LatLngBounds.fromPoints(points),
      padding: const EdgeInsets.fromLTRB(40, 200, 40, 160),
      maxZoom: 15,
    ));
  }

  Future<void> _openPlace(MapPlace place) async {
    HapticFeedback.lightImpact();
    setState(() => _follow = false);
    _map.move(LatLng(place.latitude, place.longitude),
        math.max(_map.camera.zoom, place.locked ? 11 : 14));
    await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: QuestColors.osBg,
        builder: (_) => place.locked
            ? _LockedSheet(place: place)
            : _PlaceSheet(place: place, from: _lastFix));
    if (mounted) {
      ref.invalidate(mapPlacesProvider);
      ref.invalidate(mapCountriesProvider);
    }
  }

  Future<void> _openList(List<MapPlace> rows, bool loading) {
    return showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: QuestColors.osBg,
        builder: (sheetContext) => DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.55,
            minChildSize: 0.3,
            maxChildSize: 0.95,
            builder: (_, scroll) => ListView(
                  controller: scroll,
                  padding: const EdgeInsets.all(20),
                  children: [
                    Text('${rows.length} PLACES',
                        style: QuestTypography.osDisplaySmall),
                    const SizedBox(height: 12),
                    if (loading) const LinearProgressIndicator(),
                    if (!loading && rows.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Text(
                            _category == 'hidden'
                                ? 'Hidden places show as locked pins until an approved quest nearby reveals them.'
                                : 'No matching published places yet. Try another country or filter.',
                            style: QuestTypography.osBodyMedium),
                      ),
                    for (final p in rows)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: ArcadeCard(
                          onTap: () {
                            Navigator.pop(sheetContext);
                            _openPlace(p);
                          },
                          padding: const EdgeInsets.all(14),
                          child: Row(children: [
                            _PinGlyph(place: p, size: 36),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(p.name,
                                      style: QuestTypography.osHeadlineSmall),
                                  Text(
                                    p.locked
                                        ? 'HIDDEN · COMPLETE A QUEST NEARBY TO REVEAL'
                                        : '${p.category.toUpperCase()}${p.city.isEmpty ? '' : ' · ${p.city}'} · ${p.questCount} QUESTS${p.confirmed ? ' · CONFIRMED' : p.discovered ? ' · IN REVIEW' : ''}',
                                    style: QuestTypography.osLabelSmall
                                        .copyWith(
                                            color: QuestColors.osTextSecondary),
                                  ),
                                ],
                              ),
                            ),
                            Icon(p.saved ? Icons.bookmark : Icons.chevron_right,
                                color: QuestColors.osTextMuted),
                          ]),
                        ),
                      ),
                  ],
                )));
  }
}

// ── Fog of war ───────────────────────────────────────────────────────────────

/// One polygon per country ring. Undiscovered countries sit under heavy ink;
/// once a country has a discovery its fog thins and every confirmed place
/// punches a clear circle through it.
List<Polygon> _fogPolygons(
  List<CountryGeometry> geometry,
  List<MapCountry> countries,
  List<LatLng> confirmed,
) {
  final byGeometryId = {for (final c in countries) c.geometryId: c};
  final holes = [for (final point in confirmed) _circleRing(point)];
  final polygons = <Polygon>[];
  for (final shape in geometry) {
    final country = byGeometryId[shape.id];
    // Only countries with quests are part of the game board.
    if (country == null || country.total == 0) continue;
    final explored = country.discovered > 0;
    for (final ring in shape.rings) {
      if (ring.length < 4) continue;
      polygons.add(Polygon(
        points: [for (final o in ring) LatLng(o.dy, o.dx)],
        holePointsList: explored ? holes : const [],
        color: QuestColors.osTextPrimary.withAlpha(explored ? 70 : 150),
        borderColor: QuestColors.osTextPrimary,
        borderStrokeWidth: 1.5,
      ));
    }
  }
  return polygons;
}

/// A 48-point ring [_revealRadiusM] around [centre], in degrees.
List<LatLng> _circleRing(LatLng centre) {
  const steps = 48;
  const dLat = _revealRadiusM / 111320.0;
  final dLng = _revealRadiusM /
      (111320.0 *
          math.cos(centre.latitude * math.pi / 180).abs().clamp(0.01, 1));
  return [
    for (var i = 0; i < steps; i++)
      LatLng(
        centre.latitude + dLat * math.sin(2 * math.pi * i / steps),
        centre.longitude + dLng * math.cos(2 * math.pi * i / steps),
      ),
  ];
}

// ── Pins ─────────────────────────────────────────────────────────────────────

Color _pinColor(MapPlace p) {
  if (p.locked) return QuestColors.osTextMuted;
  if (p.confirmed) return QuestColors.osSuccess;
  if (p.discovered) return QuestColors.osAccent;
  return QuestColors.osPrimary;
}

IconData _pinIcon(MapPlace p) {
  if (p.locked) return Icons.lock_outline_rounded;
  if (p.confirmed) return Icons.check_rounded;
  if (p.discovered) return Icons.hourglass_bottom_rounded;
  return switch (p.category) {
    'landmark' => Icons.flag_rounded,
    'culture' => Icons.theater_comedy_rounded,
    'pilgrimage' => Icons.route_rounded,
    'heritage' => Icons.account_balance_rounded,
    _ => Icons.place_rounded,
  };
}

/// The chunky square glyph shared by the pin and the list rows.
class _PinGlyph extends StatelessWidget {
  const _PinGlyph({required this.place, required this.size});
  final MapPlace place;
  final double size;

  @override
  Widget build(BuildContext context) {
    final tint = _pinColor(place);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: tint,
        borderRadius: BorderRadius.circular(QuestSpacing.radiusControl),
        border: Border.all(
            color: QuestColors.osTextPrimary,
            width: QuestSpacing.cardBorderWidth),
        boxShadow: QuestSpacing.shadowSm,
      ),
      alignment: Alignment.center,
      child: Icon(_pinIcon(place),
          size: size * 0.55, color: QuestColors.onAccent(tint)),
    );
  }
}

/// A place on the map: the glyph on a stem, with a bookmark badge when saved
/// and a quest count when there is more than one quest to do there.
class _PlacePin extends StatelessWidget {
  const _PlacePin({required this.place, required this.onTap});
  final MapPlace place;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: place.name,
      child: Semantics(
        button: true,
        label: place.locked
            ? 'Locked location'
            : '${place.name}, ${place.questCount} quests',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  _PinGlyph(place: place, size: 40),
                  if (place.saved)
                    const Positioned(
                      top: -6,
                      right: -6,
                      child: Icon(Icons.bookmark,
                          size: 16, color: QuestColors.osAccent),
                    ),
                  if (!place.locked && place.questCount > 1)
                    Positioned(
                      top: -8,
                      left: -8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: QuestColors.osCard,
                          borderRadius:
                              BorderRadius.circular(QuestSpacing.radiusFull),
                          border: Border.all(
                              color: QuestColors.osTextPrimary, width: 1.5),
                        ),
                        child: Text('${place.questCount}',
                            style: QuestTypography.osLabelSmall
                                .copyWith(fontSize: 10, height: 1.2)),
                      ),
                    ),
                ],
              ),
              // Stem
              Container(
                width: 3,
                height: 10,
                color: QuestColors.osTextPrimary,
              ),
              Container(
                width: 8,
                height: 4,
                decoration: BoxDecoration(
                  color: QuestColors.osTextPrimary.withAlpha(120),
                  borderRadius: BorderRadius.circular(QuestSpacing.radiusFull),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The player: their avatar in a ring, with a slow pulse so it reads as
/// live rather than as another pin.
class _PlayerMarker extends StatefulWidget {
  const _PlayerMarker({required this.avatarUrl, required this.username});
  final String? avatarUrl;
  final String username;

  @override
  State<_PlayerMarker> createState() => _PlayerMarkerState();
}

class _PlayerMarkerState extends State<_PlayerMarker>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat();

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'You are here',
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (context, child) {
          final t = _pulse.value;
          return Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 28 + 32 * t,
                height: 28 + 32 * t,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: QuestColors.osCool.withAlpha((120 * (1 - t)).round()),
                ),
              ),
              child!,
            ],
          );
        },
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: QuestColors.osCard, width: 3),
            boxShadow: QuestSpacing.shadowSm,
          ),
          child: PixelAvatar(
            imageUrl: widget.avatarUrl,
            username: widget.username,
            size: 36,
          ),
        ),
      ),
    );
  }
}

// ── Chrome ───────────────────────────────────────────────────────────────────

/// A cream panel with the design's ink outline and hard shadow, for anything
/// floating over the map.
class _Panel extends StatelessWidget {
  const _Panel({required this.child, this.padding = const EdgeInsets.all(12)});
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: QuestColors.osCard,
        borderRadius: BorderRadius.circular(QuestSpacing.radiusPanel),
        border: Border.all(
            color: QuestColors.osTextPrimary,
            width: QuestSpacing.cardBorderWidth),
        boxShadow: QuestSpacing.shadowSm,
      ),
      child: child,
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.active = false,
  });
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            width: QuestSpacing.minTouchTarget,
            height: QuestSpacing.minTouchTarget,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: active ? QuestColors.osPrimary : QuestColors.osCard,
              borderRadius: BorderRadius.circular(QuestSpacing.radiusButton),
              border: Border.all(
                  color: QuestColors.osTextPrimary,
                  width: QuestSpacing.cardBorderWidth),
              boxShadow: QuestSpacing.shadowSm,
            ),
            child: Icon(icon,
                size: 20,
                color: active
                    ? QuestColors.onAccent(QuestColors.osPrimary)
                    : QuestColors.osTextPrimary),
          ),
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.accent = false,
    this.icon,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool accent;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final ground = selected
        ? (accent ? QuestColors.osPrimary : QuestColors.osTextPrimary)
        : QuestColors.osCard;
    final ink = selected
        ? (accent
            ? QuestColors.onAccent(QuestColors.osPrimary)
            : QuestColors.osBg)
        : QuestColors.osTextPrimary;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Container(
          constraints:
              const BoxConstraints(minHeight: QuestSpacing.minTouchTarget - 10),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: ground,
            borderRadius: BorderRadius.circular(QuestSpacing.radiusButton),
            border: Border.all(
                color: QuestColors.osTextPrimary,
                width: QuestSpacing.cardBorderWidth),
            boxShadow: QuestSpacing.shadowSm,
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: ink),
              const SizedBox(width: 4),
            ],
            Text(label,
                style: QuestTypography.osLabelMedium
                    .copyWith(fontSize: 11, color: ink, height: 1)),
          ]),
        ),
      ),
    );
  }
}

class _ProgressPill extends StatelessWidget {
  const _ProgressPill({required this.countries, required this.onTap});
  final List<MapCountry> countries;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final total = countries.fold(0, (n, c) => n + c.total);
    final discovered = countries.fold(0, (n, c) => n + c.discovered);
    final fraction = total == 0 ? 0.0 : (discovered / total).clamp(0.0, 1.0);
    return Semantics(
      button: true,
      label: 'Discovery progress',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: _Panel(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${countries.length == 1 ? countries.first.name.toUpperCase() : 'WORLD'} · $discovered / $total DISCOVERED',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: QuestTypography.osLabelSmall,
                  ),
                  const SizedBox(height: 6),
                  ArcadeMeter(
                      progress: fraction,
                      fill: QuestColors.osSuccess,
                      height: 8),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text('${(fraction * 100).round()}%',
                style: QuestTypography.osHeadlineMedium),
          ]),
        ),
      ),
    );
  }
}

class _LocationBanner extends StatelessWidget {
  const _LocationBanner({required this.status});
  final LiveLocationStatus status;

  @override
  Widget build(BuildContext context) {
    final serviceOff = status == LiveLocationStatus.serviceOff;
    return _Panel(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      child: Row(children: [
        const Icon(Icons.location_off_outlined, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            serviceOff
                ? 'Location is off. Turn it on to see yourself on the map.'
                : 'Allow location to see yourself and your distance to each quest.',
            style: QuestTypography.osBodySmall,
          ),
        ),
        TextButton(
          onPressed: () => serviceOff
              ? Geolocator.openLocationSettings()
              : Geolocator.openAppSettings(),
          child: const Text('SETTINGS'),
        ),
      ]),
    );
  }
}

// ── Sheets ───────────────────────────────────────────────────────────────────

class DiscoveryProgress extends StatelessWidget {
  const DiscoveryProgress({super.key, required this.countries});
  final List<MapCountry> countries;
  @override
  Widget build(BuildContext context) {
    final total = countries.fold(0, (n, c) => n + c.total),
        discovered = countries.fold(0, (n, c) => n + c.discovered);
    final confirmed = countries.fold(0, (n, c) => n + c.confirmed);
    final fraction = total == 0 ? 0.0 : discovered / total;
    return ArcadeCard(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
              '${countries.length == 1 ? countries.first.name.toUpperCase() : 'WORLD'} · ${(fraction * 100).round()}%',
              style: QuestTypography.osHeadlineMedium),
          const SizedBox(height: 10),
          ArcadeMeter(
              progress: fraction, fill: QuestColors.osSuccess, height: 10),
          const SizedBox(height: 10),
          Text('$discovered OF $total PUBLISHED LOCATIONS DISCOVERED',
              style: QuestTypography.osLabelSmall),
          Text(
              '$confirmed confirmed · ${discovered - confirmed} awaiting review',
              style: QuestTypography.osBodySmall),
          if (total == 0)
            Text('Published destinations will appear here when added.',
                style: QuestTypography.osBodySmall),
        ]));
  }
}

/// A hidden place the player has not uncovered yet.
class _LockedSheet extends StatelessWidget {
  const _LockedSheet({required this.place});
  final MapPlace place;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        _PinGlyph(place: place, size: 64),
        const SizedBox(height: 16),
        Text('LOCKED LOCATION', style: QuestTypography.osDisplaySmall),
        const SizedBox(height: 8),
        Text(
          'Something is hidden around here. Complete a quest at any place '
          'within ${(_revealRadiusM / 1000).round()} km and get it approved to '
          'reveal this part of the map.',
          textAlign: TextAlign.center,
          style: QuestTypography.osBodyMedium,
        ),
        const SizedBox(height: 16),
        ArcadeButton(label: 'Got it', onTap: () => Navigator.pop(context)),
      ]),
    );
  }
}

class _PlaceSheet extends ConsumerStatefulWidget {
  const _PlaceSheet({required this.place, this.from});
  final MapPlace place;

  /// The player's last fix, for the distance line. Device GPS, so it only
  /// informs — it never counts as having been there.
  final LatLng? from;

  @override
  ConsumerState<_PlaceSheet> createState() => _PlaceSheetState();
}

class _PlaceSheetState extends ConsumerState<_PlaceSheet> {
  late bool _saved = widget.place.saved;
  bool _saving = false;

  String? get _distanceLabel {
    final from = widget.from;
    if (from == null) return null;
    final metres = const Distance().as(LengthUnit.Meter, from,
        LatLng(widget.place.latitude, widget.place.longitude));
    if (metres < 1000) return '${metres.round()} m away';
    return '${(metres / 1000).toStringAsFixed(metres < 10000 ? 1 : 0)} km away';
  }

  @override
  Widget build(BuildContext context) {
    final place = widget.place;
    final distance = _distanceLabel;
    return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (context, scroll) => ListView(
                controller: scroll,
                padding: const EdgeInsets.all(20),
                children: [
                  Row(children: [
                    _PinGlyph(place: place, size: 44),
                    const SizedBox(width: 12),
                    Expanded(
                        child: Text(place.name,
                            style: QuestTypography.osDisplaySmall)),
                    IconButton(
                        tooltip: 'Close place',
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close))
                  ]),
                  const SizedBox(height: 6),
                  Text(
                    '${place.category.toUpperCase()}${place.city.isEmpty ? '' : ' · ${place.city}'}'
                    '${distance == null ? '' : ' · ${distance.toUpperCase()}'}',
                    style: QuestTypography.osLabelSmall
                        .copyWith(color: QuestColors.osTextSecondary),
                  ),
                  if (place.confirmed || place.discovered) ...[
                    const SizedBox(height: 8),
                    Row(children: [
                      Icon(
                          place.confirmed
                              ? Icons.check_circle
                              : Icons.hourglass_bottom_rounded,
                          size: 16,
                          color: place.confirmed
                              ? QuestColors.osSuccess
                              : QuestColors.osAccentInk),
                      const SizedBox(width: 6),
                      Text(
                          place.confirmed
                              ? 'DISCOVERED · REVEALED THE MAP AROUND HERE'
                              : 'PROOF SUBMITTED · AWAITING REVIEW',
                          style: QuestTypography.osLabelSmall),
                    ]),
                  ],
                  const SizedBox(height: 12),
                  if (place.description.isNotEmpty)
                    Text(place.description,
                        style: QuestTypography.osBodyMedium),
                  const SizedBox(height: 8),
                  TextButton.icon(
                      onPressed: _saving
                          ? null
                          : () async {
                              setState(() => _saving = true);
                              try {
                                await ref
                                    .read(mapRepositoryProvider)
                                    .save(place.id, !_saved);
                                if (mounted) setState(() => _saved = !_saved);
                              } catch (_) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                          content: Text(
                                              'Could not update saved place. Try again.')));
                                }
                              } finally {
                                if (mounted) setState(() => _saving = false);
                              }
                            },
                      icon:
                          Icon(_saved ? Icons.bookmark : Icons.bookmark_border),
                      label: Text(_saved ? 'SAVED' : 'SAVE FOR LATER')),
                  const SizedBox(height: 8),
                  Text('QUESTS HERE', style: QuestTypography.osHeadlineMedium),
                  const SizedBox(height: 8),
                  ref.watch(mapDetailProvider(place.id)).when(
                      loading: () =>
                          const Center(child: CircularProgressIndicator()),
                      error: (_, __) => _Retry(
                          message: 'Place details unavailable.',
                          onRetry: () =>
                              ref.invalidate(mapDetailProvider(place.id))),
                      data: (detail) => Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (detail.quests.isEmpty)
                                  Text(
                                      'No active quests published at this place yet.',
                                      style: QuestTypography.osBodyMedium),
                                for (final q in detail.quests)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 10),
                                    child: ArcadeCard(
                                      onTap: () {
                                        Navigator.pop(context);
                                        context.pushNamed(
                                            RouteNames.questDetails,
                                            pathParameters: {'id': q.id});
                                      },
                                      padding: const EdgeInsets.all(14),
                                      child: Row(children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(q.title,
                                                  style: QuestTypography
                                                      .osHeadlineSmall),
                                              const SizedBox(height: 4),
                                              Text(
                                                '${q.category.toUpperCase()} · ${q.hours}H · ${q.xp} XP'
                                                '${q.requiresVerification ? ' · NETWORK-VERIFIED' : ''}',
                                                style: QuestTypography
                                                    .osLabelSmall
                                                    .copyWith(
                                                        color: QuestColors
                                                            .osTextSecondary),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const Icon(Icons.chevron_right),
                                      ]),
                                    ),
                                  ),
                                if (detail.quests
                                    .any((q) => q.requiresVerification))
                                  Padding(
                                    padding:
                                        const EdgeInsets.symmetric(vertical: 8),
                                    child: Text(
                                      'NETWORK-VERIFIED quests ask your mobile network to confirm you were inside the '
                                      '${place.radiusM} m circle when you submit proof. Phone GPS is only for the map.',
                                      style: QuestTypography.osBodySmall
                                          .copyWith(
                                              color:
                                                  QuestColors.osTextSecondary),
                                    ),
                                  ),
                                if (detail.previews.isNotEmpty) ...[
                                  const SizedBox(height: 16),
                                  Text('QUEST VIDEOS',
                                      style: QuestTypography.osHeadlineMedium),
                                  const SizedBox(height: 8),
                                  Wrap(spacing: 12, children: [
                                    for (final p in detail.previews)
                                      Column(children: [
                                        IconButton.filled(
                                            tooltip:
                                                'Watch quest by ${p.username}',
                                            onPressed: () {
                                              Navigator.pop(context);
                                              context.pushNamed(
                                                  RouteNames.feedPostDetails,
                                                  pathParameters: {'id': p.id});
                                            },
                                            icon: const Icon(
                                                Icons.play_circle_outline,
                                                size: 36)),
                                        Text(p.username,
                                            style: QuestTypography.osLabelSmall)
                                      ])
                                  ])
                                ],
                              ])),
                ]));
  }
}

class MapLegend extends StatelessWidget {
  const MapLegend({super.key});
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('MAP LEGEND', style: QuestTypography.osDisplayMedium),
            const SizedBox(height: 16),
            Text(
                'A real OpenStreetMap map. Countries with quests start under fog; '
                'an approved quest clears a ${(_revealRadiusM / 1000).round()} km circle around its place and reveals the hidden pins inside it.',
                style: QuestTypography.osBodyMedium),
            const SizedBox(height: 16),
            for (final entry in {
              'VIOLET PIN': 'A place with quests you can start now.',
              'GOLD PIN': 'You submitted proof here; it is awaiting review.',
              'GREEN PIN':
                  'Approved — discovered, and the fog around it is gone.',
              'GREY LOCK':
                  'A hidden place. Its exact spot and name stay secret until you reveal it.',
              'CIRCLE AROUND A PIN':
                  'The geofence the network checks you against for NETWORK-VERIFIED quests.',
              'YOUR AVATAR':
                  'Your live position from phone GPS. It moves the map; it never counts as proof.',
              'SAVED': 'Bookmarks for future travel, not visits.',
            }.entries)
              ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(entry.key, style: QuestTypography.osLabelMedium),
                  subtitle:
                      Text(entry.value, style: QuestTypography.osBodySmall)),
            Text(
                'Percentages count published quest locations, not geographic surface area. Rejected or removed proof does not count.',
                style: QuestTypography.osBodySmall),
            TextButton(
                onPressed: () => showLicensePage(context: context),
                child: const Text('MAP & GEOGRAPHY LICENSES')),
          ]));
}

class _Retry extends StatelessWidget {
  const _Retry({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.all(16),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(message, style: QuestTypography.osBodyMedium),
        TextButton(onPressed: onRetry, child: const Text('RETRY'))
      ]));
}
