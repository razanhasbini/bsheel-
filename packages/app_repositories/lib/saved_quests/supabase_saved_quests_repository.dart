import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:supabase_contracts/supabase_contracts.dart';
import 'saved_quests_repository.dart';

class SupabaseSavedQuestsRepository implements SavedQuestsRepository {
  final SupabaseClient client;
  SupabaseSavedQuestsRepository(this.client);

  @override
  Future<bool> isQuestSaved(String questId, String userId) async {
    final data = await client
        .from(Tables.savedQuests)
        .select(SavedQuestColumns.id)
        .eq(SavedQuestColumns.questId, questId)
        .eq(SavedQuestColumns.userId, userId)
        .maybeSingle();
    return data != null;
  }

  @override
  Future<void> saveQuest(String questId, String userId) async {
    await client.from(Tables.savedQuests).upsert(
      {
        SavedQuestColumns.questId: questId,
        SavedQuestColumns.userId: userId,
      },
      onConflict: '${SavedQuestColumns.userId},${SavedQuestColumns.questId}',
    );
  }

  @override
  Future<void> unsaveQuest(String questId, String userId) async {
    await client
        .from(Tables.savedQuests)
        .delete()
        .eq(SavedQuestColumns.questId, questId)
        .eq(SavedQuestColumns.userId, userId);
  }
}
