import 'dart:async';
import 'dart:convert';
import 'package:app_core/app_core.dart';
import 'package:app_models/app_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/router/route_names.dart';
import '../data/map_providers.dart';
import '../domain/map_geometry.dart';

final mapGeometryProvider = FutureProvider<List<CountryGeometry>>((ref) async =>
    CountryGeometry.decode(
        jsonDecode(await rootBundle.loadString('assets/map/countries-50m.json'))
            as Map<String, dynamic>));

class MapPage extends ConsumerStatefulWidget {
  const MapPage({super.key});
  @override
  ConsumerState<MapPage> createState() => _MapPageState();
}

class _MapPageState extends ConsumerState<MapPage> {
  String? _country, _category;
  String _search = '';
  bool _savedOnly = false;
  int _offset = 0;
  Timer? _debounce;
  final _searchController = TextEditingController();
  final _transform = TransformationController();
  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _transform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final countries = ref.watch(mapCountriesProvider);
    final geometry = ref.watch(mapGeometryProvider);
    final filter = (
      country: _country,
      category: _category,
      search: _search,
      offset: _offset,
      savedOnly: _savedOnly
    );
    final places = ref.watch(mapPlacesProvider(filter));
    final countryRows = countries.valueOrNull ?? <MapCountry>[];
    final shapeIds = {for (final c in countryRows) c.code: c.geometryId};
    final shapes = (geometry.valueOrNull ?? <CountryGeometry>[])
        .where((g) =>
            g.id != '010' && (_country == null || g.id == shapeIds[_country]))
        .toList();
    final rows = (places.valueOrNull ?? <MapPlace>[])
        .where((p) => !_savedOnly || p.saved)
        .toList();
    return Scaffold(
        backgroundColor: QuestColors.osBg,
        body: SafeArea(
            bottom: false,
            child: RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(mapCountriesProvider);
                ref.invalidate(mapPlacesProvider);
                await ref.read(mapCountriesProvider.future);
              },
              child: ListView(padding: const EdgeInsets.all(18), children: [
                Row(children: [
                  Expanded(
                      child: Text('EXPLORE',
                          style: QuestTypography.osDisplayMedium)),
                  IconButton(
                      tooltip: 'Map legend',
                      onPressed: () => showModalBottomSheet<void>(
                          context: context,
                          isScrollControlled: true,
                          useSafeArea: true,
                          builder: (_) => const MapLegend()),
                      icon: const Icon(Icons.info_outline)),
                  IconButton(
                      tooltip: 'Search people and quests',
                      onPressed: () => context.pushNamed(RouteNames.search),
                      icon: const Icon(Icons.person_search_outlined)),
                ]),
                const SizedBox(height: 12),
                TextField(
                    controller: _searchController,
                    decoration: const InputDecoration(
                        hintText: 'Search a place, city or country',
                        prefixIcon: Icon(Icons.search)),
                    onChanged: (value) {
                      _debounce?.cancel();
                      _debounce = Timer(const Duration(milliseconds: 300), () {
                        if (mounted) {
                          setState(() {
                            _search = value;
                            _offset = 0;
                          });
                        }
                      });
                    }),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                    initialValue: _country ?? '',
                    decoration: const InputDecoration(labelText: 'MAP VIEW'),
                    items: [
                      const DropdownMenuItem(value: '', child: Text('WORLD')),
                      for (final c in countryRows)
                        DropdownMenuItem(
                            value: c.code, child: Text(c.name.toUpperCase()))
                    ],
                    onChanged: (value) => setState(() {
                          _country = value == '' ? null : value;
                          _offset = 0;
                          _transform.value = Matrix4.identity();
                        })),
                const SizedBox(height: 10),
                SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(children: [
                      for (final entry in <String?, String>{
                        null: 'ALL',
                        'landmark': 'LANDMARKS',
                        'culture': 'CULTURE',
                        'pilgrimage': 'ROUTES',
                        'heritage': 'HERITAGE',
                        'hidden': 'HIDDEN'
                      }.entries)
                        Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                                label: Text(entry.value),
                                selected: _category == entry.key,
                                onSelected: (_) => setState(() {
                                      _category = entry.key;
                                      _offset = 0;
                                    }))),
                    ])),
                const SizedBox(height: 12),
                Container(
                    height: 350,
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                        color: QuestColors.osCool.withAlpha(70),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                            color: QuestColors.osTextPrimary, width: 2)),
                    child: geometry.when(
                        loading: () =>
                            const Center(child: CircularProgressIndicator()),
                        error: (_, __) => _Retry(
                            message: 'Geography could not be loaded.',
                            onRetry: () => ref.invalidate(mapGeometryProvider)),
                        data: (_) =>
                            LayoutBuilder(builder: (context, constraints) {
                              final size = Size(
                                  constraints.maxWidth, constraints.maxHeight);
                              final projection = MapProjection(shapes, size);
                              return Stack(children: [
                                InteractiveViewer(
                                    transformationController: _transform,
                                    maxScale: 12,
                                    child: SizedBox.fromSize(
                                        size: size,
                                        child: Stack(children: [
                                          CustomPaint(
                                              size: size,
                                              painter: _GeographyPainter(
                                                  shapes,
                                                  projection,
                                                  countryRows,
                                                  _country)),
                                          for (final p in rows)
                                            Positioned(
                                                left:
                                                    projection.project(Offset(p.longitude, p.latitude)).dx -
                                                        22,
                                                top: projection.project(Offset(p.longitude, p.latitude)).dy -
                                                    22,
                                                child: IconButton.filled(
                                                    tooltip: p.name,
                                                    style: IconButton.styleFrom(
                                                        backgroundColor:
                                                            p.discovered
                                                                ? QuestColors
                                                                    .osSuccess
                                                                : QuestColors
                                                                    .osCard,
                                                        foregroundColor:
                                                            QuestColors
                                                                .osTextPrimary),
                                                    onPressed: () =>
                                                        _openPlace(p),
                                                    icon: Icon(p.saved
                                                        ? Icons.bookmark
                                                        : Icons
                                                            .place_outlined))),
                                        ]))),
                                Positioned(
                                    right: 6,
                                    top: 6,
                                    child: IconButton(
                                        tooltip: 'Reset map view',
                                        onPressed: () => setState(() =>
                                            _transform.value =
                                                Matrix4.identity()),
                                        icon: const Icon(
                                            Icons.center_focus_strong))),
                                Positioned(
                                    left: 10,
                                    bottom: 10,
                                    child: DecoratedBox(
                                        decoration: BoxDecoration(
                                            color: QuestColors.osBg,
                                            borderRadius:
                                                BorderRadius.circular(8)),
                                        child: const Padding(
                                            padding: EdgeInsets.all(6),
                                            child: Text(
                                                'NATURAL EARTH · PINCH TO ZOOM',
                                                style:
                                                    TextStyle(fontSize: 10))))),
                              ]);
                            }))),
                const SizedBox(height: 12),
                countries.when(
                    loading: () => const LinearProgressIndicator(),
                    error: (_, __) => _Retry(
                        message: 'Progress unavailable.',
                        onRetry: () => ref.invalidate(mapCountriesProvider)),
                    data: (data) => DiscoveryProgress(
                        countries: _country == null
                            ? data
                            : data.where((c) => c.code == _country).toList())),
                SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('SAVED PLACES'),
                    subtitle: const Text('Saving a place does not unlock it.'),
                    value: _savedOnly,
                    onChanged: (value) => setState(() {
                          _savedOnly = value;
                          _offset = 0;
                        })),
                places.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (_, __) => _Retry(
                        message: 'Places could not be loaded.',
                        onRetry: () =>
                            ref.invalidate(mapPlacesProvider(filter))),
                    data: (_) => Column(children: [
                          if (rows.isEmpty)
                            Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 24),
                                child: Text(_category == 'hidden'
                                    ? 'Hidden places appear after network location verification.'
                                    : 'No matching published places yet. Try another country or filter.')),
                          for (final p in rows)
                            Card(
                                child: ListTile(
                                    title: Text(p.name),
                                    subtitle: Text(
                                        '${p.category.toUpperCase()} · ${p.city}\n${p.questCount} QUESTS${p.discovered ? ' · DISCOVERED' : ''}'),
                                    isThreeLine: true,
                                    leading: Icon(p.discovered
                                        ? Icons.check_circle
                                        : Icons.place_outlined),
                                    trailing: Icon(p.saved
                                        ? Icons.bookmark
                                        : Icons.chevron_right),
                                    onTap: () => _openPlace(p))),
                          Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                TextButton(
                                    onPressed: _offset == 0
                                        ? null
                                        : () => setState(() => _offset -= 100),
                                    child: const Text('PREVIOUS')),
                                TextButton(
                                    onPressed:
                                        (places.valueOrNull?.length ?? 0) < 100
                                            ? null
                                            : () =>
                                                setState(() => _offset += 100),
                                    child: const Text('NEXT'))
                              ]),
                        ])),
              ]),
            )));
  }

  Future<void> _openPlace(MapPlace place) async {
    await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: QuestColors.osBg,
        builder: (_) => _PlaceSheet(place: place));
    if (mounted) {
      ref.invalidate(mapPlacesProvider);
      ref.invalidate(mapCountriesProvider);
    }
  }
}

