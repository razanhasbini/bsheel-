import '../api/api_client.dart';
import 'saved_quests_repository.dart';

class ApiSavedQuestsRepository implements SavedQuestsRepository {
  const ApiSavedQuestsRepository(this._client);

  final ApiClient _client;

  @override
  Future<bool> isQuestSaved(String questId, String userId) async {
    final data = apiObject(await _client.get('social/saved/quests/$questId'));
    return data['saved'] == true;
  }

  @override
  Future<void> saveQuest(String questId, String userId) async {
    await _client.put('social/saved/quests/$questId');
  }

  @override
  Future<void> unsaveQuest(String questId, String userId) async {
    await _client.delete('social/saved/quests/$questId');
  }
}
