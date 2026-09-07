import 'package:app_models/app_models.dart';

abstract class QuestsRepository {
  Future<QuestModel> getQuest(String questId);
  Future<List<QuestModel>> listAllQuestsAdmin();
  Future<QuestModel> createQuest({
    required String title,
    required String description,
    required String category,
    required String difficulty,
    required int xpReward,
    int durationHours = 4,
    bool isActive,
  });
  Future<QuestModel> updateQuest(QuestModel quest);
  Future<UserQuestModel?> getActiveUserQuest(String userId);
  Future<UserQuestModel> assignSpecificQuest(String userId, String questId);
  Future<List<QuestModel>> getQuestPickerOptions({int count = 3});
  Future<void> expireOverdueQuests(String userId);
  Future<void> markQuestExpired(String userQuestId);
  Future<List<UserQuestModel>> getUserQuestHistory(String userId);
}
