import 'package:supabase_contracts/supabase_contracts.dart';

import 'quest_model.dart';

class UserQuestModel {
  final String id;
  final String userId;
  final String questId;
  final String status;
  final DateTime assignedAt;
  final DateTime? completedAt;
  final DateTime? expiresAt;
  final QuestModel? quest;

  const UserQuestModel({
    required this.id,
    required this.userId,
    required this.questId,
    required this.status,
    required this.assignedAt,
    this.completedAt,
    this.expiresAt,
    this.quest,
  });

  factory UserQuestModel.fromJson(Map<String, dynamic> json) {
    return UserQuestModel(
      id: (json[UserQuestColumns.id] ?? '').toString(),
      userId: (json[UserQuestColumns.userId] ?? '').toString(),
      questId: (json[UserQuestColumns.questId] ?? '').toString(),
      status: (json[UserQuestColumns.status] ?? '').toString(),
      assignedAt: _toDateTime(
        json[UserQuestColumns.assignedAt],
      ),
      completedAt: _toNullableDateTime(
        json[UserQuestColumns.completedAt],
      ),
      expiresAt: _toNullableDateTime(
        json[UserQuestColumns.expiresAt],
      ),
      quest: _parseQuest(json),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      UserQuestColumns.id: id,
      UserQuestColumns.userId: userId,
      UserQuestColumns.questId: questId,
      UserQuestColumns.status: status,
      UserQuestColumns.assignedAt: assignedAt.toIso8601String(),
      UserQuestColumns.completedAt: completedAt?.toIso8601String(),
      UserQuestColumns.expiresAt: expiresAt?.toIso8601String(),
      if (quest != null) Tables.quests: quest!.toJson(),
    };
  }

  static QuestModel? _parseQuest(Map<String, dynamic> json) {
    final joinedQuest = json[Tables.quests];
    if (joinedQuest is Map<String, dynamic>) {
      return QuestModel.fromJson(joinedQuest);
    }
    if (joinedQuest is List && joinedQuest.isNotEmpty) {
      final first = joinedQuest.first;
      if (first is Map<String, dynamic>) {
        return QuestModel.fromJson(first);
      }
    }
    return null;
  }

  static DateTime _toDateTime(dynamic value) {
    if (value is DateTime) return value;
    return DateTime.parse(value as String);
  }

  static DateTime? _toNullableDateTime(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    return DateTime.parse(value as String);
  }
}
