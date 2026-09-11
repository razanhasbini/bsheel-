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
// `hide Path`: latlong2's Path<LatLng> would shadow dart:ui's Path, which
// the pin stem painter draws with.
import 'package:latlong2/latlong.dart' hide Path;
import 'package:shared_ui/shared_ui.dart';

import '../../../core/providers/current_profile_provider.dart';
import '../../../core/router/route_names.dart';
import '../data/live_location_provider.dart';
import '../data/map_providers.dart';
import '../domain/map_geometry.dart';

/// Natural Earth country outlines, decoded once — they cut the fog of war
/// along real borders.
final mapGeometryProvider = FutureProvider<List<CountryGeometry>>((ref) async =>
    CountryGeometry.decode(
        jsonDecode(await rootBundle.loadString('assets/map/countries-50m.json'))
            as Map<String, dynamic>));

/// CARTO Voyager without labels: soft colours, no street names, so the pins
/// and the fog carry the screen. Free with attribution; heavy production
/// traffic should move to a keyed plan.
const _tiles =
    'https://basemaps.cartocdn.com/rastertiles/voyager_nolabels/{z}/{x}/{y}@2x.png';
const _userAgent = 'com.questapp.mobileApp';

/// An approved quest uncovers the hidden places within this distance — the
/// same number the server uses, so the cleared circle is exactly the area
/// that is really open.
const double _revealRadiusM = 10000;

/// Beirut, before anything is known.
const _home = LatLng(33.8938, 35.5018);

