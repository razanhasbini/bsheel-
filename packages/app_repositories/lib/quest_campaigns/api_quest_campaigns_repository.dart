import '../api/api_client.dart';
import 'quest_campaigns_repository.dart';

/// HTTP implementation of [QuestCampaignsRepository] (#56).
class ApiQuestCampaignsRepository implements QuestCampaignsRepository {
  ApiQuestCampaignsRepository(this._client);

  final ApiClient _client;

  @override
  Future<List<Map<String, dynamic>>> listChains() async =>
      apiObjectList(await _client.get('quest-campaigns/chains'));

  @override
  Future<Map<String, dynamic>> chainDetail(String id) async =>
      apiObject(await _client.get('quest-campaigns/chains/$id'));

  @override
  Future<Map<String, dynamic>> createChain({
    required String name,
    String description = '',
    String mode = 'solo',
    bool isActive = true,
  }) async =>
      apiObject(await _client.post(
        'quest-campaigns/chains',
        body: {
          'name': name,
          'description': description,
          'mode': mode,
          'isActive': isActive,
        },
      ));

  @override
  Future<Map<String, dynamic>> updateChain(
    String id, {
    String? name,
    String? description,
    String? mode,
    bool? isActive,
  }) async =>
      apiObject(await _client.patch(
        'quest-campaigns/chains/$id',
        // Only what changed: the server leaves an omitted field alone, and
        // sending nulls would read as "clear it".
        body: {
          if (name != null) 'name': name,
          if (description != null) 'description': description,
          if (mode != null) 'mode': mode,
          if (isActive != null) 'isActive': isActive,
        },
      ));

  @override
  Future<void> deleteChain(String id) async =>
      _client.delete('quest-campaigns/chains/$id');

  @override
  Future<int> appendStep(String chainId, String questId) async {
    final row = apiObject(await _client.post(
      'quest-campaigns/chains/$chainId/steps',
      body: {'questId': questId},
    ));
    return (row['step_order'] as num?)?.toInt() ?? 0;
  }

  @override
  Future<void> reorderStep(String chainId, String questId, int toOrder) async =>
      _client.patch(
        'quest-campaigns/chains/$chainId/steps',
        body: {'questId': questId, 'toOrder': toOrder},
      );

  @override
  Future<void> removeStep(String chainId, String questId) async =>
      _client.delete('quest-campaigns/chains/$chainId/steps/$questId');

  @override
  Future<List<Map<String, dynamic>>> listCollections() async =>
      apiObjectList(await _client.get('quest-campaigns/collections'));

  @override
  Future<Map<String, dynamic>> collectionDetail(String id) async =>
      apiObject(await _client.get('quest-campaigns/collections/$id'));

  @override
  Future<Map<String, dynamic>> createCollection({
    required String name,
    String description = '',
    String? countryCode,
    bool isPublished = false,
  }) async =>
      apiObject(await _client.post(
        'quest-campaigns/collections',
        body: {
          'name': name,
          'description': description,
          if (countryCode != null && countryCode.isNotEmpty)
            'countryCode': countryCode,
          'isPublished': isPublished,
        },
      ));

  @override
  Future<Map<String, dynamic>> updateCollection(
    String id, {
    String? name,
    String? description,
    String? countryCode,
    bool? isPublished,
  }) async =>
      apiObject(await _client.patch(
        'quest-campaigns/collections/$id',
        body: {
          if (name != null) 'name': name,
          if (description != null) 'description': description,
          // An empty string is deliberately forwarded: it is how the API is
          // told to clear the country, as distinct from omitting the field.
          if (countryCode != null) 'countryCode': countryCode,
          if (isPublished != null) 'isPublished': isPublished,
        },
      ));

  @override
  Future<void> deleteCollection(String id) async =>
      _client.delete('quest-campaigns/collections/$id');

  @override
  Future<void> addToCollection(String collectionId, String questId) async =>
      _client.post(
        'quest-campaigns/collections/$collectionId/quests',
        body: {'questId': questId},
      );

  @override
  Future<void> removeFromCollection(
    String collectionId,
    String questId,
  ) async =>
      _client.delete(
        'quest-campaigns/collections/$collectionId/quests/$questId',
      );

  @override
  Future<List<Map<String, dynamic>>> assignableQuests({
    String scope = 'chain',
    String search = '',
  }) async =>
      apiObjectList(await _client.get(
        'quest-campaigns/assignable-quests',
        query: {'scope': scope, 'search': search},
      ));
}
