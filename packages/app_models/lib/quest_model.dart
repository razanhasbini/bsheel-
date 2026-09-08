import 'package:app_contracts/app_contracts.dart';

import 'src/json_coercions.dart';

class QuestModel {
  final String id;
  final String title;
  final String description;
  final String category;
  final String difficulty;
  final int xpReward;
  final int durationHours;
  final bool isActive;
  final String? createdBy;
  final DateTime createdAt;
  final DateTime? updatedAt;

  const QuestModel({
    required this.id,
    required this.title,
    required this.description,
    required this.category,
    required this.difficulty,
    required this.xpReward,
    this.durationHours = defaultQuestDurationHours,
    this.isActive = true,
    this.createdBy,
    required this.createdAt,
    this.updatedAt,
  });

  factory QuestModel.fromJson(Map<String, dynamic> json) {
    return QuestModel(
      id: (json[QuestColumns.id] ?? '').toString(),
      title: (json[QuestColumns.title] ?? '').toString(),
      description: (json[QuestColumns.description] ?? '').toString(),
      category: (json[QuestColumns.category] ?? '').toString(),
      difficulty: (json[QuestColumns.difficulty] ?? '').toString(),
      xpReward: coerceInt(json[QuestColumns.xpReward]),
      durationHours: normalizeQuestDurationHours(
        json[QuestColumns.durationHours],
      ),
      isActive: coerceBool(json[QuestColumns.isActive], ifMissing: true),
      createdBy: json[QuestColumns.createdBy] as String?,
      createdAt: coerceTimestamp(json[QuestColumns.createdAt]),
      updatedAt: coerceNullableTimestamp(json[QuestColumns.updatedAt]),
    );
  }

  QuestModel copyWith({
    String? title,
    String? description,
    String? category,
    String? difficulty,
    int? xpReward,
    int? durationHours,
    bool? isActive,
  }) {
    return QuestModel(
      id: id,
      title: title ?? this.title,
      description: description ?? this.description,
      category: category ?? this.category,
      difficulty: difficulty ?? this.difficulty,
      xpReward: xpReward ?? this.xpReward,
      // Re-normalised here too, not only in fromJson: a caller that passed
      // 0 (or 100000) used to be able to build a quest the wire could
      // never produce and the DB CHECK would have rejected.
      durationHours: durationHours == null
          ? this.durationHours
          : normalizeQuestDurationHours(durationHours),
      isActive: isActive ?? this.isActive,
      createdBy: createdBy,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      QuestColumns.id: id,
      QuestColumns.title: title,
      QuestColumns.description: description,
      QuestColumns.category: category,
      QuestColumns.difficulty: difficulty,
      QuestColumns.xpReward: xpReward,
      QuestColumns.durationHours: durationHours,
      QuestColumns.isActive: isActive,
      QuestColumns.createdBy: createdBy,
      QuestColumns.createdAt: createdAt.toIso8601String(),
      QuestColumns.updatedAt: updatedAt?.toIso8601String(),
    };
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is QuestModel &&
        other.id == id &&
        other.title == title &&
        other.description == description &&
        other.category == category &&
        other.difficulty == difficulty &&
        other.xpReward == xpReward &&
        other.durationHours == durationHours &&
        other.isActive == isActive &&
        other.createdBy == createdBy &&
        other.createdAt == createdAt &&
        other.updatedAt == updatedAt;
  }

  @override
  int get hashCode => Object.hash(
        id,
        title,
        description,
        category,
        difficulty,
        xpReward,
        durationHours,
        isActive,
        createdBy,
        createdAt,
        updatedAt,
      );
}
