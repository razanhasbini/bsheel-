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

  /// Cancels a live quest at the player's request.
  ///
  /// Distinct from [markQuestExpired], which the server only accepts once the
  /// timer has run out — that guard is what keeps the countdown
  /// server-enforced. CANCEL QUEST used to call the expiry route while the
  /// quest was still running, so every tap failed with QUEST_NOT_EXPIRABLE.
  Future<void> abandonQuest(String userQuestId);
  Future<List<UserQuestModel>> getUserQuestHistory(String userId);
}