const _flags = <String, String>{'LB': '🇱🇧', 'QA': '🇶🇦'};

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

  /// Snapchat-style: the camera rides with the player until they pan.
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

  bool get _filtered => _category != null || _savedOnly;

  @override
  Widget build(BuildContext context) {
    final countries = ref.watch(mapCountriesProvider);
    final geometry = ref.watch(mapGeometryProvider);
    final places = ref.watch(mapPlacesProvider(_filter));
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
    final navInset = MediaQuery.of(context).padding.bottom * 0.30 + 78;

    final fix = live.point;
    if (fix != null && fix != _lastFix) {
      _lastFix = fix;
      if (_follow) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _map.move(fix, math.max(_map.camera.zoom, 14));
        });
      }
    }
    if (!_fittedOnce && rows.isNotEmpty) {
      _fittedOnce = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _fitTo(rows, navInset);
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
                  if (hasGesture && _follow) setState(() => _follow = false);
                },
              ),
              children: [
                if (tiles)
                  TileLayer(
                    urlTemplate: _tiles,
                    userAgentPackageName: _userAgent,
                    maxNativeZoom: 19,
                  ),
                // ── Fog of war ────────────────────────────────────────
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
                    for (final point in confirmedPoints)
                      CircleMarker(
                        point: point,
                        radius: _revealRadiusM,
                        useRadiusInMeter: true,
                        color: QuestColors.osSuccess.withAlpha(28),
                        borderColor: QuestColors.osSuccess.withAlpha(140),
                        borderStrokeWidth: 1.5,
                      ),
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
                        width: 52,
                        height: 62,
                        alignment: Alignment.topCenter,
                        child: _PlacePin(place: p, onTap: () => _openPlace(p)),
                      ),
                    if (fix != null)
                      Marker(
                        point: fix,
                        width: 64,
                        height: 76,
                        alignment: Alignment.topCenter,
                        child: _PlayerPin(
                          avatarUrl: me?.avatarUrl,
                          username: me?.username ?? '',
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),

          // ── Header: EXPLORE · filter, search, countries ──────────────
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 6, 14, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Text(
                          'EXPLORE',
                          style: QuestTypography.osLabelMedium.copyWith(
                            fontSize: 12,
                            letterSpacing: 2.4,
                            shadows: const [
                              Shadow(
                                  color: QuestColors.osBg,
                                  blurRadius: 6,
                                  offset: Offset(0, 1)),
                            ],
                          ),
                        ),
                        const Spacer(),
                        _SmallButton(
                          icon: Icons.tune_rounded,
                          tooltip: 'Filters',
                          badge: _filtered,
                          onTap: _openFilters,
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    // One border only: the field draws none of its own.
                    Container(
                      height: 40,
                      padding: const EdgeInsets.only(left: 10),
                      decoration: BoxDecoration(
                        color: QuestColors.osCard,
                        borderRadius:
                            BorderRadius.circular(QuestSpacing.radiusButton),
                        border: Border.all(
                            color: QuestColors.osTextPrimary,
                            width: QuestSpacing.cardBorderWidth),
                        boxShadow: QuestSpacing.shadowSm,
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.search, size: 18),
                          const SizedBox(width: 6),
                          Expanded(
                            child: TextField(
                              controller: _searchController,
                              style: QuestTypography.osBodySmall,
                              decoration: InputDecoration(
                                hintText: 'Find a place…',
                                hintStyle: QuestTypography.osBodySmall
                                    .copyWith(color: QuestColors.osTextMuted),
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                filled: false,
                                isDense: true,
                                contentPadding: EdgeInsets.zero,
                              ),
                              onChanged: (value) {
                                _debounce?.cancel();
                                _debounce = Timer(
                                    const Duration(milliseconds: 300), () {
                                  if (mounted) {
                                    setState(() => _search = value);
                                  }
                                });
                              },
                            ),
                          ),
                          // People & quests search rides inside the field.
                          Semantics(
                            button: true,
                            label: 'Search people and quests',
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () => context.pushNamed(RouteNames.search),
                              child: const SizedBox(
                                width: 40,
                                height: 40,
                                child: Icon(Icons.person_search_outlined,
                                    size: 18),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    if (countryRows.isNotEmpty)
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            for (final c in countryRows) ...[
                              _CountryChip(
                                flag: _flags[c.code] ?? '📍',
                                name: c.name,
                                selected: _country == c.code,
                                onTap: () => _setCountry(
                                    _country == c.code ? null : c.code),
                              ),
                              const SizedBox(width: 6),
                            ],
                          ],
                        ),
                      ),
                    if (live.status != LiveLocationStatus.live &&
                        live.status != LiveLocationStatus.pending &&
                        live.status != LiveLocationStatus.unavailable) ...[
                      const SizedBox(height: 6),
                      _LocationBanner(status: live.status),
                    ],
                    if (places.hasError) ...[
                      const SizedBox(height: 6),
                      _Panel(
                        padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
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

          // ── Right: locate me ─────────────────────────────────────────
          Positioned(
            right: 14,
            bottom: navInset,
            child: _SmallButton(
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
          ),

          // ── Left: progress + places count ────────────────────────────
          Positioned(
            left: 14,
            bottom: navInset,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (countryRows.isNotEmpty)
                  _ProgressChip(
                    countries: _country == null
                        ? countryRows
                        : countryRows.where((c) => c.code == _country).toList(),
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
                const SizedBox(width: 6),
                _CountChip(
                  icon: Icons.place_rounded,
                  count: rows.length,
                  tooltip: 'Places list',
                  onTap: () => _openList(rows, places.isLoading),
                ),
              ],
            ),
          ),

          if (tiles)
            Positioned(
              left: 14,
              bottom: navInset + 40,
              child: Text(
                '© OpenStreetMap · © CARTO',
                style: QuestTypography.osLabelSmall.copyWith(
                  fontSize: 8,
                  height: 1.2,
                  color: QuestColors.osTextSecondary,
                  shadows: const [
                    Shadow(color: QuestColors.osBg, blurRadius: 4),
                  ],
                ),
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

  void _setCountry(String? code) {
    setState(() {
      _country = code;
      _follow = false;
      // Frame the country as soon as its places are known.
      _fittedOnce = false;
    });
  }

  void _fitTo(List<MapPlace> places, double navInset) {
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
      padding: EdgeInsets.fromLTRB(40, 170, 40, navInset + 60),
      maxZoom: 15,
    ));
  }

  Future<void> _openFilters() {
    HapticFeedback.selectionClick();
    return showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      backgroundColor: QuestColors.osBg,
      builder: (sheetContext) => _FilterSheet(
        category: _category,
        savedOnly: _savedOnly,
        onCategory: (value) => setState(() => _category = value),
        onSavedOnly: (value) => setState(() => _savedOnly = value),
        onLegend: () {
          Navigator.pop(sheetContext);
          showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              useSafeArea: true,
              backgroundColor: QuestColors.osBg,
              builder: (_) => const MapLegend());
        },
      ),
    );
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
                                : 'No published places here yet.',
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
                          padding: const EdgeInsets.all(12),
                          child: Row(children: [
                            _PinGlyph(place: p, size: 40),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(p.name,
                                      style: QuestTypography.osHeadlineSmall),
                                  Text(
                                    p.locked
                                        ? 'LOCKED'
                                        : '${p.questCount} QUESTS${p.confirmed ? ' · DONE' : p.discovered ? ' · IN REVIEW' : ''}',
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

/// Illustrated, not iconised: one emoji per state and category, so the
/// board reads at a glance without a word on it.
String _pinEmoji(MapPlace p) {
  if (p.locked) return '🔒';
  if (p.confirmed) return '🏆';
  if (p.discovered) return '⏳';
  return switch (p.category) {
    'landmark' => '🏰',
    'culture' => '🎭',
    'pilgrimage' => '🧭',
    'heritage' => '🏛️',
    _ => '⭐',
  };
}

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
        borderRadius: BorderRadius.circular(QuestSpacing.radiusPanel),
        border: Border.all(
            color: QuestColors.osTextPrimary,
            width: QuestSpacing.cardBorderWidth),
        boxShadow: QuestSpacing.shadowSm,
      ),
      alignment: Alignment.center,
      child: Text(
        _pinEmoji(place),
        style: TextStyle(fontSize: size * 0.5, height: 1),
      ),
    );
  }
}

/// A place: the emoji badge on a stem, bookmark when saved, a count when
/// more than one quest waits there.
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
                  _PinGlyph(place: place, size: 44),
                  if (place.saved)
                    const Positioned(
                      top: -7,
                      right: -7,
                      child: Icon(Icons.bookmark,
                          size: 16, color: QuestColors.osAccent),
                    ),
                  if (!place.locked && place.questCount > 1)
                    Positioned(
                      top: -8,
                      left: -8,
                      child: Container(
                        width: 20,
                        height: 20,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: QuestColors.osCard,
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: QuestColors.osTextPrimary, width: 1.5),
                        ),
                        child: Text('${place.questCount}',
                            style: QuestTypography.osLabelSmall
                                .copyWith(fontSize: 10, height: 1)),
                      ),
                    ),
                ],
              ),
              const CustomPaint(
                size: Size(14, 9),
                painter: _StemPainter(),
              ),
              Container(
                width: 8,
                height: 3,
                decoration: BoxDecoration(
                  color: QuestColors.osTextPrimary.withAlpha(110),
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

/// The little ink triangle that turns a badge into a pin.
class _StemPainter extends CustomPainter {
  const _StemPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = QuestColors.osTextPrimary);
  }

  @override
  bool shouldRepaint(_StemPainter oldDelegate) => false;
}

