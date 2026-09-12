import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:app_core/app_core.dart';
import 'package:app_models/app_models.dart';
import 'package:cached_network_image/cached_network_image.dart';
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
import 'package:video_player/video_player.dart';

import '../../../core/providers/current_profile_provider.dart';
import '../../../core/providers/auth_session_provider.dart';
import '../../../core/router/route_names.dart';
import '../../reactions/presentation/widgets/bsheeel_dialog.dart'
    show assignQuestFlow;
import '../../../core/services/analytics_reporter.dart';
import '../../../core/widgets/quest_impression.dart';
import '../data/live_location_provider.dart';
import '../data/map_providers.dart';
import '../domain/map_geometry.dart';
import '../../quests/presentation/providers/journey_providers.dart';
import 'journey_route_layer.dart';

/// Natural Earth country outlines, decoded once — they cut the fog of war
/// along real borders.
final mapGeometryProvider = FutureProvider<List<CountryGeometry>>((ref) async =>
    CountryGeometry.decode(
        jsonDecode(await rootBundle.loadString('assets/map/countries-50m.json'))
            as Map<String, dynamic>));

/// Leaflet's own default basemap — the standard OpenStreetMap layer.
/// flutter_map is Leaflet for Flutter, and this is the layer Leaflet ships
/// with. The tile usage policy asks for an identifying user agent, which
/// `userAgentPackageName` sends; sustained production traffic should move to
/// a hosted tile plan.
const _tiles = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
const _userAgent = 'com.questapp.mobileApp';

/// An approved quest uncovers the hidden places within this distance — the
/// same number the server uses, so what the legend promises is exactly the
/// area that is really open.
const double _revealRadiusM = 10000;

/// Beirut, before anything is known.
const _home = LatLng(33.8938, 35.5018);

/// Where the intro starts: the whole world, Middle East roughly centred.
const _world = LatLng(22, 30);
const double _worldZoom = 1.2;

/// Below this zoom the board shows one badge per country instead of every
/// pin — 76 pins on a world view are a smear, one flag per country is a map.
const double _badgeZoom = 5.5;

/// Any ISO 3166-1 alpha-2 code as its flag emoji, so a country the seed adds
/// tomorrow needs no table entry here.
String _flag(String? code) {
  if (code == null || code.length != 2) return '📍';
  final upper = code.toUpperCase();
  return String.fromCharCodes(
      [for (final unit in upper.codeUnits) 0x1F1E6 + unit - 0x41]);
}

class MapPage extends ConsumerStatefulWidget {
  const MapPage({super.key});
  @override
  ConsumerState<MapPage> createState() => _MapPageState();
}

