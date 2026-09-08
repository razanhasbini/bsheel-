import 'package:supabase_contracts/supabase_contracts.dart';

import 'src/json_coercions.dart';

class ReactionModel {
  final String id;
  final String submissionId;
  final String userId;
  final String type;
  final DateTime createdAt;

  const ReactionModel({
    required this.id,
    required this.submissionId,
    required this.userId,
    required this.type,
    required this.createdAt,
  });

  factory ReactionModel.fromJson(Map<String, dynamic> json) {
    return ReactionModel(
      id: (json[ReactionColumns.id] ?? '').toString(),
      submissionId: (json[ReactionColumns.submissionId] ?? '').toString(),
      userId: (json[ReactionColumns.userId] ?? '').toString(),
      type: (json[ReactionColumns.type] ?? '').toString(),
      createdAt: coerceTimestamp(json[ReactionColumns.createdAt]),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      ReactionColumns.id: id,
      ReactionColumns.submissionId: submissionId,
      ReactionColumns.userId: userId,
      ReactionColumns.type: type,
      ReactionColumns.createdAt: createdAt.toIso8601String(),
    };
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ReactionModel &&
        other.id == id &&
        other.submissionId == submissionId &&
        other.userId == userId &&
        other.type == type &&
        other.createdAt == createdAt;
  }

  @override
  int get hashCode => Object.hash(id, submissionId, userId, type, createdAt);
}
