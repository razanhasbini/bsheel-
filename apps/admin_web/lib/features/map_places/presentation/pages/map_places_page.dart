import 'package:app_contracts/app_contracts.dart';
import 'package:app_repositories/app_repositories.dart' show ApiException;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/backend/app_backend.dart';
import '../../../../core/providers/admin_role_provider.dart';
import '../../../../core/theme/bsheel_design.dart';
import '../../../../shared/layout/admin_shell.dart';
import '../../../../shared/widgets/bsheel_widgets.dart';

/// Map destinations — the places a quest can be pinned to, and the
/// place↔quest links that make a quest a *located* quest.
///
/// `map/admin/places` is `super_admin` only, so the page reads the list
/// only once the role has resolved to super admin. A moderator gets an
/// explained empty state instead of a table whose every action answers
/// 403 (issue #48).
///
/// `hidden` is a **category**, not a visibility flag: a hidden place stays
/// server-side until the requesting user has current CAMARA geofence
/// evidence (migration 0022's `enforce_destination_assignment`). It is
/// therefore marked on its own row, separately from the published/draft
/// status, so it never reads as an ordinary published place.

/// Every destination, newest first — the admin list, which unlike the
/// public one includes drafts and hidden places.
final _placesProvider =
    FutureProvider.autoDispose<List<_MapPlace>>((ref) async {
  final rows = await AppBackend.repositories.admin.adminMapPlaces();
  return rows.map(_MapPlace.fromRow).toList();
});

/// The quest bank, from the same query the quest-management page lists.
/// Retired quests are dropped: an inactive quest is never handed out, so
/// pinning one to a place would link a destination nobody can reach.
final _questBankProvider =
    FutureProvider.autoDispose<List<_QuestChoice>>((ref) async {
  final quests = await AppBackend.repositories.quests.listAllQuestsAdmin();
  final choices = quests
      .where((quest) => quest.isActive)
      .map((quest) => _QuestChoice(
            id: quest.id,
            title: quest.title,
            category: quest.category,
            difficulty: quest.difficulty,
          ))
      .toList()
    ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
  return choices;
});

/// Category tint. `BsheelColors.category` only knows the five *quest*
/// categories, so the map's own five map onto the same accent set the
/// system already uses for category identity — `hidden` takes lavender,
/// the "held back / inactive" token, because its row is deliberately
/// quieter than a live one.
Color _categoryGround(String category) => switch (category) {
      MapPlaceCategory.landmark => BsheelColors.cool,
      MapPlaceCategory.culture => BsheelColors.primary,
      MapPlaceCategory.pilgrimage => BsheelColors.accent,
      MapPlaceCategory.heritage => BsheelColors.success,
      MapPlaceCategory.hidden => BsheelColors.lavender,
      _ => BsheelColors.lavender,
    };

/// `landmark` → `Landmark`, for dropdown items that read as words rather
/// than as DB values.
String _readable(String value) =>
    value.isEmpty ? value : '${value[0].toUpperCase()}${value.substring(1)}';

/// `33.2705` — six places is ~10cm, finer than any geofence radius.
String _coord(double value) => value.toStringAsFixed(6);

double? _toDouble(Object? raw) => raw is num
    ? raw.toDouble()
    : (raw == null ? null : double.tryParse(raw.toString()));

int? _toInt(Object? raw) =>
    raw is num ? raw.toInt() : (raw == null ? null : int.tryParse('$raw'));

/// One row of `map/admin/places`: the `map_places` record joined with its
/// country. Parsed once here so the table and the detail dialog read
/// typed fields rather than repeating wire keys.
class _MapPlace {
  const _MapPlace({
    required this.id,
    required this.name,
    required this.description,
    required this.city,
    required this.category,
    required this.countryCode,
    required this.countryName,
    required this.geometryId,
    required this.latitude,
    required this.longitude,
    required this.radiusM,
    required this.isPublished,
    required this.questCount,
  });