class _MapPageState extends ConsumerState<MapPage>
    with SingleTickerProviderStateMixin {
  String? _country, _category;
  String _search = '';
  bool _savedOnly = false;

  /// 'all' | 'available' | 'completed' — a client-side view over the rows
  /// the server returned; it never changes what the server decides.
  String _status = 'all';
  Timer? _debounce;
  final _searchController = TextEditingController();
  final _map = MapController();

  /// Snapchat-style: the camera rides with the player until they pan.
  bool _follow = false;
  LatLng? _lastFix;

  /// True while the world view is still on screen; the first fix — or the
  /// intro timer, whichever comes first — flies the camera in.
  bool _introPending = true;
  Timer? _introTimer;

  /// Zoomed out enough to show country badges rather than pins.
  bool _badges = true;

  /// Whether the moments layer is drawn — the photo and video squares from
  /// the feed, sitting at the place they were earned. On by default: seeing
  /// that somebody actually did this here is the whole reason to look at a
  /// map rather than a list. The toggle exists because they are also the
  /// densest thing on the board, and a player hunting for one specific pin
  /// deserves to be able to clear the clutter.
  bool _moments = true;

  // ── Camera flight ─────────────────────────────────────────────────────
  // flutter_map moves the camera in one jump; the flight is a tween over
  // centre and zoom driven by this controller, so opening the map reads as
  // "the world, then you", and picking a country reads as travelling to it.
  late final AnimationController _fly = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  )..addListener(_onFlyTick);
  LatLng _flyFrom = _world, _flyTo = _world;
  double _zoomFrom = _worldZoom, _zoomTo = _worldZoom;

  @override
  void initState() {
    super.initState();
    // If the phone has not produced a fix by then, fly to the quests instead
    // of leaving the player staring at a grey world.
    _introTimer = Timer(const Duration(milliseconds: 2200), () {
      if (mounted && _introPending) _finishIntro(null);
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _introTimer?.cancel();
    _fly.dispose();
    _searchController.dispose();
    _map.dispose();
    super.dispose();
  }

  void _onFlyTick() {
    final t = Curves.easeInOutCubic.transform(_fly.value);
    _map.move(
      LatLng(
        _flyFrom.latitude + (_flyTo.latitude - _flyFrom.latitude) * t,
        _flyFrom.longitude + (_flyTo.longitude - _flyFrom.longitude) * t,
      ),
      _zoomFrom + (_zoomTo - _zoomFrom) * t,
    );
  }

  void _flyToPoint(LatLng target, double zoom,
      {Duration duration = const Duration(milliseconds: 1400)}) {
    _flyFrom = _map.camera.center;
    _zoomFrom = _map.camera.zoom;
    _flyTo = target;
    _zoomTo = zoom.clamp(1.0, 18.0);
    _fly.duration = duration;
    _fly.forward(from: 0);
  }

  /// Frame a set of points with room for the header and the nav pill.
  void _flyToPoints(List<LatLng> points, double navInset,
      {double maxZoom = 15}) {
    if (points.isEmpty) return;
    if (points.length == 1) {
      _flyToPoint(points.first, 13);
      return;
    }
    final fitted = CameraFit.bounds(
      bounds: LatLngBounds.fromPoints(points),
      padding: EdgeInsets.fromLTRB(40, 190, 40, navInset + 70),
      maxZoom: maxZoom,
    ).fit(_map.camera);
    _flyToPoint(fitted.center, fitted.zoom);
  }

  /// The intro's second half: from the world to the player, or — with no
  /// fix — to the quests, so the first thing seen is never empty grey.
  void _finishIntro(LatLng? fix) {
    if (!_introPending) return;
    _introPending = false;
    _introTimer?.cancel();
    if (fix != null) {
      _flyToPoint(fix, 12, duration: const Duration(milliseconds: 2600));
      return;
    }
    final everyPlace =
        ref.read(mapPlacesProvider(mapAllPlacesFilter)).valueOrNull ??
            const <MapPlace>[];
    final home = everyPlace.where((p) => p.countryCode == 'LB').toList();
    final navInset = MediaQuery.of(context).padding.bottom * 0.30 + 78;
    if (home.isNotEmpty) {
      _flyToPoints(
          [for (final p in home) LatLng(p.latitude, p.longitude)], navInset,
          maxZoom: 9);
    } else {
      _flyToPoint(_home, 8, duration: const Duration(milliseconds: 2600));
    }
  }

  MapFilter get _filter => (
        country: _country,
        category: _category,
        search: _search,
        offset: 0,
        savedOnly: _savedOnly
      );

  bool get _filtered => _category != null || _savedOnly || _status != 'all';

  @override
  Widget build(BuildContext context) {
    final countries = ref.watch(mapCountriesProvider);
    final geometry = ref.watch(mapGeometryProvider);
    final places = ref.watch(mapPlacesProvider(_filter));
    final allPlaces = ref.watch(mapPlacesProvider(mapAllPlacesFilter));
    final live =
        ref.watch(liveLocationProvider).valueOrNull ?? LiveLocation.pending;
    final journeys =
        ref.watch(activeJourneysProvider).valueOrNull ?? const <JourneyRun>[];
    final tiles = ref.watch(mapTilesEnabledProvider);
    final me = ref.watch(currentProfileProvider).valueOrNull;
    // Only fetched once the board is worth drawing them on: at world zoom
    // every tile would land on the same few pixels anyway, and the request
    // carries signed URLs that start expiring the moment they are issued.
    final moments = _moments && !_badges
        ? ref.watch(mapMomentsProvider(_country)).valueOrNull ??
            const <MapMoment>[]
        : const <MapMoment>[];

    // Which places are already speaking for themselves with a piece of
    // proof. Their pins are suppressed below so the two never stack on one
    // point and compete for the same tap.
    final momentPlaceIds = {for (final moment in moments) moment.placeId};

    final countryRows = countries.valueOrNull ?? const <MapCountry>[];
    final rows = (places.valueOrNull ?? const <MapPlace>[])
        .where((p) => !_savedOnly || p.saved)
        .where((p) => switch (_status) {
              'available' => !p.locked && !p.confirmed,
              'completed' => p.confirmed,
              _ => true,
            })
        .toList();
    final everyPlace = allPlaces.valueOrNull ?? const <MapPlace>[];
    final navInset = MediaQuery.of(context).padding.bottom * 0.30 + 78;

    final fix = live.point;
    if (fix != null && fix != _lastFix) {
      _lastFix = fix;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_introPending) {
          _finishIntro(fix);
        } else if (_follow) {
          _map.move(fix, math.max(_map.camera.zoom, 14));
        }
      });
    }

    // Country badges carry the board while zoomed out; the ones with a
    // selected country step aside so its pins can be seen.
    final badgeCountries = _badges && _country == null
        ? countryRows.where((c) => c.total > 0).toList()
        : const <MapCountry>[];
    final showPins = !_badges || _country != null;

    return Scaffold(
      backgroundColor: QuestColors.osBg,
      body: Stack(
        children: [
          Positioned.fill(
            child: FlutterMap(
              mapController: _map,
              options: MapOptions(
                initialCenter: _world,
                initialZoom: _worldZoom,
                minZoom: 1,
                maxZoom: 18,
                backgroundColor: QuestColors.osSurface,
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                ),
                onPositionChanged: (camera, hasGesture) {
                  if (hasGesture) {
                    if (_fly.isAnimating) _fly.stop();
                    if (_follow) setState(() => _follow = false);
                    if (_introPending) {
                      _introPending = false;
                      _introTimer?.cancel();
                    }
                  }
                  final badges = camera.zoom < _badgeZoom;
                  if (badges != _badges) setState(() => _badges = badges);
                },
              ),
              children: [
                if (tiles)
                  TileLayer(
                    urlTemplate: _tiles,
                    userAgentPackageName: _userAgent,
                    maxNativeZoom: 19,
                  ),
                // ── The grey world and its grids ──────────────────────
                // One veil over the whole planet; countries with quests get
                // a grid, cells with an approved quest are cut out of the
                // veil (colour comes back), and a finished country is cut
                // out whole.
                if (geometry.hasValue)
                  PolygonLayer(
                    polygons: _boardPolygons(
                      geometry.value!,
                      countryRows,
                      everyPlace,
                    ),
                  ),
                if (showPins && !_badges)
                  CircleLayer(
                    circles: [
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
                for (final journey in journeys) JourneyRouteLayer(run: journey),
                MarkerLayer(
                  markers: [
                    for (final c in badgeCountries)
                      Marker(
                        point: _countryAnchor(c, everyPlace, geometry.value),
                        width: 132,
                        height: 44,
                        child: _CountryBadge(
                          country: c,
                          onTap: () => _travelTo(c, everyPlace, navInset),
                        ),
                      ),
                    // A place shows EITHER its proof or its pin, never both
                    // stacked on the same point.
                    //
                    // They used to draw on top of each other — the tile
                    // scattered inside the place radius, which at low zoom
                    // is a few pixels — so the two things a player might
                    // want were the same tap target, and which one they got
                    // depended on draw order rather than on where they
                    // pressed. Hiding the pin under a tile costs nothing,
                    // because the tile carries the same two actions: its ⚑N
                    // badge counts the quests here, and its sheet offers DO
                    // THIS QUEST and EVERYTHING AT <place>.
                    //
                    // The result is the mix asked for: some places show a
                    // piece of proof, the rest show their pin.
                    if (showPins)
                      for (final moment in moments)
                        Marker(
                          point: _scatter(moment),
                          // Card (66) + gap + the "+N more" chip, plus the
                          // avatar ring's 6 of overhang. Measured, not
                          // guessed: a Marker gives its child a fixed box
                          // and a pixel short of it is a RenderFlex overflow
                          // on every tile.
                          width: 76,
                          height: 104,
                          child: _MomentTile(
                            moment: moment,
                            onTap: () => _openMoment(moment),
                          ),
                        ),
                    if (showPins)
                      for (final p in rows)
                        if (!momentPlaceIds.contains(p.id))
                          Marker(
                            point: LatLng(p.latitude, p.longitude),
                            width: 52,
                            height: 62,
                            alignment: Alignment.topCenter,
                            child:
                                _PlacePin(place: p, onTap: () => _openPlace(p)),
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
                                flag: _flag(c.code),
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
                    // With a country picked, one tap opens what it has to
                    // offer — trending, discovery, hidden — from anywhere.
                    if (_country != null) ...[
                      const SizedBox(height: 6),
                      _DiscoverButton(
                        flag: _flag(_country),
                        name: countryRows
                                .where((c) => c.code == _country)
                                .map((c) => c.name)
                                .firstOrNull ??
                            _country!,
                        onTap: () => _openDiscover(_country!),
                      ),
                    ],
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

          // ── Right: moments toggle, above locate-me ───────────────────
          if (!_badges)
            Positioned(
              right: 14,
              bottom: navInset + 52,
              child: _SmallButton(
                icon: _moments
                    ? Icons.photo_camera_rounded
                    : Icons.photo_camera_outlined,
                tooltip: _moments ? 'Hide quest moments' : 'Show quest moments',
                active: _moments,
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => _moments = !_moments);
                },
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
                _flyToPoint(point, math.max(_map.camera.zoom, 15));
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
                        // Above the shell, so the floating nav pill never covers the sheet.
                        useRootNavigator: true,
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
                '© OpenStreetMap contributors',
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
    });
    if (code == null) {
      _flyToPoint(_world, _worldZoom + 0.6);
      return;
    }
    final everyPlace =
        ref.read(mapPlacesProvider(mapAllPlacesFilter)).valueOrNull ??
            const <MapPlace>[];
    final navInset = MediaQuery.of(context).padding.bottom * 0.30 + 78;
    _flyToPoints(
      [
        for (final p in everyPlace)
          if (p.countryCode == code) LatLng(p.latitude, p.longitude),
      ],
      navInset,
      maxZoom: 10,
    );
  }

  /// A badge tap: select the country and travel to its places.
  void _travelTo(MapCountry c, List<MapPlace> everyPlace, double navInset) {
    HapticFeedback.selectionClick();
    _introPending = false;
    _introTimer?.cancel();
    setState(() {
      _country = c.code;
      _follow = false;
    });
    final points = [
      for (final p in everyPlace)
        if (p.countryCode == c.code) LatLng(p.latitude, p.longitude),
    ];
    if (points.isEmpty) {
      _flyToPoint(_countryAnchor(c, everyPlace, null), 6);
    } else {
      _flyToPoints(points, navInset, maxZoom: 10);
    }
  }

  Future<void> _openFilters() {
    HapticFeedback.selectionClick();
    return showModalBottomSheet<void>(
      context: context,
      // Above the shell, so the floating nav pill never covers the sheet.
      useRootNavigator: true,
      useSafeArea: true,
      backgroundColor: QuestColors.osBg,
      builder: (sheetContext) => _FilterSheet(
        category: _category,
        savedOnly: _savedOnly,
        status: _status,
        onCategory: (value) => setState(() => _category = value),
        onSavedOnly: (value) => setState(() => _savedOnly = value),
        onStatus: (value) => setState(() => _status = value),
        onLegend: () {
          Navigator.pop(sheetContext);
          showModalBottomSheet<void>(
              context: context,
              // Above the shell, so the floating nav pill never covers the sheet.
              useRootNavigator: true,
              isScrollControlled: true,
              useSafeArea: true,
              backgroundColor: QuestColors.osBg,
              builder: (_) => const MapLegend());
        },
      ),
    );
  }

  Future<void> _openDiscover(String code) {
    HapticFeedback.selectionClick();
    return showModalBottomSheet<void>(
      context: context,
      // Above the shell, so the floating nav pill never covers the sheet.
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: QuestColors.osBg,
      builder: (_) => _DiscoverSheet(
        code: code,
        onQuest: (snippet) {
          // Frame the place under the sheet; the quest itself opens through
          // the normal quest details → BSHEEEL flow, like everywhere else.
          _flyToPoint(LatLng(snippet.latitude, snippet.longitude),
              math.max(_map.camera.zoom, 13));
          context.pushNamed(RouteNames.questDetails,
              pathParameters: {'id': snippet.id});
        },
      ),
    );
  }

  /// Where a moment's tile sits: its place's point, nudged by the metres
  /// its own id decides.
  ///
  /// Several people completing quests at one landmark all carry that
  /// landmark's coordinate — the only location Bsheel holds — so without the
  /// nudge they stack into a single square and the map says one person went.
  /// The offset is a presentation device and nothing else: it is derived
  /// from the submission id rather than from anything about the person, it
  /// never leaves the place's own radius, and it is stable, because a tile
  /// that drifted between frames would read as somebody moving.
  LatLng _scatter(MapMoment moment) {
    final offset = moment.scatterOffset;
    // Metres to degrees. Longitude degrees shrink towards the poles, which
    // matters even across one country: an unadjusted offset elongates the
    // scatter east-west the further north a place is.
    const metresPerDegreeLat = 111320.0;
    final metresPerDegreeLng =
        metresPerDegreeLat * math.cos(moment.latitude * math.pi / 180);
    return LatLng(
      moment.latitude + offset.north / metresPerDegreeLat,
      moment.longitude +
          (metresPerDegreeLng.abs() < 1 ? 0 : offset.east / metresPerDegreeLng),
    );
  }

  /// Opens the moment itself — the picture or the video — with the quest
  /// behind it offered on the same screen.
  ///
  /// A pin answers "what can I do here"; a moment answers "what did somebody
  /// actually do", and the two want different screens. Tapping a photograph
  /// and being shown a list of quest titles loses the thing that was tapped.
  /// So this plays the proof and puts DO THIS QUEST under it: the picture is
  /// the pitch, the button is the answer to it.
  ///
  /// Everything else at the same place is one tap further on, which is what
  /// the card's "+N more" refers to.
  Future<void> _openMoment(MapMoment moment) async {
    HapticFeedback.lightImpact();
    final places = [
      ...(ref.read(mapPlacesProvider(_filter)).valueOrNull ??
          const <MapPlace>[]),
      ...(ref.read(mapPlacesProvider(mapAllPlacesFilter)).valueOrNull ??
          const <MapPlace>[]),
    ];
    final place = places.where((p) => p.id == moment.placeId).firstOrNull;
    await showModalBottomSheet<void>(
      context: context,
      // Above the shell, so the floating nav pill never covers the sheet.
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: QuestColors.osBg,
      builder: (_) => _MomentSheet(
        moment: moment,
        // Null when a filter has hidden the pin: the sheet then drops the
        // "see everything here" row rather than offering a dead tap.
        place: place,
        onOpenPlace: place == null
            ? null
            : () {
                Navigator.pop(context);
                _openPlace(place);
              },
      ),
    );
    if (mounted) ref.invalidate(mapMomentsProvider(_country));
  }

  Future<void> _openPlace(MapPlace place) async {
    HapticFeedback.lightImpact();
    setState(() => _follow = false);
    _flyToPoint(LatLng(place.latitude, place.longitude),
        math.max(_map.camera.zoom, place.locked ? 11 : 14),
        duration: const Duration(milliseconds: 700));
    await showModalBottomSheet<void>(
        context: context,
        // Above the shell, so the floating nav pill never covers the sheet.
        useRootNavigator: true,
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
        // Above the shell, so the floating nav pill never covers the sheet.
        useRootNavigator: true,
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

// ── The board: grey world, country grids, colour earned back ────────────────
//
// The whole planet sits under one grey veil. A country that has quests is
// divided into a grid of cells drawn over the veil; every cell holding a
// place where the player has an APPROVED quest is cut out of the veil, so
// the real map colour shows through there — square by square, the country
// comes back. Once every place in the country is confirmed, the veil is cut
// along the country's real border and the grid disappears: the country is
// won. Nothing here decides anything — `confirmed` comes from the server's
// exploration model, this only draws it.

/// Veil over everything. Cells and finished countries are its holes.
const _veilRing = [
  LatLng(-85, -180),
  LatLng(-85, 180),
  LatLng(85, 180),
  LatLng(85, -180),
];

List<Polygon> _boardPolygons(
  List<CountryGeometry> geometry,
  List<MapCountry> countries,
  List<MapPlace> everyPlace,
) {
  final byGeometryId = {for (final c in countries) c.geometryId: c};
  final holes = <List<LatLng>>[];
  final overlays = <Polygon>[];

  for (final shape in geometry) {
    final country = byGeometryId[shape.id];
    if (country == null || country.total == 0) continue;
    final rings = [
      for (final r in shape.rings)
        if (r.length >= 4) r
    ];
    if (rings.isEmpty) continue;
    final won = country.confirmed >= country.total;

    // The border, always: this is a country in play.
    for (final ring in rings) {
      final points = [for (final o in ring) LatLng(o.dy, o.dx)];
      overlays.add(Polygon(
        points: points,
        color: won
            ? QuestColors.osSuccess.withAlpha(36)
            : QuestColors.osPrimary.withAlpha(22),
        borderColor: won ? QuestColors.osSuccess : QuestColors.osTextPrimary,
        borderStrokeWidth: won ? 2.5 : 1.5,
      ));
      if (won) holes.add(points);
    }
    if (won) continue;

    // The grid, only for what is still to be won.
    final places =
        everyPlace.where((p) => p.countryCode == country.code).toList();
    for (final cell in _gridCells(rings, places)) {
      final ring = cell.ring;
      if (cell.revealed) {
        holes.add(ring);
        overlays.add(Polygon(
          points: ring,
          color: QuestColors.osSuccess.withAlpha(40),
          borderColor: QuestColors.osSuccess,
          borderStrokeWidth: 2,
        ));
      } else {
        overlays.add(Polygon(
          points: ring,
          color: QuestColors.osTextPrimary.withAlpha(0),
          borderColor: QuestColors.osTextPrimary.withAlpha(70),
          borderStrokeWidth: 0.8,
        ));
      }
    }
  }

  return [
    Polygon(
      points: _veilRing,
      holePointsList: holes,
      color: QuestColors.osTextPrimary.withAlpha(120),
      borderStrokeWidth: 0,
    ),
    ...overlays,
  ];
}

class _Cell {
  const _Cell(this.ring, this.revealed);
  final List<LatLng> ring;
  final bool revealed;
}

/// Squares laid over the country's bounding box, kept where they touch the
/// country (centre inside a ring, or a place inside the square). The step
/// adapts to the country so Lebanon gets a handful of cells and Egypt does
/// not get thousands; a cell is revealed when it holds a confirmed place.
Iterable<_Cell> _gridCells(List<List<Offset>> rings, List<MapPlace> places) {
  var minX = double.infinity, minY = double.infinity;
  var maxX = -double.infinity, maxY = -double.infinity;
  for (final ring in rings) {
    for (final o in ring) {
      if (o.dx < minX) minX = o.dx;
      if (o.dx > maxX) maxX = o.dx;
      if (o.dy < minY) minY = o.dy;
      if (o.dy > maxY) maxY = o.dy;
    }
  }
  final span = math.max(maxX - minX, maxY - minY);
  final step = (span / 6).clamp(0.15, 2.0);
  final cells = <_Cell>[];
  final columns = ((maxX - minX) / step).ceil();
  final rowsCount = ((maxY - minY) / step).ceil();
  if (columns * rowsCount > 400) return cells;

  for (var i = 0; i < columns; i++) {
    for (var j = 0; j < rowsCount; j++) {
      final x0 = minX + i * step, y0 = minY + j * step;
      final x1 = x0 + step, y1 = y0 + step;
      bool inCell(MapPlace p) =>
          p.longitude >= x0 &&
          p.longitude < x1 &&
          p.latitude >= y0 &&
          p.latitude < y1;
      final hasPlace = places.any(inCell);
      if (!hasPlace && !_inside(Offset(x0 + step / 2, y0 + step / 2), rings)) {
        continue;
      }
      cells.add(_Cell(
        [LatLng(y0, x0), LatLng(y0, x1), LatLng(y1, x1), LatLng(y1, x0)],
        places.any((p) => p.confirmed && inCell(p)),
      ));
    }
  }
  return cells;
}

/// Even-odd point-in-polygon over every ring, so islands count and lakes do
/// not.
bool _inside(Offset point, List<List<Offset>> rings) {
  var inside = false;
  for (final ring in rings) {
    for (var i = 0, j = ring.length - 1; i < ring.length; j = i++) {
      final a = ring[i], b = ring[j];
      if ((a.dy > point.dy) != (b.dy > point.dy) &&
          point.dx < (b.dx - a.dx) * (point.dy - a.dy) / (b.dy - a.dy) + a.dx) {
        inside = !inside;
      }
    }
  }
  return inside;
}

/// Where a country's badge sits: the middle of its places, which is where
/// the quests are — a bounding-box centre would put Egypt's badge in the
/// desert. Falls back to the geometry's centre when no places are loaded.
LatLng _countryAnchor(
  MapCountry c,
  List<MapPlace> everyPlace,
  List<CountryGeometry>? geometry,
) {
  var n = 0;
  var lat = 0.0, lng = 0.0;
  for (final p in everyPlace) {
    if (p.countryCode != c.code) continue;
    n++;
    lat += p.latitude;
    lng += p.longitude;
  }
  if (n > 0) return LatLng(lat / n, lng / n);
  final shape = geometry?.where((g) => g.id == c.geometryId).firstOrNull;
  if (shape == null) return _home;
  var count = 0;
  var x = 0.0, y = 0.0;
  for (final ring in shape.rings) {
    for (final o in ring) {
      count++;
      x += o.dx;
      y += o.dy;
    }
  }
  return count == 0 ? _home : LatLng(y / count, x / count);
}

/// One country on the world view: flag, name, and how much of it is won.
/// Tap to travel there.
class _CountryBadge extends StatelessWidget {
  const _CountryBadge({required this.country, required this.onTap});
  final MapCountry country;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = country;
    final won = c.total > 0 && c.confirmed >= c.total;
    final fraction =
        c.total == 0 ? 0.0 : (c.confirmed / c.total).clamp(0.0, 1.0);
    return Semantics(
      button: true,
      label: '${c.name}, ${c.confirmed} of ${c.total} places explored',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        // Centred in its marker box so a short name and a long one both
        // sit on the anchor; the name ellipsises rather than overflowing.
        child: Center(
          child: Container(
            padding: const EdgeInsets.fromLTRB(8, 5, 10, 5),
            decoration: BoxDecoration(
              color: won ? QuestColors.osSuccess : QuestColors.osCard,
              borderRadius: BorderRadius.circular(QuestSpacing.radiusFull),
              border: Border.all(
                  color: QuestColors.osTextPrimary,
                  width: QuestSpacing.cardBorderWidth),
              boxShadow: QuestSpacing.shadowSm,
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(_flag(c.code),
                  style: const TextStyle(fontSize: 18, height: 1)),
              const SizedBox(width: 6),
              Flexible(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      c.name.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: QuestTypography.osLabelMedium.copyWith(
                        fontSize: 10,
                        height: 1,
                        color: won
                            ? QuestColors.onAccent(QuestColors.osSuccess)
                            : QuestColors.osTextPrimary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    SizedBox(
                      width: 44,
                      child: ArcadeMeter(
                        progress: fraction,
                        fill: won ? QuestColors.osCard : QuestColors.osSuccess,
                        height: 5,
                      ),
                    ),
                  ],
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
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

/// The moment itself: the proof, then the quest that produced it.
///
/// This is what a card on the map opens into, and the order is the argument.
/// The picture or the video comes first at full width, because that is what
/// was tapped and what makes somebody want the quest. DO THIS QUEST sits
/// directly under it, so the gap between "that looks worth doing" and having
/// it assigned is one button rather than a hunt through a list.
///
/// A video plays here rather than sending the player to the feed: being
/// bounced to another screen to watch the thing you just tapped is how the
/// invitation gets lost. The full post — votes, comments, report — is still
/// one tap away, because those rules live in one place and are not
/// reimplemented here.
class _MomentSheet extends ConsumerStatefulWidget {
  const _MomentSheet({
    required this.moment,
    required this.place,
    required this.onOpenPlace,
  });

  final MapMoment moment;

  /// Null when the place is filtered off the board; the "everything here"
  /// row is then dropped rather than offering a tap that goes nowhere.
  final MapPlace? place;
  final VoidCallback? onOpenPlace;

  @override
  ConsumerState<_MomentSheet> createState() => _MomentSheetState();
}

class _MomentSheetState extends ConsumerState<_MomentSheet> {
  VideoPlayerController? _video;
  bool _videoReady = false;
  bool _videoFailed = false;
  bool _taking = false;

  @override
  void initState() {
    super.initState();
    if (widget.moment.isVideo && widget.moment.mediaUrl.isNotEmpty) {
      final controller =
          VideoPlayerController.networkUrl(Uri.parse(widget.moment.mediaUrl));
      _video = controller;
      controller.initialize().then((_) {
        if (!mounted) return;
        // Looping and muted: this is a preview inside a sheet, not the feed.
        // Sound that starts itself under somebody's thumb on a map is a
        // surprise, and the post is where watching it properly happens.
        controller
          ..setLooping(true)
          ..setVolume(0)
          ..play();
        setState(() => _videoReady = true);
      }).catchError((Object _) {
        if (mounted) setState(() => _videoFailed = true);
      });
    }
  }

  @override
  void dispose() {
    _video?.dispose();
    super.dispose();
  }

  Future<void> _doQuest() async {
    final user = ref.read(authSessionProvider);
    if (user == null) return;
    setState(() => _taking = true);
    try {
      await assignQuestFlow(
        context: context,
        ref: ref,
        questId: widget.moment.questId,
        questTitle: widget.moment.questTitle,
        userId: user.id,
      );
    } finally {
      if (mounted) setState(() => _taking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final moment = widget.moment;
    final signedIn = ref.watch(authSessionProvider) != null;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.72,
      minChildSize: 0.45,
      maxChildSize: 0.95,
      builder: (context, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        children: [
          Row(children: [
            _AuthorRing(avatarUrl: moment.avatarUrl, username: moment.username),
            const SizedBox(width: 10),
            Expanded(
              child: Text('@${moment.username}',
                  style: QuestTypography.osHeadlineSmall,
                  overflow: TextOverflow.ellipsis),
            ),
            IconButton(
              tooltip: 'Close',
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close),
            ),
          ]),
          const SizedBox(height: 10),
          // The proof, at full width. 4:5 because that is the shape most
          // phone photos and clips arrive in; BoxFit.cover keeps the frame
          // honest rather than letterboxing every one of them.
          AspectRatio(
            aspectRatio: 4 / 5,
            child: Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: QuestColors.category(moment.questCategory),
                borderRadius: BorderRadius.circular(QuestSpacing.radiusPanel),
                border: Border.all(
                    color: QuestColors.osTextPrimary,
                    width: QuestSpacing.cardBorderWidth),
                boxShadow: QuestSpacing.shadowSm,
              ),
              child: _media(moment),
            ),
          ),
          const SizedBox(height: 14),
          Text(moment.questTitle.toUpperCase(),
              style: QuestTypography.osDisplaySmall),
          const SizedBox(height: 4),
          Text(
            '${moment.placeName}'
            '${moment.city.isEmpty ? '' : ' · ${moment.city}'}'
            ' · ${moment.questCategory.toUpperCase()}',
            style: QuestTypography.osLabelSmall
                .copyWith(color: QuestColors.osTextSecondary),
          ),
          if (moment.caption.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(moment.caption, style: QuestTypography.osBodyMedium),
          ],
          const SizedBox(height: 16),
          // The answer to the picture.
          ArcadeButton(
            label: _taking ? 'TAKING…' : 'DO THIS QUEST',
            icon: Icons.flag_rounded,
            isLoading: _taking,
            onTap: (!signedIn || _taking) ? null : _doQuest,
          ),
          const SizedBox(height: 12),
          ArcadeButton(
            label: 'OPEN POST',
            icon: Icons.chat_bubble_outline,
            variant: ArcadeButtonVariant.ghost,
            onTap: () {
              Navigator.pop(context);
              context.pushNamed(RouteNames.feedPostDetails,
                  pathParameters: {'id': moment.id});
            },
          ),
          if (widget.onOpenPlace != null) ...[
            const SizedBox(height: 12),
            ArcadeButton(
              label: moment.moreCount > 0
                  ? 'SEE ALL ${moment.moreCount + 1} AT ${moment.placeName.toUpperCase()}'
                  : 'EVERYTHING AT ${moment.placeName.toUpperCase()}',
              icon: Icons.place_rounded,
              variant: ArcadeButtonVariant.ghost,
              onTap: widget.onOpenPlace,
            ),
          ],
        ],
      ),
    );
  }

  Widget _media(MapMoment moment) {
    if (!moment.isVideo) {
      if (moment.mediaUrl.isEmpty) {
        return const Center(child: Text('📷', style: TextStyle(fontSize: 34)));
      }
      return CachedNetworkImage(
        imageUrl: moment.mediaUrl,
        fit: BoxFit.cover,
        placeholder: (_, __) =>
            const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        errorWidget: (_, __, ___) =>
            const Center(child: Text('📷', style: TextStyle(fontSize: 34))),
      );
    }
    if (_videoFailed || moment.mediaUrl.isEmpty) {
      // Says what happened instead of spinning forever on a clip that will
      // never arrive — the quest below is still takeable either way.
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text(
              'This clip could not be loaded. Open the post to try again.',
              textAlign: TextAlign.center),
        ),
      );
    }
    final video = _video;
    if (!_videoReady || video == null) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: video.value.size.width,
            height: video.value.size.height,
            child: VideoPlayer(video),
          ),
        ),
        // Muted by default, so say so and let it be turned up here rather
        // than only in the post.
        Positioned(
          right: 8,
          bottom: 8,
          child: _MuteToggle(controller: video),
        ),
      ],
    );
  }
}

/// Sound toggle for the moment sheet's clip.
class _MuteToggle extends StatefulWidget {
  const _MuteToggle({required this.controller});
  final VideoPlayerController controller;

  @override
  State<_MuteToggle> createState() => _MuteToggleState();
}

class _MuteToggleState extends State<_MuteToggle> {
  bool _muted = true;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: _muted ? 'Unmute' : 'Mute',
      child: GestureDetector(
        onTap: () {
          setState(() => _muted = !_muted);
          widget.controller.setVolume(_muted ? 0 : 1);
        },
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: QuestColors.osCard,
            shape: BoxShape.circle,
            border: Border.all(
                color: QuestColors.osTextPrimary,
                width: QuestSpacing.cardBorderWidth),
          ),
          child: Icon(_muted ? Icons.volume_off : Icons.volume_up, size: 18),
        ),
      ),
    );
  }
}

/// One piece of proof from the feed, as a card on the map.
///
/// The Snap/Instagram-map shape: the media fills a rounded card, the author
/// rides in a ring on its corner, and everything else standing at the same
/// place is summarised underneath as "+N more" rather than drawn as more
/// cards. One place, one card — a landmark with two hundred completions
/// cannot bury the rest of the board.
///
/// The difference from those maps, and it is the point: this is not a
/// postcard, it is an **invitation**. Tapping it opens the place, where the
/// quest that produced the picture can be taken. That is why the card
/// carries the quest count — somebody did something here that you can go
/// and do.
///
/// The coordinate is the **place's**, not the photographer's. Bsheel does
/// not store where a photograph was taken, and the one source that could
/// approximate it is telecom verification somebody consented to for a
/// single quest.
///
/// A photo draws itself. A video draws its category tint and a play glyph:
/// there are no server-side poster frames yet, and decoding one per marker
/// would mean a video decoder per card on a map being panned.
class _MomentTile extends StatelessWidget {
  const _MomentTile({required this.moment, required this.onTap});
  final MapMoment moment;
  final VoidCallback onTap;

  static const double _cardW = 54;
  static const double _cardH = 66;

  /// What to draw in the square: the photo itself, or a video's poster
  /// frame. Empty means there is nothing to draw and the tile falls back to
  /// the category tint behind it.
  String get _picture =>
      moment.isVideo ? (moment.posterUrl ?? '') : moment.mediaUrl;

  @override
  Widget build(BuildContext context) {
    final tint = QuestColors.category(moment.questCategory);
    final more = moment.moreCount;
    final semantics = [
      '${moment.isVideo ? 'Video' : 'Photo'} proof by ${moment.username}',
      'at ${moment.placeName}',
      if (more > 0) 'and $more more',
      if (moment.questCount > 0)
        '${moment.questCount} quest${moment.questCount == 1 ? '' : 's'} here',
    ].join(', ');

    return Tooltip(
      message:
          '${moment.placeName} · ${moment.questTitle} · @${moment.username}'
          '${more > 0 ? ' · +$more more' : ''}',
      child: Semantics(
        button: true,
        label: semantics,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: _cardW,
                    height: _cardH,
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: tint,
                      borderRadius:
                          BorderRadius.circular(QuestSpacing.radiusPanel),
                      border: Border.all(
                          color: QuestColors.osTextPrimary,
                          width: QuestSpacing.cardBorderWidth),
                      boxShadow: QuestSpacing.shadowSm,
                    ),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        // One picture rule for both kinds: a photo shows
                        // itself, a video shows the frame the backend cut
                        // from it. A video without a poster yet — not
                        // decoded, or no ffmpeg where it was uploaded —
                        // falls back to the tint, which is what every video
                        // tile used to be.
                        if (_picture.isNotEmpty)
                          CachedNetworkImage(
                            imageUrl: _picture,
                            fit: BoxFit.cover,
                            memCacheWidth: (_cardW * 3).round(),
                            placeholder: (_, __) => const SizedBox.shrink(),
                            errorWidget: (_, __, ___) => Center(
                                child: Text(moment.isVideo ? '🎬' : '📷')),
                          ),
                        if (_picture.isEmpty)
                          Center(child: Text(moment.isVideo ? '🎬' : '📷')),
                        // The glyph stays on a video even with a poster —
                        // it is what says "this one moves". Over a real
                        // frame it needs a scrim to stay legible, which a
                        // flat tint never required.
                        if (moment.isVideo)
                          Center(
                            child: Container(
                              width: 26,
                              height: 26,
                              decoration: BoxDecoration(
                                color: QuestColors.osCard.withAlpha(215),
                                shape: BoxShape.circle,
                                border: Border.all(
                                    color: QuestColors.osTextPrimary,
                                    width: 1.5),
                              ),
                              child: const Icon(Icons.play_arrow_rounded,
                                  size: 16, color: QuestColors.osTextPrimary),
                            ),
                          ),
                        // A quest waiting here, marked on the card: the
                        // picture is the invitation, this is the promise
                        // there is something to accept.
                        if (moment.questCount > 0)
                          Positioned(
                            top: 3,
                            right: 3,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 4, vertical: 1),
                              decoration: BoxDecoration(
                                color: QuestColors.osCard,
                                borderRadius: BorderRadius.circular(
                                    QuestSpacing.radiusFull),
                                border: Border.all(
                                    color: QuestColors.osTextPrimary, width: 1),
                              ),
                              child: Text('⚑${moment.questCount}',
                                  style: QuestTypography.osLabelSmall
                                      .copyWith(fontSize: 8, height: 1)),
                            ),
                          ),
                      ],
                    ),
                  ),
                  // The author's ring, the way the reference maps do it —
                  // proof belongs to a person, and the face is what makes it
                  // read as somebody's rather than as stock photography.
                  Positioned(
                    left: -6,
                    bottom: -6,
                    child: _AuthorRing(
                        avatarUrl: moment.avatarUrl, username: moment.username),
                  ),
                ],
              ),
              if (more > 0) ...[
                const SizedBox(height: 7),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: QuestColors.osCard,
                    borderRadius:
                        BorderRadius.circular(QuestSpacing.radiusFull),
                    border:
                        Border.all(color: QuestColors.osTextPrimary, width: 1),
                  ),
                  child: Text('+$more more',
                      style: QuestTypography.osLabelSmall
                          .copyWith(fontSize: 9, height: 1.1)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The avatar ring on a moment card. Falls back to the first letter of the
/// username, because a missing picture must not leave a hole where the
/// author should be.
class _AuthorRing extends StatelessWidget {
  const _AuthorRing({required this.avatarUrl, required this.username});
  final String? avatarUrl;
  final String username;

  @override
  Widget build(BuildContext context) {
    final initial =
        username.isEmpty ? '?' : username.substring(0, 1).toUpperCase();
    return Container(
      width: 22,
      height: 22,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: QuestColors.osCard,
        shape: BoxShape.circle,
        border: Border.all(color: QuestColors.osTextPrimary, width: 1.5),
        boxShadow: QuestSpacing.shadowSm,
      ),
      alignment: Alignment.center,
      child: avatarUrl == null || avatarUrl!.isEmpty
          ? Text(initial,
              style: QuestTypography.osLabelSmall
                  .copyWith(fontSize: 10, height: 1))
          : CachedNetworkImage(
              imageUrl: avatarUrl!,
              fit: BoxFit.cover,
              width: 22,
              height: 22,
              memCacheWidth: 66,
              placeholder: (_, __) => const SizedBox.shrink(),
              errorWidget: (_, __, ___) => Text(initial,
                  style: QuestTypography.osLabelSmall
                      .copyWith(fontSize: 10, height: 1)),
            ),
    );
  }
}

