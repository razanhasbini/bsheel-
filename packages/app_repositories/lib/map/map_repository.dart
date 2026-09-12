import 'package:app_models/app_models.dart';
import '../api/api_client.dart';
import '../media/api_media_signer.dart';

abstract class MapRepository {
  Future<List<MapCountry>> countries({String? userId});
  Future<List<MapPlace>> places(
      {String? country,
      String? category,
      String search = '',
      int offset = 0,
      bool savedOnly = false});
  Future<MapPlaceDetail> detail(String id);
  Future<void> save(String id, bool saved);

  /// The one exploration model — world and per-country percentages from
  /// approved destination quests. Displayed, never recomputed, on the client.
  Future<MapProgress> progress();

  /// A country as seen from anywhere: trending and discovery quests, hidden
  /// count, collections. Being there is never required.
  Future<MapCountryDiscovery> discover(String countryCode);

  /// Recent proof from the feed, pinned at the place it happened. Media is
  /// signed before it is returned, so the tiles can be drawn directly.
  Future<List<MapMoment>> moments({String? country, int limit = 60});
}

class ApiMapRepository implements MapRepository {
  ApiMapRepository(this._client);
  final ApiClient _client;

  /// Swaps the raw `cover_media_url` on each row for a signed URL the image
  /// widget can load; rows without a cover are left alone.
  Future<void> _signCovers(List<Map<String, dynamic>> rows) async {
    final raw = rows
        .map((r) => r['cover_media_url'] as String? ?? '')
        .where((u) => u.isNotEmpty)
        .toSet()
        .toList();
    if (raw.isEmpty) return;
    final signed = await ApiMediaSigner(_client).signMany(raw);
    for (final row in rows) {
      final url = row['cover_media_url'] as String?;
      if (url != null && url.isNotEmpty) {
        row['cover_media_url'] = signed[url] ?? '';
      }
    }
  }

  @override
  Future<List<MapCountry>> countries({String? userId}) async =>
      apiObjectList(await _client.get(userId == null
              ? 'map/countries'
              : 'map/profiles/$userId/countries'))
          .map(MapCountry.fromJson)
          .toList();

  @override
  Future<List<MapPlace>> places(
      {String? country,
      String? category,
      String search = '',
      int offset = 0,
      bool savedOnly = false}) async {
    final rows = apiObjectList(await _client.get('map/places', query: {
      if (country != null) 'country': country,
      if (category != null) 'category': category,
      'search': search,
      'offset': offset,
      'limit': 100,
      'saved': savedOnly.toString()
    }))
        .map((r) => Map<String, dynamic>.from(r))
        .toList();
    await _signCovers(rows);
    return rows.map(MapPlace.fromJson).toList();
  }

  @override
  Future<MapPlaceDetail> detail(String id) async {
    final data = apiObject(await _client.get('map/places/$id'));
    final previews = (data['previews'] as List).cast<Map<String, dynamic>>();
    final signed = await ApiMediaSigner(_client)
        .signMany(previews.map((p) => p['media_url'] as String? ?? ''));
    for (final preview in previews) {
      preview['media_url'] = signed[preview['media_url']] ?? '';
    }
    return MapPlaceDetail.fromJson(data);
  }

  @override
  Future<void> save(String id, bool saved) async {
    if (saved) {
      await _client.post('map/places/$id/save');
    } else {
      await _client.delete('map/places/$id/save');
    }
  }

  @override
  Future<List<MapMoment>> moments({String? country, int limit = 60}) async {
    final rows = apiObjectList(await _client.get('map/moments', query: {
      if (country != null) 'country': country,
      'limit': limit,
    })).map((r) => Map<String, dynamic>.from(r)).toList();
    // Same signing path as the feed's, and for the same reason: `media_url`
    // is an object key, and the key is the access. A row whose signing
    // failed keeps an empty string rather than the raw key — the tile draws
    // a placeholder, and nothing leaks a key that would not load anyway.
    final raw = rows
        .map((r) => r['media_url'] as String? ?? '')
        .where((u) => u.isNotEmpty)
        .toSet()
        .toList();
    // Avatars go through the same signer and the same request: the author's
    // face is on the tile, and a second round trip per moment would be one
    // request per pin.
    raw.addAll(rows
        .map((r) => r['avatar_url'] as String? ?? '')
        .where((u) => u.isNotEmpty));
    if (raw.isNotEmpty) {
      final signed = await ApiMediaSigner(_client).signMany(raw.toSet().toList());
      for (final row in rows) {
        for (final key in ['media_url', 'avatar_url']) {
          final url = row[key] as String?;
          if (url != null && url.isNotEmpty) row[key] = signed[url] ?? '';
        }
      }
    }
    return rows.map(MapMoment.fromJson).toList();
  }

  @override
  Future<MapProgress> progress() async =>
      MapProgress.fromJson(apiObject(await _client.get('map/progress/me')));

  @override
  Future<MapCountryDiscovery> discover(String countryCode) async {
    final data =
        apiObject(await _client.get('map/countries/$countryCode/discover'));
    final snippets = <Map<String, dynamic>>[
      for (final key in ['trending', 'discovery'])
        ...(data[key] as List).map((q) => Map<String, dynamic>.from(q as Map)),
    ];
    await _signCovers(snippets);
    // Write the signed rows back under their keys in the same order.
    final trendingCount = (data['trending'] as List).length;
    data['trending'] = snippets.sublist(0, trendingCount);
    data['discovery'] = snippets.sublist(trendingCount);
    return MapCountryDiscovery.fromJson(data);
  }
}