class _GeographyPainter extends CustomPainter {
  _GeographyPainter(this.shapes, this.projection, this.progress, this.country);
  final List<CountryGeometry> shapes;
  final MapProjection projection;
  final List<MapCountry> progress;
  final String? country;
  @override
  void paint(Canvas canvas, Size size) {
    for (final shape in shapes) {
      final discovered =
          progress.any((c) => c.geometryId == shape.id && c.discovered > 0);
      final path = projection.path(shape);
      canvas.drawPath(
          path,
          Paint()
            ..color = country == null && discovered
                ? QuestColors.osSuccess.withAlpha(130)
                : QuestColors.osTextMuted.withAlpha(110));
      canvas.drawPath(
          path,
          Paint()
            ..color = QuestColors.osTextPrimary
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.6);
    }
  }

  @override
  bool shouldRepaint(covariant _GeographyPainter old) =>
      old.shapes != shapes ||
      old.progress != progress ||
      old.country != country;
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
    return Card(
        child: Padding(
            padding: const EdgeInsets.all(16),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                  '${countries.length == 1 ? countries.first.name.toUpperCase() : 'WORLD'} · ${(fraction * 100).round()}%',
                  style: QuestTypography.osHeadlineMedium),
              const SizedBox(height: 10),
              LinearProgressIndicator(
                  value: fraction, minHeight: 10, color: QuestColors.osSuccess),
              const SizedBox(height: 10),
              Text('$discovered OF $total PUBLISHED LOCATIONS DISCOVERED',
                  style: QuestTypography.osLabelSmall),
              Text(
                  '$confirmed confirmed · ${discovered - confirmed} awaiting review'),
              if (total == 0)
                const Text(
                    'Published destinations will appear here when added.'),
            ])));
  }
}

