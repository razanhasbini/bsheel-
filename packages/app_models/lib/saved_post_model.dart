import 'package:supabase_contracts/supabase_contracts.dart';

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
      createdAt: _toDateTime(json[SavedPostColumns.createdAt]),
    );
  }

  static DateTime _toDateTime(dynamic value) {
    if (value is DateTime) return value;
    return DateTime.parse(value as String);
  }
}
