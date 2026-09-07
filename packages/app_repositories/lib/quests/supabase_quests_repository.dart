import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:app_models/app_models.dart';
import 'package:supabase_contracts/supabase_contracts.dart';

import 'quests_repository.dart';

class SupabaseQuestsRepository implements QuestsRepository {
  final SupabaseClient _client;
  SupabaseQuestsRepository(this._client);

  @override
  Future<QuestModel> getQuest(String questId) async {
    final response = await _client
        .from(Tables.quests)
        .select()
        .eq(QuestColumns.id, questId)
        .single();

    return QuestModel.fromJson(Map<String, dynamic>.from(response));
  }

  @override
  Future<List<QuestModel>> listAllQuestsAdmin() async {
    final response = await _client
        .from(Tables.quests)
        .select()
        .order(QuestColumns.createdAt, ascending: false);

    return (response as List<dynamic>)
        .map((row) => QuestModel.fromJson(Map<String, dynamic>.from(row)))
        .toList();
  }

  @override
  Future<QuestModel> createQuest({
    required String title,
    required String description,
    required String category,
    required String difficulty,
    required int xpReward,
    int durationHours = 4,
    bool isActive = true,
  }) async {
    final uid = _client.auth.currentUser?.id;
    final data = await _client
        .from(Tables.quests)
        .insert({
          QuestColumns.title: title,
          QuestColumns.description: description,
          QuestColumns.category: category,
          QuestColumns.difficulty: difficulty,
          QuestColumns.xpReward: xpReward,
          QuestColumns.durationHours: durationHours,
          QuestColumns.isActive: isActive,
          if (uid != null) QuestColumns.createdBy: uid,
        })
        .select()
        .single();

    return QuestModel.fromJson(Map<String, dynamic>.from(data));
  }

  @override
  Future<QuestModel> updateQuest(QuestModel quest) async {
    final data = await _client
        .from(Tables.quests)
        .update({
          QuestColumns.title: quest.title,
          QuestColumns.description: quest.description,
          QuestColumns.category: quest.category,
          QuestColumns.difficulty: quest.difficulty,
          QuestColumns.xpReward: quest.xpReward,
          QuestColumns.durationHours: quest.durationHours,
          QuestColumns.isActive: quest.isActive,
        })
        .eq(QuestColumns.id, quest.id)
        .select()
        .single();

    return QuestModel.fromJson(Map<String, dynamic>.from(data));
  }

  @override
  Future<UserQuestModel?> getActiveUserQuest(String userId) async {
    // Server-side expiration is handled by the `expire-overdue-quests`
    // pg_cron job (every 5 min) plus the markQuestExpired safety net
    // below. Direct UPDATEs from the client are RLS-blocked for non-
    // admin users since 0055, so calling expireOverdueQuests here is
    // a silent no-op — removed (ARC-002).

    // Fetch both 'assigned' (in-progress) and 'submitted' (awaiting review).
    // 'submitted' quests should still show on the home screen until reviewed.
    final response = await _client
        .from(Tables.userQuests)
        .select('*, ${Tables.quests}(*)')
        .eq(UserQuestColumns.userId, userId)
        .inFilter(UserQuestColumns.status, [
          UserQuestStatus.assigned,
          UserQuestStatus.submitted,
        ])
        .order(UserQuestColumns.assignedAt, ascending: false)
        .limit(1);

    final rows = response as List<dynamic>;
    if (rows.isEmpty) return null;

    final userQuest =
        UserQuestModel.fromJson(Map<String, dynamic>.from(rows.first));

    // Safety net: if the DB update above didn't catch it yet (clock skew /
    // cached response), expire client-side and persist the status change.
    // Only apply to 'assigned' quests — 'submitted' quests have proof
    // already uploaded and must not be auto-expired even if time ran out.
    if (userQuest.status == UserQuestStatus.assigned &&
        userQuest.expiresAt != null &&
        DateTime.now().isAfter(userQuest.expiresAt!)) {
      await markQuestExpired(userQuest.id);
      return null;
    }

    return userQuest;
  }

  @override
  Future<void> markQuestExpired(String userQuestId) async {
    await _client.rpc(
      RpcNames.expireUserQuest,
      params: {ExpireUserQuestParams.userQuestId: userQuestId},
    );
  }

  @override
  Future<UserQuestModel> assignSpecificQuest(
    String userId,
    String questId,
  ) async {
    // The RPC has been live since 0014 with current grants in place.
    // The previous fallback path inserted directly into user_quests and
    // was RLS-blocked for non-admin users since 0055; surface the real
    // RPC error instead of running through dead code (ARC-002 / ARC-004).
    final response = await _client.rpc(
      RpcNames.assignSpecificQuest,
      params: {
        AssignSpecificQuestParams.userId: userId,
        AssignSpecificQuestParams.questId: questId,
      },
    );
    return _parseAssignedQuestResponse(response);
  }

  @override
  Future<void> expireOverdueQuests(String userId) async {
    // No-op: kept on the interface so existing callers + test fakes
    // don't need to change. The actual expiration runs via the
    // `expire-overdue-quests` pg_cron job (every 5 min) plus the
    // per-quest `markQuestExpired` safety net inside getActiveUserQuest.
    // Direct UPDATEs from the client were RLS-blocked since 0055.
    return;
  }

  @override
  Future<List<QuestModel>> getQuestPickerOptions({int count = 3}) async {
    final response = await _client.rpc(
      RpcNames.getQuestPickerOptions,
      params: {GetQuestPickerOptionsParams.count: count},
    );

    if (response is! List) return const <QuestModel>[];
    return response
        .whereType<dynamic>()
        .map(
          (row) => QuestModel.fromJson(Map<String, dynamic>.from(row as Map)),
        )
        .toList();
  }

  UserQuestModel _parseAssignedQuestResponse(dynamic response) {
    if (response is Map<String, dynamic>) {
      return UserQuestModel.fromJson(response);
    }

    if (response is Map) {
      return UserQuestModel.fromJson(Map<String, dynamic>.from(response));
    }

    if (response is List) {
      if (response.isEmpty) {
        throw StateError('Quest assignment returned no rows.');
      }
      final first = response.first;
      if (first is Map<String, dynamic>) {
        return UserQuestModel.fromJson(first);
      }
      if (first is Map) {
        return UserQuestModel.fromJson(Map<String, dynamic>.from(first));
      }
    }

    throw StateError(
      'Unexpected quest assignment response type: ${response.runtimeType}',
    );
  }

  @override
  Future<List<UserQuestModel>> getUserQuestHistory(String userId) async {
    final response = await _client
        .from(Tables.userQuests)
        .select('*, ${Tables.quests}(*)')
        .eq(UserQuestColumns.userId, userId)
        .order(UserQuestColumns.assignedAt, ascending: false);

    return (response as List<dynamic>)
        .map((row) => UserQuestModel.fromJson(Map<String, dynamic>.from(row)))
        .toList();
  }
}
