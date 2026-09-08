import 'package:supabase_contracts/supabase_contracts.dart';

import 'src/json_coercions.dart';

class AdminModel {
  final String id;
  final String userId;
  final String role;
  final DateTime createdAt;

  const AdminModel({
    required this.id,
    required this.userId,
    required this.role,
    required this.createdAt,
  });

  factory AdminModel.fromJson(Map<String, dynamic> json) {
    return AdminModel(
      id: (json[AdminColumns.id] ?? '').toString(),
      userId: (json[AdminColumns.userId] ?? '').toString(),
      role: (json[AdminColumns.role] as String?) ?? AdminRole.moderator,
      createdAt: coerceTimestamp(json[AdminColumns.createdAt]),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      AdminColumns.id: id,
      AdminColumns.userId: userId,
      AdminColumns.role: role,
      AdminColumns.createdAt: createdAt.toIso8601String(),
    };
  }

  bool get isSuperAdmin => role == AdminRole.superAdmin;
  bool get isModerator => role == AdminRole.moderator;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AdminModel &&
        other.id == id &&
        other.userId == userId &&
        other.role == role &&
        other.createdAt == createdAt;
  }

  @override
  int get hashCode => Object.hash(id, userId, role, createdAt);
}
