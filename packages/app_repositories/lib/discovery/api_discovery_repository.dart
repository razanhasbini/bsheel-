import 'package:app_models/app_models.dart';

import '../api/api_client.dart';
import 'discovery_repository.dart';

class ApiDiscoveryRepository implements DiscoveryRepository {
  ApiDiscoveryRepository(this._client);

  final ApiClient _client;

  @override
  Future<List<DiscoveryModule>> homeModules() async {
    final data = apiObject(await _client.get('discovery/home'));
    return (data['modules'] as List? ?? const [])
        .cast<Map<String, dynamic>>()
        .map(DiscoveryModule.fromJson)
        .toList();
  }

  @override
  Future<List<DiscoveryQuestCard>> worthTheTrip({int limit = 10}) async {
    final rows = apiObjectList(
        await _client.get('discovery/worth-the-trip?limit=$limit'));
    return rows.map(DiscoveryQuestCard.fromJson).toList();
  }

  @override
  Future<List<DiscoveryQuestCard>> byCountry(String countryCode,
      {int limit = 20}) async {
    final rows = apiObjectList(
        await _client.get('discovery/countries/$countryCode?limit=$limit'));
    return rows.map(DiscoveryQuestCard.fromJson).toList();
  }
}