  factory _MapPlace.fromRow(Map<String, dynamic> row) => _MapPlace(
        id: (row['id'] ?? '').toString(),
        name: (row['name'] ?? '').toString(),
        description: (row['description'] ?? '').toString(),
        city: (row['city'] ?? '').toString(),
        category: (row['category'] ?? '').toString(),
        countryCode: (row['country_code'] ?? '').toString(),
        countryName: (row['country_name'] ?? '').toString(),
        geometryId: (row['geometry_id'] ?? '').toString(),
        latitude: _toDouble(row['latitude']) ?? 0,
        longitude: _toDouble(row['longitude']) ?? 0,
        radiusM: _toInt(row['radius_m']) ?? 0,
        isPublished: row['is_published'] == true,
        // The admin list now returns this. Still read defensively — an
        // older server would omit it, and a missing count must render as
        // unknown rather than as a confident zero.
        questCount: _toInt(row['quest_count']),
      );

  final String id;
  final String name;
  final String description;
  final String city;
  final String category;
  final String countryCode;
  final String countryName;
  final String geometryId;
  final double latitude;
  final double longitude;
  final int radiusM;
  final bool isPublished;
  final int? questCount;

  /// Content held back until the user's location is proven — not a draft.
  bool get isHidden => category == MapPlaceCategory.hidden;
}

/// A pickable quest in the link dialog.
class _QuestChoice {
  const _QuestChoice({
    required this.id,
    required this.title,
    required this.category,
    required this.difficulty,
  });

  final String id;
  final String title;
  final String category;
  final String difficulty;

  bool matches(String query) =>
      query.isEmpty ||
      title.toLowerCase().contains(query) ||
      category.toLowerCase().contains(query);
}

class MapPlacesPage extends ConsumerStatefulWidget {
  const MapPlacesPage({super.key});

  @override
  ConsumerState<MapPlacesPage> createState() => _MapPlacesPageState();
}

class _MapPlacesPageState extends ConsumerState<MapPlacesPage> {
  /// Not a category value — the chip that clears the filter.
  static const String _filterAll = 'all';

  String _filter = _filterAll;

  @override
  Widget build(BuildContext context) {
    final roleAsync = ref.watch(isSuperAdminProvider);
    final isSuperAdmin = roleAsync.valueOrNull ?? false;
    // Reading the list at all is super-admin-gated on the server, so a
    // moderator's page never sends the request.
    final placesAsync = isSuperAdmin ? ref.watch(_placesProvider) : null;
    final places = placesAsync?.valueOrNull;

    return AdminPage(
      title: 'Destinations',
      meta: places == null ? null : '${places.length} places',
      actions: [
        if (isSuperAdmin)
          BsheelButton.primary(
            label: 'New place',
            small: true,
            onPressed: () => _showCreateDialog(context),
          ),
      ],
      subheader: isSuperAdmin ? _filterRow(places) : null,
      child: _body(context, roleAsync, isSuperAdmin, placesAsync),
    );
  }

  Widget _body(
    BuildContext context,
    AsyncValue<bool> roleAsync,
    bool isSuperAdmin,
    AsyncValue<List<_MapPlace>>? placesAsync,
  ) {
    // Role still resolving: draw the rows that are about to arrive rather
    // than flashing "super admin only" at a super admin.
    if (roleAsync.isLoading) {
      return const BsheelLoadingList(rows: 6, rowHeight: 44);
    }
    if (!isSuperAdmin) {
      return const Padding(
        padding: EdgeInsets.only(top: 36),
        child: BsheelEmptyState(
          title: 'Super admin only',
          message: 'Destination management creates map places and pins quests '
              'to them, which only a super admin may do. Nothing on this page '
              'would work under your role. Ask a super admin to add the place '
              'or link the quest.',
        ),
      );
    }

    return placesAsync!.when(
      loading: () => const BsheelLoadingList(rows: 6, rowHeight: 44),
      error: (e, _) => BsheelErrorState(
        message: 'The destination list did not come back. Nothing was changed '
            '— no place has been created and no quest has been linked to '
            'one. ($e)',
        onRetry: () => ref.invalidate(_placesProvider),
      ),
      data: (places) => _table(context, places),
    );
  }