class _PlaceSheet extends ConsumerStatefulWidget {
  const _PlaceSheet({required this.place});
  final MapPlace place;
  @override
  ConsumerState<_PlaceSheet> createState() => _PlaceSheetState();
}

class _PlaceSheetState extends ConsumerState<_PlaceSheet> {
  late bool _saved = widget.place.saved;
  bool _saving = false;
  @override
  Widget build(BuildContext context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (context, scroll) => ListView(
              controller: scroll,
              padding: const EdgeInsets.all(20),
              children: [
                Row(children: [
                  Expanded(
                      child: Text(widget.place.name,
                          style: QuestTypography.osDisplayMedium)),
                  IconButton(
                      tooltip: 'Close place',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close))
                ]),
                Text(
                    '${widget.place.category.toUpperCase()} · ${widget.place.city}'),
                const SizedBox(height: 12),
                Text(widget.place.description),
                TextButton.icon(
                    onPressed: _saving
                        ? null
                        : () async {
                            setState(() => _saving = true);
                            try {
                              await ref
                                  .read(mapRepositoryProvider)
                                  .save(widget.place.id, !_saved);
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
                    icon: Icon(_saved ? Icons.bookmark : Icons.bookmark_border),
                    label: Text(_saved ? 'SAVED' : 'SAVE FOR LATER')),
                ref.watch(mapDetailProvider(widget.place.id)).when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (_, __) => _Retry(
                        message: 'Place details unavailable.',
                        onRetry: () =>
                            ref.invalidate(mapDetailProvider(widget.place.id))),
                    data: (detail) => Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (detail.quests.isEmpty)
                                const Text(
                                    'No active quests published at this place yet.'),
                              for (final q in detail.quests)
                                Card(
                                    child: ListTile(
                                        title: Text(q.title),
                                        subtitle: Text(
                                            '${q.category} · ${q.hours}H · ${q.xp} XP\n${q.unlocked ? 'OPEN' : 'LOCKED · NETWORK VERIFICATION REQUIRED'}'),
                                        isThreeLine: true,
                                        trailing: Icon(q.unlocked
                                            ? Icons.chevron_right
                                            : Icons.lock_outline),
                                        onTap: q.unlocked
                                            ? () {
                                                Navigator.pop(context);
                                                context.pushNamed(
                                                    RouteNames.questDetails,
                                                    pathParameters: {
                                                      'id': q.id
                                                    });
                                              }
                                            : null)),
                              if (detail.quests.any((q) => !q.unlocked))
                                const Padding(
                                    padding: EdgeInsets.symmetric(vertical: 12),
                                    child: Text(
                                        'Location-verified quests stay locked until CAMARA confirms your presence. Phone GPS and saving do not count as verification.')),
                              if (detail.previews.isNotEmpty) ...[
                                const SizedBox(height: 16),
                                Text('QUEST VIDEOS',
                                    style: QuestTypography.osHeadlineMedium),
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
                                      Text(p.username)
                                    ])
                                ])
                              ],
                            ])),
              ]));
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
            const Text(
                'Real Natural Earth country boundaries, projected with Mercator. Coastlines are generalised; this map is not a location-verification tool.'),
            const SizedBox(height: 16),
            for (final entry in {
              'LANDMARK': 'Named destinations and attractions.',
              'CULTURE': 'Cultural and partner destinations.',
              'PILGRIMAGE':
                  'Journey destinations; stages depend on the quest engine.',
              'HERITAGE': 'Sites and monuments.',
              'HIDDEN': 'Concealed until verified network presence.',
              'SAVED': 'Bookmarks for future travel, not visits.',
              'GREY / COLOUR':
                  'Grey is undiscovered. Colour marks a location with submitted proof; approval confirms discovery.'
            }.entries)
              ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(entry.key),
                  subtitle: Text(entry.value)),
            const Text(
                'Percentages count published quest locations, not geographic surface area. Rejected or removed proof does not count.'),
            TextButton(
                onPressed: () => showLicensePage(context: context),
                child: const Text('GEOGRAPHY LICENSES')),
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
        Text(message),
        TextButton(onPressed: onRetry, child: const Text('RETRY'))
      ]));
}
