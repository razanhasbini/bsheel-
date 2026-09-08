import 'package:supabase_contracts/supabase_contracts.dart';

import 'quest_model.dart';
import 'src/json_coercions.dart';

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
      assignedAt: coerceTimestamp(json[UserQuestColumns.assignedAt]),
      completedAt: coerceNullableTimestamp(
        json[UserQuestColumns.completedAt],
      ),
      expiresAt: coerceNullableTimestamp(
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
    final joinedQuest = coerceEmbed(json[Tables.quests]);
    return joinedQuest == null ? null : QuestModel.fromJson(joinedQuest);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is UserQuestModel &&
        other.id == id &&
        other.userId == userId &&
        other.questId == questId &&
        other.status == status &&
        other.assignedAt == assignedAt &&
        other.completedAt == completedAt &&
        other.expiresAt == expiresAt &&
        other.quest == quest;
  }

  @override
  int get hashCode => Object.hash(
        id,
        userId,
        questId,
        status,
        assignedAt,
        completedAt,
        expiresAt,
        quest,
      );
}