  // ── Filters ────────────────────────────────────────────────

  Widget _filterRow(List<_MapPlace>? places) {
    int? countWhere(bool Function(_MapPlace) test) =>
        places?.where(test).length;

    return BsheelFilterChips(
      selected: _filter,
      onChanged: (value) => setState(() => _filter = value),
      filters: [
        // ALL stays untinted — it is not a category.
        BsheelFilter(_filterAll, 'All', count: places?.length),
        for (final category in MapPlaceCategory.all)
          BsheelFilter(
            category,
            category,
            count: countWhere((place) => place.category == category),
            ground: _categoryGround(category),
          ),
      ],
    );
  }

  bool _matches(_MapPlace place) =>
      _filter == _filterAll || place.category == _filter;

  // ── Table ──────────────────────────────────────────────────

  Widget _table(BuildContext context, List<_MapPlace> places) {
    final filtered = places.where(_matches).toList();

    if (filtered.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 36),
        child: _filter == _filterAll
            ? BsheelEmptyState(
                title: 'No destinations yet',
                message: 'The map has nothing to draw and no quest can be '
                    'located until a place exists. Add the first one.',
                actionLabel: 'New place',
                onAction: () => _showCreateDialog(context),
              )
            : BsheelEmptyState(
                title: 'No matches',
                message: 'No destination sits in that category. Nothing has '
                    'been removed — clear the filter to see every place.',
                actionLabel: 'Clear filter',
                onAction: () => setState(() => _filter = _filterAll),
              ),
      );
    }

    return BsheelTable(
      depth: 5,
      columns: const [
        BsheelColumn('Name'),
        BsheelColumn('Country', width: 110),
        BsheelColumn('City', width: 110),
        BsheelColumn('Category', width: 104),
        BsheelColumn('Quests', width: 76),
        BsheelColumn('Status', width: 96),
      ],
      rows: [for (final place in filtered) _tableRow(context, place)],
    );
  }

  BsheelRow _tableRow(BuildContext context, _MapPlace place) {
    // A draft greys wholesale, so every cell reads as not-yet-live.
    final draft = !place.isPublished;
    final Color? dim = draft ? BsheelColors.inkMuted : null;

    return BsheelRow(
      [
        Row(
          children: [
            Flexible(child: BsheelCell.title(place.name, muted: draft)),
            // Hidden is content the server withholds until the user's
            // location is proven. Sky, because it states a fact about the
            // record — nothing is at fault and nothing waits on a person.
            if (place.isHidden) ...[
              const SizedBox(width: 8),
              const BsheelPill(
                'hidden',
                tone: BsheelPillTone.sky,
                small: true,
              ),
            ],
          ],
        ),
        BsheelCell.mono(
          place.countryCode.isEmpty ? '—' : place.countryCode,
          color: dim,
        ),
        BsheelCell.meta(place.city.isEmpty ? '—' : place.city, color: dim),
        BsheelCell.pill(
          BsheelTag(place.category, ground: _categoryGround(place.category)),
        ),
        // `map/admin/places` does not join quest_destinations, so the
        // count is unknown rather than zero. See the class doc.
        place.questCount == null
            ? BsheelCell.meta('—', color: dim)
            : BsheelCell.mono('${place.questCount}', color: dim),
        BsheelCell.pill(
          place.isPublished
              ? BsheelPill.status('published')
              : BsheelPill.status('draft'),
        ),
      ],
      muted: draft,
      onTap: () => _showDetailDialog(context, place),
    );
  }

  // ── Dialogs ────────────────────────────────────────────────

  void _showCreateDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) => const _NewPlaceDialog(),
    );
  }

  void _showDetailDialog(BuildContext context, _MapPlace place) {
    showDialog<void>(
      context: context,
      builder: (_) => _PlaceDetailDialog(place: place),
    );
  }
}

