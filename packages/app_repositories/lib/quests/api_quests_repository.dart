import 'package:app_models/app_models.dart';
import 'package:supabase_contracts/supabase_contracts.dart';

import '../api/api_client.dart';
import '../media/api_media_signer.dart';
import 'quests_repository.dart';

class ApiQuestsRepository implements QuestsRepository {
  ApiQuestsRepository(this._client) : _media = ApiMediaSigner(_client);

  final ApiClient _client;
  final ApiMediaSigner _media;

  @override
  Future<QuestModel> getQuest(String questId) async =>
      QuestModel.fromJson(apiObject(await _client.get('quests/$questId')));

  @override
  Future<List<QuestModel>> listAllQuestsAdmin() async => apiObjectList(
        await _client.get('quests/admin/all'),
      ).map(QuestModel.fromJson).toList(growable: false);

  @override
  Future<QuestModel> createQuest({
    required String title,
    required String description,
    required String category,
    required String difficulty,
    required int xpReward,
    int durationHours = 4,
    bool isActive = true,
  }) async =>
      QuestModel.fromJson(
        apiObject(
          await _client.post(
            'quests/admin',
            body: {
              'title': title,
              'description': description,
              'category': category,
              'difficulty': difficulty,
              'xpReward': xpReward,
              'durationHours': durationHours,
              'isActive': isActive,
            },
          ),
        ),
      );

  @override
  Future<QuestModel> updateQuest(QuestModel quest) async => QuestModel.fromJson(
        apiObject(
          await _client.patch(
            'quests/admin/${quest.id}',
            body: {
              'title': quest.title,
              'description': quest.description,
              'category': quest.category,
              'difficulty': quest.difficulty,
              'xpReward': quest.xpReward,
              'durationHours': quest.durationHours,
              'isActive': quest.isActive,
            },
          ),
        ),
      );

  Future<List<QuestModel>> createQuestsBulk(
    List<Map<String, dynamic>> quests,
  ) async =>
      apiObjectList(
        await _client.post(
          'quests/admin/bulk',
          body: {'quests': quests},
        ),
      ).map(QuestModel.fromJson).toList(growable: false);

  Future<void> deleteQuest(String questId) =>
      _client.delete('quests/admin/$questId');

  Future<int> deleteAllQuests() async {
    final data = apiObject(
      await _client.delete(
        'quests/admin',
        body: const {'confirmation': 'DELETE ALL'},
      ),
    );
    return (data['deleted'] as num).toInt();
  }

  @override
  Future<UserQuestModel?> getActiveUserQuest(String userId) async {
    final data = await _client.get('quests/active');
    if (data == null) return null;
    final quest = UserQuestModel.fromJson(apiObject(data));
    if (quest.status == UserQuestStatus.assigned &&
        quest.expiresAt != null &&
        DateTime.now().isAfter(quest.expiresAt!)) {
      await markQuestExpired(quest.id);
      return null;
    }
    return quest;
  }

  @override

  /// Assigns a quest to the signed-in user. The API derives the user from
  /// the access token, so [userId] is accepted only to satisfy the existing
  /// contract and must be the caller. Admins assigning to somebody else use
  /// [assignQuestToUser].
  Future<UserQuestModel> assignSpecificQuest(
    String userId,
    String questId,
  ) async =>
      UserQuestModel.fromJson(
        apiObject(
          await _client.post(
            'quests/assign',
            body: {'questId': questId},
          ),
        ),
      );

  /// Admin override: assigns an existing quest to [userId], expiring
  /// whatever that user currently has in flight. One audited transaction
  /// on the API — the previous client version expired the active quest in a
  /// separate call, so a failure between the two left the user with nothing.
  Future<UserQuestModel> assignQuestToUser(
    String userId,
    String questId,
  ) async =>
      UserQuestModel.fromJson(
        apiObject(
          await _client.post(
            'quests/admin/assign',
            body: {'userId': userId, 'questId': questId},
          ),
        ),
      );

  @override
  Future<List<QuestModel>> getQuestPickerOptions({int count = 3}) async =>
      apiObjectList(await _client.get('quests/picker', query: {'count': count}))
          .map(QuestModel.fromJson)
          .toList(growable: false);

  Future<Map<String, dynamic>?> getQuestOfTheDay() async {
    final data = await _client.get('quests/quest-of-the-day');
    return data == null ? null : apiObject(data);
  }

  Future<List<Map<String, dynamic>>> getFollowingActiveQuests({
    int limit = 12,
  }) async {
    final rows = apiObjectList(
      await _client.get(
        'quests/following-active',
        query: {'limit': limit},
      ),
    );
    final signed = await _media.signMany(
      rows.map((row) => row['avatar_url']?.toString() ?? ''),
    );
    return rows.map((row) {
      final avatar = row['avatar_url']?.toString();
      return {
        ...row,
        'avatar_url': avatar == null ? null : signed[avatar] ?? avatar,
      };
    }).toList(growable: false);
  }

  Future<int> getRerollsRemaining() async {
    final data = apiObject(await _client.get('quests/rerolls/remaining'));
    return (data['remaining'] as num).toInt();
  }

  Future<int> recordReroll() async {
    final data = apiObject(await _client.post('quests/rerolls'));
    return (data['remaining'] as num).toInt();
  }

  @override
  Future<void> expireOverdueQuests(String userId) async {
    final active = await getActiveUserQuest(userId);
    if (active?.status == UserQuestStatus.assigned &&
        active?.expiresAt != null &&
        DateTime.now().isAfter(active!.expiresAt!)) {
      await markQuestExpired(active.id);
    }
  }

  @override
  Future<void> markQuestExpired(String userQuestId) async {
    await _client.post('quests/expire', body: {'userQuestId': userQuestId});
  }

  @override
  Future<List<UserQuestModel>> getUserQuestHistory(String userId) async {
    final result = <UserQuestModel>[];
    const pageSize = 100;
    for (var offset = 0;; offset += pageSize) {
      final page = apiObjectList(
        await _client.get(
          'quests/history',
          query: {
            'limit': pageSize,
            'offset': offset,
          },
        ),
      );
      result.addAll(page.map(UserQuestModel.fromJson));
      if (page.length < pageSize) return result;
    }
  }
}