/// The player: their avatar as a pin — round photo in a sky ring on an ink
/// stem, with a slow pulse underneath so it reads as live.
class _PlayerPin extends StatefulWidget {
  const _PlayerPin({required this.avatarUrl, required this.username});
  final String? avatarUrl;
  final String username;

  @override
  State<_PlayerPin> createState() => _PlayerPinState();
}

class _PlayerPinState extends State<_PlayerPin>
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 50,
            height: 50,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: QuestColors.osCool,
              shape: BoxShape.circle,
              border: Border.all(
                  color: QuestColors.osTextPrimary,
                  width: QuestSpacing.cardBorderWidth),
              boxShadow: QuestSpacing.shadowSm,
            ),
            child: ClipOval(
              child: PixelAvatar(
                imageUrl: widget.avatarUrl,
                username: widget.username,
                size: 40,
              ),
            ),
          ),
          const CustomPaint(
            size: Size(16, 10),
            painter: _StemPainter(),
          ),
          AnimatedBuilder(
            animation: _pulse,
            builder: (context, _) {
              final t = _pulse.value;
              return Container(
                width: 10 + 26 * t,
                height: 4 + 8 * t,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(QuestSpacing.radiusFull),
                  color: QuestColors.osCool.withAlpha((150 * (1 - t)).round()),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

// ── Chrome ───────────────────────────────────────────────────────────────────

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

/// 36pt square button — the whole map chrome uses this one size.
class _SmallButton extends StatelessWidget {
  const _SmallButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.active = false,
    this.badge = false,
  });
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool active;
  final bool badge;

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
          // 44pt hit box around a 36pt paint.
          child: SizedBox(
            width: QuestSpacing.minTouchTarget,
            height: QuestSpacing.minTouchTarget,
            child: Center(
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color:
                          active ? QuestColors.osPrimary : QuestColors.osCard,
                      borderRadius:
                          BorderRadius.circular(QuestSpacing.radiusSm),
                      border: Border.all(
                          color: QuestColors.osTextPrimary,
                          width: QuestSpacing.cardBorderWidth),
                      boxShadow: QuestSpacing.shadowSm,
                    ),
                    child: Icon(icon,
                        size: 18,
                        color: active
                            ? QuestColors.onAccent(QuestColors.osPrimary)
                            : QuestColors.osTextPrimary),
                  ),
                  if (badge)
                    Positioned(
                      top: -3,
                      right: -3,
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: QuestColors.osRed,
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: QuestColors.osTextPrimary, width: 1.5),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Flag + name, ink when selected.
class _CountryChip extends StatelessWidget {
  const _CountryChip({
    required this.flag,
    required this.name,
    required this.selected,
    required this.onTap,
  });
  final String flag;
  final String name;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: name,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Container(
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: selected ? QuestColors.osTextPrimary : QuestColors.osCard,
            borderRadius: BorderRadius.circular(QuestSpacing.radiusFull),
            border: Border.all(
                color: QuestColors.osTextPrimary,
                width: QuestSpacing.cardBorderWidth),
            boxShadow: QuestSpacing.shadowSm,
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(flag, style: const TextStyle(fontSize: 13, height: 1)),
            const SizedBox(width: 6),
            Text(
              name.toUpperCase(),
              style: QuestTypography.osLabelMedium.copyWith(
                fontSize: 11,
                height: 1,
                color: selected ? QuestColors.osBg : QuestColors.osTextPrimary,
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Trophy, `3/10`, a short meter. Tap for the full breakdown.
class _ProgressChip extends StatelessWidget {
  const _ProgressChip({required this.countries, required this.onTap});
  final List<MapCountry> countries;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final total = countries.fold(0, (n, c) => n + c.total);
    final discovered = countries.fold(0, (n, c) => n + c.discovered);
    final fraction = total == 0 ? 0.0 : (discovered / total).clamp(0.0, 1.0);
    return Semantics(
      button: true,
      label: 'Discovery progress, $discovered of $total',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: _Panel(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Text('🏆', style: TextStyle(fontSize: 14, height: 1)),
            const SizedBox(width: 6),
            Text('$discovered/$total',
                style: QuestTypography.osHeadlineSmall
                    .copyWith(fontSize: 13, height: 1)),
            const SizedBox(width: 8),
            SizedBox(
              width: 56,
              child: ArcadeMeter(
                  progress: fraction, fill: QuestColors.osSuccess, height: 8),
            ),
          ]),
        ),
      ),
    );
  }
}

class _CountChip extends StatelessWidget {
  const _CountChip({
    required this.icon,
    required this.count,
    required this.tooltip,
    required this.onTap,
  });
  final IconData icon;
  final int count;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: '$tooltip, $count',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: _Panel(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 16),
              const SizedBox(width: 4),
              Text('$count',
                  style: QuestTypography.osHeadlineSmall
                      .copyWith(fontSize: 13, height: 1)),
            ]),
          ),
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
      padding: const EdgeInsets.fromLTRB(10, 4, 4, 4),
      child: Row(children: [
        const Icon(Icons.location_off_outlined, size: 16),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            serviceOff ? 'Location is off.' : 'Allow location to see yourself.',
            style: QuestTypography.osBodySmall,
          ),
        ),
        TextButton(
          onPressed: () => serviceOff
              ? Geolocator.openLocationSettings()
              : Geolocator.openAppSettings(),
          child: const Text('FIX'),
        ),
      ]),
    );
  }
}