// ── Detail + quest link ─────────────────────────────────────────────

/// Where a place is, how wide its geofence is, and the one thing staff can
/// change from here: which quest is pinned to it.
class _PlaceDetailDialog extends ConsumerStatefulWidget {
  const _PlaceDetailDialog({required this.place});

  final _MapPlace place;

  @override
  ConsumerState<_PlaceDetailDialog> createState() => _PlaceDetailDialogState();
}

class _PlaceDetailDialogState extends ConsumerState<_PlaceDetailDialog> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _search = '';
  String? _questId;
  bool _requiresVerification = true;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _link() async {
    final questId = _questId;
    if (questId == null) return;
    // Captured before the await: the confirmation is shown by the page's
    // messenger *after* this dialog has been popped.
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await AppBackend.repositories.admin.linkQuestToPlace(
        widget.place.id,
        questId: questId,
        requiresVerification: _requiresVerification,
      );
      ref.invalidate(_placesProvider);
      if (!mounted) return;
      navigator.pop();
      messenger.showSnackBar(
        SnackBar(content: Text('Quest linked to ${widget.place.name}.')),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        // The server refuses to move a quest that already has attempts,
        // because that would retroactively move discovery.
        _error = e.code == 'QUEST_ALREADY_STARTED'
            ? 'That quest already has attempts, so it cannot be moved to a '
                'destination. Nothing was linked. Pick a quest nobody has '
                'started, or write a new one.'
            : e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'The link was not saved. Nothing changed on this place. ($e)';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final place = widget.place;
    final questsAsync = ref.watch(_questBankProvider);

    return BsheelDialog(
      title: 'Destination',
      maxWidth: 560,
      content: SizedBox(
        width: 520,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 460),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(place.name, style: BsheelType.displayXs),
                    ),
                    const SizedBox(width: 10),
                    if (place.isHidden)
                      const BsheelPill('hidden', tone: BsheelPillTone.sky),
                  ],
                ),
                if (place.description.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    place.description,
                    style: BsheelType.bodySm.copyWith(
                      color: BsheelColors.inkSoft,
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                BsheelKeyValues(
                  entries: [
                    BsheelKeyValue('Latitude', _coord(place.latitude)),
                    BsheelKeyValue('Longitude', _coord(place.longitude)),
                    BsheelKeyValue('Geofence radius', '${place.radiusM} m'),
                    BsheelKeyValue(
                      'Country',
                      place.countryName.isEmpty
                          ? place.countryCode
                          : '${place.countryName} · ${place.countryCode}',
                    ),
                    if (place.city.isNotEmpty)
                      BsheelKeyValue('City', place.city),
                    BsheelKeyValue('Atlas geometry', place.geometryId),
                  ],
                ),
                const SizedBox(height: 18),
                Container(
                  height: BsheelBorders.hairline,
                  color: BsheelColors.rowLine,
                ),
                const SizedBox(height: 14),
                const BsheelLabel('Link a quest'),
                const SizedBox(height: 6),
                const Text(
                  'A quest has one destination, so linking moves it here from '
                  'wherever it was. A quest that already has attempts cannot '
                  'be moved.',
                  style: BsheelType.bodyXs,
                ),
                const SizedBox(height: 10),
                BsheelSearchField(
                  controller: _searchCtrl,
                  hint: 'Search active quests…',
                  onChanged: (v) =>
                      setState(() => _search = v.trim().toLowerCase()),
                ),
                const SizedBox(height: 10),
                questsAsync.when(
                  loading: () =>
                      const BsheelLoadingList(rows: 3, rowHeight: 40),
                  error: (e, _) => BsheelCallout.danger(
                    'The quest bank did not load, so nothing can be linked '
                    'yet. Nothing on this place has changed. ($e)',
                  ),
                  data: _questPicker,
                ),
                const SizedBox(height: 14),
                BsheelCard.flat(
                  padding: EdgeInsets.zero,
                  child: BsheelToggleRow(
                    name: 'Requires verification',
                    description: 'On, the user must prove they are inside the '
                        'geofence before this quest can be assigned. Off, the '
                        'place is only a label — unless it is hidden, which '
                        'always demands proof.',
                    monoName: false,
                    value: _requiresVerification,
                    last: true,
                    onChanged: _saving
                        ? null
                        : (v) => setState(() => _requiresVerification = v),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  BsheelCallout.danger(_error!),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        BsheelButton.ghost(
          label: 'Close',
          small: true,
          onPressed: _saving ? null : () => Navigator.pop(context),
        ),
        BsheelButton.primary(
          label: 'Link quest',
          small: true,
          loading: _saving,
          onPressed: _questId == null || _saving ? null : _link,
        ),
      ],
    );
  }

  Widget _questPicker(List<_QuestChoice> quests) {
    final matches = quests.where((q) => q.matches(_search)).toList();
    if (matches.isEmpty) {
      return Text(
        quests.isEmpty
            ? 'There are no active quests to link. Write one in the quest '
                'bank first.'
            : 'No active quest matches that search.',
        style: BsheelType.bodyXs,
      );
    }

    return SizedBox(
      height: 168,
      child: ListView.separated(
        padding: EdgeInsets.zero,
        itemCount: matches.length,
        separatorBuilder: (_, __) => const SizedBox(height: 7),
        itemBuilder: (_, i) {
          final quest = matches[i];
          final selected = quest.id == _questId;
          final fg = selected
              ? BsheelColors.onAccent(BsheelColors.primary)
              : BsheelColors.ink;
          return BsheelCard.flat(
            color: selected ? BsheelColors.primary : BsheelColors.card,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            onTap: _saving ? null : () => setState(() => _questId = quest.id),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  quest.title,
                  style: BsheelType.bodySmMedium.copyWith(color: fg),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Text(
                  '${quest.category} · ${quest.difficulty}'.toUpperCase(),
                  style: BsheelType.labelSm.copyWith(
                    color: selected ? fg : BsheelColors.inkSoft,
                    fontSize: 10,
                    letterSpacing: 0.7,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ── Create ──────────────────────────────────────────────────────────

/// Every bound below mirrors `MapPlaceDto`, so a value the server would
/// reject never leaves the browser.
class _NewPlaceDialog extends ConsumerStatefulWidget {
  const _NewPlaceDialog();

  @override
  ConsumerState<_NewPlaceDialog> createState() => _NewPlaceDialogState();
}

class _NewPlaceDialogState extends ConsumerState<_NewPlaceDialog> {
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _descCtrl = TextEditingController();
  final TextEditingController _countryCodeCtrl = TextEditingController();
  final TextEditingController _countryNameCtrl = TextEditingController();
  final TextEditingController _geometryCtrl = TextEditingController();
  final TextEditingController _cityCtrl = TextEditingController();
  final TextEditingController _latCtrl = TextEditingController();
  final TextEditingController _lngCtrl = TextEditingController();
  final TextEditingController _radiusCtrl = TextEditingController(text: '250');

  String _category = MapPlaceCategory.landmark;
  bool _isPublished = false;
  bool _saving = false;

  /// Per-field messages, keyed by the DTO field. Rendered by each
  /// [BsheelField]'s own `error`, never as a tooltip or a snackbar.
  final Map<String, String> _errors = <String, String>{};
  String? _formError;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _countryCodeCtrl.dispose();
    _countryNameCtrl.dispose();
    _geometryCtrl.dispose();
    _cityCtrl.dispose();
    _latCtrl.dispose();
    _lngCtrl.dispose();
    _radiusCtrl.dispose();
    super.dispose();
  }

  /// Fills [_errors] and returns true when nothing is left to fix.
  bool _validate() {
    _errors.clear();

    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      _errors['name'] = 'A place needs a name.';
    } else if (name.length > 160) {
      _errors['name'] = 'Use 160 characters or fewer (currently '
          '${name.length}).';
    }

    if (_descCtrl.text.trim().length > 2000) {
      _errors['description'] = 'Use 2000 characters or fewer (currently '
          '${_descCtrl.text.trim().length}).';
    }

    // The DTO wants exactly two *uppercase* letters, so a lowercase entry
    // is upper-cased rather than rejected — a typo is not a case error.
    final countryCode = _countryCodeCtrl.text.trim().toUpperCase();
    if (!RegExp(r'^[A-Z]{2}$').hasMatch(countryCode)) {
      _errors['countryCode'] = 'Two letters, ISO 3166-1 alpha-2 — LB, QA.';
    }

    final countryName = _countryNameCtrl.text.trim();
    if (countryName.isEmpty) {
      _errors['countryName'] = 'Name the country — it is created if new.';
    } else if (countryName.length > 100) {
      _errors['countryName'] = 'Use 100 characters or fewer.';
    }

    final geometryId = _geometryCtrl.text.trim();
    if (!RegExp(r'^[0-9]{3}$').hasMatch(geometryId)) {
      _errors['geometryId'] = 'Exactly three digits — the world-atlas '
          'numeric id (Lebanon 422, Qatar 634).';
    }

    if (_cityCtrl.text.trim().length > 100) {
      _errors['city'] = 'Use 100 characters or fewer.';
    }

    final latitude = double.tryParse(_latCtrl.text.trim());
    if (latitude == null) {
      _errors['latitude'] = 'Numbers only, decimal degrees.';
    } else if (latitude < -85 || latitude > 85) {
      _errors['latitude'] = 'Between -85 and 85.';
    }

    final longitude = double.tryParse(_lngCtrl.text.trim());
    if (longitude == null) {
      _errors['longitude'] = 'Numbers only, decimal degrees.';
    } else if (longitude < -180 || longitude > 180) {
      _errors['longitude'] = 'Between -180 and 180.';
    }

    final radius = int.tryParse(_radiusCtrl.text.trim());
    if (radius == null) {
      _errors['radiusM'] = 'Whole metres only.';
    } else if (radius < 25 || radius > 10000) {
      _errors['radiusM'] = 'Between 25 and 10000 metres.';
    }

    // Category needs no check: the dropdown is built from
    // `MapPlaceCategory.all` and starts on a legal value, so it cannot
    // hold anything the CHECK constraint would refuse.

    return _errors.isEmpty;
  }

  Future<void> _save() async {
    // Fills `_errors`; the setState below is what paints them.
    final valid = _validate();
    setState(() => _formError = null);
    if (!valid) return;

    // Captured before the await — see the note in the detail dialog.
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() => _saving = true);
    try {
      await AppBackend.repositories.admin.createMapPlace(
        countryCode: _countryCodeCtrl.text.trim().toUpperCase(),
        countryName: _countryNameCtrl.text.trim(),
        geometryId: _geometryCtrl.text.trim(),
        name: _nameCtrl.text.trim(),
        category: _category,
        latitude: double.parse(_latCtrl.text.trim()),
        longitude: double.parse(_lngCtrl.text.trim()),
        description: _descCtrl.text.trim(),
        city: _cityCtrl.text.trim(),
        radiusM: int.parse(_radiusCtrl.text.trim()),
        isPublished: _isPublished,
      );
      ref.invalidate(_placesProvider);
      if (!mounted) return;
      navigator.pop();
      messenger.showSnackBar(
        const SnackBar(content: Text('Destination created.')),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _formError = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _formError = 'The place was not created. Nothing has been written to '
            'the map. ($e)';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return BsheelDialog(
      title: 'New place',
      maxWidth: 620,
      content: SizedBox(
        width: 580,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 460),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                BsheelField(
                  controller: _nameCtrl,
                  label: 'Name',
                  hint: 'Baalbek Roman Temples',
                  error: _errors['name'],
                  enabled: !_saving,
                ),
                const SizedBox(height: 14),
                BsheelField(
                  controller: _descCtrl,
                  label: 'Description',
                  hint: 'Shown on the place card. Optional.',
                  maxLines: 3,
                  error: _errors['description'],
                  enabled: !_saving,
                ),
                const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 120,
                      child: BsheelField(
                        controller: _countryCodeCtrl,
                        label: 'Country code',
                        hint: 'LB',
                        maxLength: 2,
                        error: _errors['countryCode'],
                        enabled: !_saving,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: BsheelField(
                        controller: _countryNameCtrl,
                        label: 'Country name',
                        hint: 'Lebanon',
                        error: _errors['countryName'],
                        enabled: !_saving,
                      ),
                    ),
                    const SizedBox(width: 14),
                    SizedBox(
                      width: 130,
                      child: BsheelField(
                        controller: _geometryCtrl,
                        label: 'Geometry id',
                        hint: '422',
                        maxLength: 3,
                        keyboardType: TextInputType.number,
                        error: _errors['geometryId'],
                        enabled: !_saving,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: BsheelField(
                        controller: _cityCtrl,
                        label: 'City',
                        hint: 'Optional',
                        error: _errors['city'],
                        enabled: !_saving,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: BsheelDropdown<String>(
                        value: _category,
                        label: 'Category',
                        items: [
                          for (final value in MapPlaceCategory.all)
                            DropdownMenuItem(
                              value: value,
                              child: Text(_readable(value)),
                            ),
                        ],
                        onChanged: _saving
                            ? (_) {}
                            : (v) => setState(() => _category = v!),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  _category == MapPlaceCategory.hidden
                      ? 'Hidden places stay server-side until the user proves '
                          'they are inside the geofence, whatever the quest '
                          'link says.'
                      : 'Category tints the place on the map and in this '
                          'table.',
                  style: BsheelType.bodyXs,
                ),
                const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: BsheelField(
                        controller: _latCtrl,
                        label: 'Latitude',
                        hint: '34.006700',
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                          signed: true,
                        ),
                        error: _errors['latitude'],
                        enabled: !_saving,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: BsheelField(
                        controller: _lngCtrl,
                        label: 'Longitude',
                        hint: '36.203900',
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                          signed: true,
                        ),
                        error: _errors['longitude'],
                        enabled: !_saving,
                      ),
                    ),
                    const SizedBox(width: 14),
                    SizedBox(
                      width: 150,
                      child: BsheelField(
                        controller: _radiusCtrl,
                        label: 'Radius (m)',
                        keyboardType: TextInputType.number,
                        error: _errors['radiusM'],
                        enabled: !_saving,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                BsheelCard.flat(
                  padding: EdgeInsets.zero,
                  child: BsheelToggleRow(
                    name: 'Published',
                    description: 'A draft is invisible to the app and its '
                        'quests cannot be assigned. Publish once the '
                        'coordinates are right.',
                    monoName: false,
                    value: _isPublished,
                    last: true,
                    onChanged: _saving
                        ? null
                        : (v) => setState(() => _isPublished = v),
                  ),
                ),
                if (_formError != null) ...[
                  const SizedBox(height: 14),
                  BsheelCallout.danger(_formError!),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        BsheelButton.ghost(
          label: 'Cancel',
          small: true,
          onPressed: _saving ? null : () => Navigator.pop(context),
        ),
        BsheelButton.primary(
          label: 'Create place',
          small: true,
          loading: _saving,
          onPressed: _saving ? null : _save,
        ),
      ],
    );
  }
}
