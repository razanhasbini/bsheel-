import 'package:supabase_contracts/supabase_contracts.dart';

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
    this.durationHours = 4,
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
      xpReward: _toInt(json[QuestColumns.xpReward]),
      durationHours: _normalizeDurationHours(
        _toInt(json[QuestColumns.durationHours]),
      ),
      isActive: json[QuestColumns.isActive] as bool? ?? true,
      createdBy: json[QuestColumns.createdBy] as String?,
      createdAt: _toDateTime(
        json[QuestColumns.createdAt],
      ),
      updatedAt: _toNullableDateTime(
        json[QuestColumns.updatedAt],
      ),
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

  static int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static int _normalizeDurationHours(int value) {
    if (value < 1) return 4;
    return value;
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