// ── Sheets ───────────────────────────────────────────────────────────────────

/// Category, saved-only, and the legend — everything that used to crowd the
/// map header.
class _FilterSheet extends StatefulWidget {
  const _FilterSheet({
    required this.category,
    required this.savedOnly,
    required this.onCategory,
    required this.onSavedOnly,
    required this.onLegend,
  });
  final String? category;
  final bool savedOnly;
  final ValueChanged<String?> onCategory;
  final ValueChanged<bool> onSavedOnly;
  final VoidCallback onLegend;

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late String? _category = widget.category;
  late bool _savedOnly = widget.savedOnly;

  static const _categories = <String?, String>{
    null: '⭐ ALL',
    'landmark': '🏰 LANDMARKS',
    'culture': '🎭 CULTURE',
    'pilgrimage': '🧭 ROUTES',
    'heritage': '🏛️ HERITAGE',
    'hidden': '🔒 HIDDEN',
  };

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
                child: Text('FILTERS', style: QuestTypography.osDisplaySmall)),
            IconButton(
                tooltip: 'Close filters',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close)),
          ]),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final entry in _categories.entries)
                _OptionChip(
                  label: entry.value,
                  selected: _category == entry.key,
                  onTap: () {
                    setState(() => _category = entry.key);
                    widget.onCategory(entry.key);
                  },
                ),
            ],
          ),
          const SizedBox(height: 14),
          _OptionChip(
            label: '🔖 SAVED PLACES ONLY',
            selected: _savedOnly,
            onTap: () {
              setState(() => _savedOnly = !_savedOnly);
              widget.onSavedOnly(_savedOnly);
            },
          ),
          const SizedBox(height: 18),
          ArcadeButton(
            label: 'How the map works',
            variant: ArcadeButtonVariant.secondary,
            icon: Icons.info_outline,
            onTap: widget.onLegend,
          ),
        ],
      ),
    );
  }
}