class _PinGlyph extends StatelessWidget {
  const _PinGlyph({required this.place, required this.size});
  final MapPlace place;
  final double size;

  @override
  Widget build(BuildContext context) {
    final tint = _pinColor(place);
    final cover = place.locked ? null : place.coverMediaUrl;
    final emoji = Text(
      _pinEmoji(place),
      style: TextStyle(fontSize: size * 0.5, height: 1),
    );
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: tint,
        borderRadius: BorderRadius.circular(QuestSpacing.radiusPanel),
        border: Border.all(
            color: QuestColors.osTextPrimary,
            width: QuestSpacing.cardBorderWidth),
        boxShadow: QuestSpacing.shadowSm,
      ),
      alignment: Alignment.center,
      // A place someone has actually been to shows their proof as a photo
      // snippet, with the state emoji tucked in the corner; the rest keep
      // the emoji badge.
      child: cover == null
          ? emoji
          : Stack(
              fit: StackFit.expand,
              children: [
                CachedNetworkImage(
                  imageUrl: cover,
                  fit: BoxFit.cover,
                  memCacheWidth: (size * 3).round(),
                  placeholder: (_, __) => Center(child: emoji),
                  errorWidget: (_, __, ___) => Center(child: emoji),
                ),
                Positioned(
                  right: 1,
                  bottom: 1,
                  child: Text(
                    _pinEmoji(place),
                    style: TextStyle(fontSize: size * 0.3, height: 1),
                  ),
                ),
              ],
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
    // Approved, unique places only — the same arithmetic as the backend's
    // exploration model, so this chip, the sheet and the profile agree.
    final total = countries.fold(0, (n, c) => n + c.total);
    final explored = countries.fold(0, (n, c) => n + c.confirmed);
    final fraction = total == 0 ? 0.0 : (explored / total).clamp(0.0, 1.0);
    return Semantics(
      button: true,
      label: 'Exploration progress, $explored of $total',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: _Panel(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Text('🏆', style: TextStyle(fontSize: 14, height: 1)),
            const SizedBox(width: 6),
            Text('$explored/$total',
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
    required this.status,
    required this.onCategory,
    required this.onSavedOnly,
    required this.onStatus,
    required this.onLegend,
  });
  final String? category;
  final bool savedOnly;
  final String status;
  final ValueChanged<String?> onCategory;
  final ValueChanged<bool> onSavedOnly;
  final ValueChanged<String> onStatus;
  final VoidCallback onLegend;

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late String? _category = widget.category;
  late bool _savedOnly = widget.savedOnly;
  late String _status = widget.status;

  static const _statuses = <String, String>{
    'all': 'EVERYTHING',
    'available': '🎯 AVAILABLE',
    'completed': '🏆 COMPLETED',
  };

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
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final entry in _statuses.entries)
                _OptionChip(
                  label: entry.value,
                  selected: _status == entry.key,
                  onTap: () {
                    setState(() => _status = entry.key);
                    widget.onStatus(entry.key);
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

/// "DISCOVER LEBANON" — the door to a country's quests, shown once a country
/// chip is picked.
class _DiscoverButton extends StatelessWidget {
  const _DiscoverButton({
    required this.flag,
    required this.name,
    required this.onTap,
  });
  final String flag;
  final String name;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Discover $name',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: QuestColors.osAccent,
            borderRadius: BorderRadius.circular(QuestSpacing.radiusButton),
            border: Border.all(
                color: QuestColors.osTextPrimary,
                width: QuestSpacing.cardBorderWidth),
            boxShadow: QuestSpacing.shadowSm,
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(flag, style: const TextStyle(fontSize: 14, height: 1)),
            const SizedBox(width: 6),
            Text(
              'DISCOVER ${name.toUpperCase()}',
              style: QuestTypography.osLabelMedium.copyWith(
                fontSize: 11,
                height: 1,
                letterSpacing: 1,
                color: QuestColors.onAccent(QuestColors.osAccent),
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.arrow_forward_rounded,
                size: 16, color: QuestColors.onAccent(QuestColors.osAccent)),
          ]),
        ),
      ),
    );
  }
}

