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
}

class ApiMapRepository implements MapRepository {
  ApiMapRepository(this._client);
  final ApiClient _client;
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
          bool savedOnly = false}) async =>
      apiObjectList(await _client.get('map/places', query: {
        if (country != null) 'country': country,
        if (category != null) 'category': category,
        'search': search,
        'offset': offset,
        'limit': 100,
        'saved': savedOnly.toString()
      }))
          .map(MapPlace.fromJson)
          .toList();
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
}