class _OptionChip extends StatelessWidget {
  const _OptionChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
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
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? QuestColors.osTextPrimary : QuestColors.osCard,
            borderRadius: BorderRadius.circular(QuestSpacing.radiusButton),
            border: Border.all(
                color: QuestColors.osTextPrimary,
                width: QuestSpacing.cardBorderWidth),
          ),
          child: Text(
            label,
            style: QuestTypography.osLabelMedium.copyWith(
              fontSize: 12,
              height: 1,
              color: selected ? QuestColors.osBg : QuestColors.osTextPrimary,
            ),
          ),
        ),
      ),
    );
  }
}

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
        Text('LOCKED', style: QuestTypography.osDisplaySmall),
        const SizedBox(height: 8),
        Text(
          'Something is hidden around here. Finish a quest within '
          '${(_revealRadiusM / 1000).round()} km and get it approved to reveal it.',
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
                    Text(
                        place.confirmed
                            ? '🏆 DONE · MAP REVEALED AROUND HERE'
                            : '⏳ PROOF IN REVIEW',
                        style: QuestTypography.osLabelSmall),
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
                                  Text('No active quests here yet.',
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
                                                '${q.hours}H · ${q.xp} XP'
                                                '${q.requiresVerification ? ' · 📡 NETWORK-VERIFIED' : ''}',
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
                                      'Network-verified quests ask your mobile network to confirm you were inside the '
                                      '${place.radiusM} m circle when you submit. Phone GPS only moves the map.',
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
            Text('HOW THE MAP WORKS', style: QuestTypography.osDisplaySmall),
            const SizedBox(height: 12),
            Text(
                'Countries with quests start under fog. Finish a quest and get it approved: '
                'a ${(_revealRadiusM / 1000).round()} km circle clears and the hidden pins inside it unlock.',
                style: QuestTypography.osBodyMedium),
            const SizedBox(height: 12),
            for (final entry in {
              '🏰 🎭 🧭 🏛️': 'A place with quests you can start now.',
              '⏳': 'Your proof is in review.',
              '🏆': 'Approved — the fog around it is gone.',
              '🔒': 'Hidden. Reveal it by finishing a quest nearby.',
              '◯': 'The circle the network checks you against for 📡 quests.',
              '🧑':
                  'You, from phone GPS. Moves the map, never counts as proof.',
            }.entries)
              ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Text(entry.key,
                      style: const TextStyle(fontSize: 18, height: 1)),
                  title: Text(entry.value, style: QuestTypography.osBodySmall)),
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