/// A country as seen from anywhere: its exploration, what is trending, a
/// few discovery picks, how much is still hidden, and the journeys through
/// it. Every number here came from the server.
class _DiscoverSheet extends ConsumerWidget {
  const _DiscoverSheet({required this.code, required this.onQuest});
  final String code;
  final ValueChanged<MapQuestSnippet> onQuest;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(mapDiscoverProvider(code));
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (sheetContext, scroll) => async.when(
        loading: () => ListView(
          controller: scroll,
          padding: const EdgeInsets.all(20),
          children: const [ArcadeSkeletonList(itemCount: 4, itemHeight: 84)],
        ),
        error: (_, __) => ListView(
          controller: scroll,
          padding: const EdgeInsets.all(20),
          children: [
            _Retry(
                message: 'Could not load this country.',
                onRetry: () => ref.invalidate(mapDiscoverProvider(code))),
          ],
        ),
        data: (d) {
          void open(MapQuestSnippet q) {
            Navigator.pop(sheetContext);
            onQuest(q);
          }

          return ListView(
            controller: scroll,
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
            children: [
              Row(children: [
                Text(_flag(d.code),
                    style: const TextStyle(fontSize: 26, height: 1)),
                const SizedBox(width: 10),
                Expanded(
                    child: Text(d.name.toUpperCase(),
                        style: QuestTypography.osDisplaySmall)),
                Text('${d.percentage.round()}%',
                    style: QuestTypography.osDisplaySmall
                        .copyWith(color: QuestColors.osSuccessText)),
              ]),
              const SizedBox(height: 8),
              ArcadeMeter(
                  progress: d.totalPlaces == 0
                      ? 0
                      : (d.exploredPlaces / d.totalPlaces).clamp(0.0, 1.0),
                  fill: QuestColors.osSuccess,
                  height: 10),
              const SizedBox(height: 6),
              Text(
                '${d.exploredPlaces} OF ${d.totalPlaces} PLACES EXPLORED'
                '${d.hiddenCount > 0 ? ' · 🔒 ${d.hiddenCount} HIDDEN' : ''}',
                style: QuestTypography.osLabelSmall
                    .copyWith(color: QuestColors.osTextSecondary),
              ),
              if (d.trending.isEmpty && d.discovery.isEmpty) ...[
                const SizedBox(height: 24),
                Text(
                  d.totalPlaces == 0
                      ? 'No quest places published here yet.'
                      : 'Nothing to show yet — every quest here is still hidden.',
                  style: QuestTypography.osBodyMedium,
                ),
              ],
              if (d.trending.isNotEmpty) ...[
                const SizedBox(height: 18),
                Text('🔥 TRENDING', style: QuestTypography.osHeadlineMedium),
                const SizedBox(height: 8),
                for (final q in d.trending)
                  QuestImpression(
                    questId: q.id,
                    surface: AnalyticsSurfaces.country,
                    child: _SnippetCard(
                        snippet: q, trending: true, onTap: () => open(q)),
                  ),
              ],
              if (d.discovery.isNotEmpty) ...[
                const SizedBox(height: 18),
                Text('🎲 DISCOVER', style: QuestTypography.osHeadlineMedium),
                const SizedBox(height: 8),
                for (final q in d.discovery)
                  QuestImpression(
                    questId: q.id,
                    surface: AnalyticsSurfaces.country,
                    child: _SnippetCard(
                        snippet: q, trending: false, onTap: () => open(q)),
                  ),
              ],
              if (d.collections.isNotEmpty) ...[
                const SizedBox(height: 18),
                Text('🧭 JOURNEYS', style: QuestTypography.osHeadlineMedium),
                const SizedBox(height: 8),
                for (final c in d.collections)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: ArcadeCard(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Expanded(
                                child: Text(c.name,
                                    style: QuestTypography.osHeadlineSmall)),
                            Text('${c.completed}/${c.total}',
                                style: QuestTypography.osHeadlineSmall),
                          ]),
                          if (c.description.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(c.description,
                                style: QuestTypography.osBodySmall.copyWith(
                                    color: QuestColors.osTextSecondary)),
                          ],
                          const SizedBox(height: 8),
                          ArcadeMeter(
                              progress: c.total == 0
                                  ? 0
                                  : (c.completed / c.total).clamp(0.0, 1.0),
                              fill: QuestColors.osPrimary,
                              height: 8),
                        ],
                      ),
                    ),
                  ),
              ],
              if (d.hiddenCount > 0) ...[
                const SizedBox(height: 10),
                Text(
                  '🔒 ${d.hiddenCount} hidden quest${d.hiddenCount == 1 ? '' : 's'} in ${d.name}. '
                  'Finish quests nearby and get them approved to reveal them.',
                  style: QuestTypography.osBodySmall
                      .copyWith(color: QuestColors.osTextSecondary),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// A quest on the country sheet: proof photo (or the category badge), title,
/// place, and the social signals that put it there. Tap → quest details.
class _SnippetCard extends StatelessWidget {
  const _SnippetCard({
    required this.snippet,
    required this.trending,
    required this.onTap,
  });
  final MapQuestSnippet snippet;
  final bool trending;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final q = snippet;
    final emoji = q.completed
        ? '🏆'
        : switch (q.category) {
            'landmark' => '🏰',
            'culture' => '🎭',
            'pilgrimage' => '🧭',
            'heritage' => '🏛️',
            _ => '⭐',
          };
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: ArcadeCard(
        onTap: onTap,
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          Container(
            width: 52,
            height: 52,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: trending ? QuestColors.osRed : QuestColors.osPrimary,
              borderRadius: BorderRadius.circular(QuestSpacing.radiusPanel),
              border: Border.all(
                  color: QuestColors.osTextPrimary,
                  width: QuestSpacing.cardBorderWidth),
            ),
            alignment: Alignment.center,
            child: q.coverMediaUrl == null
                ? Text(emoji, style: const TextStyle(fontSize: 24, height: 1))
                : CachedNetworkImage(
                    imageUrl: q.coverMediaUrl!,
                    fit: BoxFit.cover,
                    memCacheWidth: 160,
                    errorWidget: (_, __, ___) => Center(
                        child: Text(emoji,
                            style: const TextStyle(fontSize: 24, height: 1))),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(q.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: QuestTypography.osHeadlineSmall),
                const SizedBox(height: 3),
                Text(
                  '📍 ${q.placeName} · ${q.xp} XP'
                  '${q.completions > 0 ? ' · ${q.completions} done' : ''}'
                  '${q.saves > 0 ? ' · ${q.saves} saved' : ''}'
                  '${q.completed ? ' · YOU DID IT' : ''}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: QuestTypography.osLabelSmall
                      .copyWith(color: QuestColors.osTextSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          const Icon(Icons.chevron_right),
        ]),
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
    // Approved proof at unique places over every published place — the
    // backend's `map/progress/me` arithmetic. Pending proof is shown, but it
    // moves nothing until it is approved.
    final fraction = total == 0 ? 0.0 : confirmed / total;
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
          Text('$confirmed OF $total PLACES EXPLORED',
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
                                // What the map tile's "+N more" opens into:
                                // the proof standing here, as pictures. A
                                // grid of play buttons answered none of what
                                // somebody tapped a photograph to see.
                                if (detail.previews.isNotEmpty) ...[
                                  const SizedBox(height: 16),
                                  Text(
                                      'PROOF FROM HERE · ${detail.previews.length}',
                                      style: QuestTypography.osHeadlineMedium),
                                  const SizedBox(height: 8),
                                  SizedBox(
                                    height: 116,
                                    child: ListView.separated(
                                      scrollDirection: Axis.horizontal,
                                      itemCount: detail.previews.length,
                                      separatorBuilder: (_, __) =>
                                          const SizedBox(width: 10),
                                      itemBuilder: (context, i) => _ProofThumb(
                                        preview: detail.previews[i],
                                        onTap: () {
                                          Navigator.pop(context);
                                          context.pushNamed(
                                              RouteNames.feedPostDetails,
                                              pathParameters: {
                                                'id': detail.previews[i].id
                                              });
                                        },
                                      ),
                                    ),
                                  ),
                                ],
                              ])),
                ]));
  }
}

