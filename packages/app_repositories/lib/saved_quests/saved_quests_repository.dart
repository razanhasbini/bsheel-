/// Per-user wishlist of quests they've BSHEEEL'd from search / discover.
abstract class SavedQuestsRepository {
  Future<bool> isQuestSaved(String questId, String userId);
  Future<void> saveQuest(String questId, String userId);
  Future<void> unsaveQuest(String questId, String userId);
}
