import 'package:supabase_contracts/supabase_contracts.dart';

class NotificationModel {
  final String id;
  final String userId;
  final String title;
  final String body;
  final String type;
  final String? referenceId;
  final bool isRead;
  final DateTime createdAt;
  final String? actorId;
  final String? actorAvatarUrl;
  final String? actorUsername;

  const NotificationModel({
    required this.id,
    required this.userId,
    required this.title,
    required this.body,
    required this.type,
    this.referenceId,
    this.isRead = false,
    required this.createdAt,
    this.actorId,
    this.actorAvatarUrl,
    this.actorUsername,
  });

  factory NotificationModel.fromJson(Map<String, dynamic> json) {
    final actorProfile =
        (json['actor_profile'] ?? json[Tables.profiles]) as Map<String, dynamic>?;
    return NotificationModel(
      id: (json[NotificationColumns.id] ?? '').toString(),
      userId: (json[NotificationColumns.userId] ?? '').toString(),
      title: (json[NotificationColumns.title] ?? '').toString(),
      body: (json[NotificationColumns.body] ?? '').toString(),
      type: (json[NotificationColumns.type] ?? '').toString(),
      referenceId: json[NotificationColumns.referenceId] as String?,
      isRead: (json[NotificationColumns.isRead] as bool?) ?? false,
      createdAt: _toDateTime(json[NotificationColumns.createdAt]),
      actorId: json[NotificationColumns.actorId] as String?,
      actorAvatarUrl: actorProfile?['avatar_url'] as String?,
      actorUsername: actorProfile?['username'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      NotificationColumns.id: id,
      NotificationColumns.userId: userId,
      NotificationColumns.title: title,
      NotificationColumns.body: body,
      NotificationColumns.type: type,
      NotificationColumns.referenceId: referenceId,
      NotificationColumns.isRead: isRead,
      NotificationColumns.createdAt: createdAt.toIso8601String(),
    };
  }

  NotificationModel copyWith({bool? isRead}) {
    return NotificationModel(
      id: id,
      userId: userId,
      title: title,
      body: body,
      type: type,
      referenceId: referenceId,
      isRead: isRead ?? this.isRead,
      createdAt: createdAt,
      actorId: actorId,
      actorAvatarUrl: actorAvatarUrl,
      actorUsername: actorUsername,
    );
  }

  static DateTime _toDateTime(dynamic value) {
    if (value is DateTime) return value;
    return DateTime.parse(value as String);
  }
}