/// One piece of proof in the place sheet's strip.
///
/// Photo draws itself; video is a play card for the same reason the map tile
/// is — there are no poster frames yet. Tapping either opens the post, where
/// the video actually plays and the votes and comments live.
class _ProofThumb extends StatelessWidget {
  const _ProofThumb({required this.preview, required this.onTap});
  final MapPreview preview;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '${preview.isVideo ? 'Video' : 'Photo'} by ${preview.username}'
          '${preview.questTitle.isEmpty ? '' : ', ${preview.questTitle}'}',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 88,
              height: 92,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: QuestColors.osSurface,
                borderRadius: BorderRadius.circular(QuestSpacing.radiusPanel),
                border: Border.all(
                    color: QuestColors.osTextPrimary,
                    width: QuestSpacing.cardBorderWidth),
                boxShadow: QuestSpacing.shadowSm,
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (!preview.isVideo && preview.mediaUrl.isNotEmpty)
                    CachedNetworkImage(
                      imageUrl: preview.mediaUrl,
                      fit: BoxFit.cover,
                      memCacheWidth: 264,
                      placeholder: (_, __) => const SizedBox.shrink(),
                      errorWidget: (_, __, ___) =>
                          const Center(child: Text('📷')),
                    ),
                  if (preview.isVideo)
                    const Center(
                        child: Icon(Icons.play_circle_outline, size: 34)),
                  if (!preview.isVideo && preview.mediaUrl.isEmpty)
                    const Center(child: Text('📷')),
                ],
              ),
            ),
            const SizedBox(height: 4),
            SizedBox(
              width: 88,
              child: Text('@${preview.username}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: QuestTypography.osLabelSmall),
            ),
          ],
        ),
      ),
    );
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
                'The world starts grey. Countries with quests are drawn as a grid: '
                'finish a quest there and get it approved, and that square gets its '
                'colour back. Win every place in a country and the whole country '
                'lights up. Hidden pins within ${(_revealRadiusM / 1000).round()} km '
                'of an approved quest unlock too.',
                style: QuestTypography.osBodyMedium),
            const SizedBox(height: 12),
            for (final entry in {
              '🇱🇧 🇶🇦': 'A country in play — tap to travel there.',
              '▦': 'A square still grey: nothing approved here yet.',
              '🏰 🎭 🧭 🏛️': 'A place with quests you can start now.',
              '⏳': 'Your proof is in review.',
              '🏆': 'Approved — its square is in colour again.',
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
