import 'package:supabase_contracts/supabase_contracts.dart';

import 'src/json_coercions.dart';

class SavedPostModel {
  final String id;
  final String userId;
  final String submissionId;
  final DateTime createdAt;

  const SavedPostModel({
    required this.id,
    required this.userId,
    required this.submissionId,
    required this.createdAt,
  });

  factory SavedPostModel.fromJson(Map<String, dynamic> json) {
    return SavedPostModel(
      id: (json[SavedPostColumns.id] ?? '').toString(),
      userId: (json[SavedPostColumns.userId] ?? '').toString(),
      submissionId: (json[SavedPostColumns.submissionId] ?? '').toString(),
      createdAt: coerceTimestamp(json[SavedPostColumns.createdAt]),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SavedPostModel &&
        other.id == id &&
        other.userId == userId &&
        other.submissionId == submissionId &&
        other.createdAt == createdAt;
  }

  @override
  int get hashCode => Object.hash(id, userId, submissionId, createdAt);
}
