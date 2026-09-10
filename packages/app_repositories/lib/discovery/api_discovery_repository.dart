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

  @override
  Future<List<DiscoveryCountry>> countries() async {
    final rows = apiObjectList(await _client.get('discovery/countries'));
    return rows.map(DiscoveryCountry.fromJson).toList();
  }

  @override
  Future<DiscoveryQuestCard?> generate({
    required String channel,
    String? countryCode,
    List<String> exclude = const [],
  }) async {
    final query = <String, String>{
      'channel': channel,
      if (countryCode != null) 'country': countryCode,
      // Capped here as well as on the server: sending fifty ids up a query
      // string is already generous, and the server refuses more anyway.
      if (exclude.isNotEmpty) 'exclude': exclude.take(50).join(','),
    };
    final qs = query.entries
        .map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}')
        .join('&');
    final raw = await _client.get('discovery/generate?$qs');
    final data = (raw is Map<String, dynamic>) ? raw['data'] : null;
    // Null is a real answer: the pool behind this shelf is exhausted for
    // this player, and the caller says so rather than showing a repeat.
    if (data is! Map<String, dynamic>) return null;
    return DiscoveryQuestCard.fromJson(data);
  }

  @override
  Future<QuestJourney?> journey(String questId) async {
    final raw = await _client.get('discovery/quests/$questId/journey');
    final data = (raw is Map<String, dynamic>) ? raw['data'] : null;
    if (data is! Map<String, dynamic>) return null;
    return QuestJourney.fromJson(data);
  }
}
