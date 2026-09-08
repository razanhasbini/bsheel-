import 'package:supabase_contracts/supabase_contracts.dart';

import 'src/json_coercions.dart';

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
    // `coerceEmbed` so the array-shaped PostgREST embed parses too — this
    // used to be a hard `as Map<String, dynamic>?` cast that threw on it
    // while SubmissionModel tolerated both shapes.
    final actorProfile = coerceEmbed(json['actor_profile']) ??
        coerceEmbed(json[Tables.profiles]);
    return NotificationModel(
      id: (json[NotificationColumns.id] ?? '').toString(),
      userId: (json[NotificationColumns.userId] ?? '').toString(),
      title: (json[NotificationColumns.title] ?? '').toString(),
      body: (json[NotificationColumns.body] ?? '').toString(),
      type: (json[NotificationColumns.type] ?? '').toString(),
      referenceId: json[NotificationColumns.referenceId] as String?,
      isRead: coerceBool(json[NotificationColumns.isRead], ifMissing: false),
      createdAt: coerceTimestamp(json[NotificationColumns.createdAt]),
      actorId: json[NotificationColumns.actorId] as String?,
      actorAvatarUrl: actorProfile?[ProfileColumns.avatarUrl] as String?,
      actorUsername: actorProfile?[ProfileColumns.username] as String?,
    );
  }

  /// Serialises every own column [fromJson] reads, `actor_id` included — it
  /// used to be dropped, so a notification cached through `toJson` came
  /// back with no actor and rendered without an avatar. The joined
  /// `actorUsername` / `actorAvatarUrl` are deliberately absent: they live
  /// on `profiles`, not on this row.
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
      NotificationColumns.actorId: actorId,
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

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is NotificationModel &&
        other.id == id &&
        other.userId == userId &&
        other.title == title &&
        other.body == body &&
        other.type == type &&
        other.referenceId == referenceId &&
        other.isRead == isRead &&
        other.createdAt == createdAt &&
        other.actorId == actorId &&
        other.actorAvatarUrl == actorAvatarUrl &&
        other.actorUsername == actorUsername;
  }

  @override
  int get hashCode => Object.hash(
        id,
        userId,
        title,
        body,
        type,
        referenceId,
        isRead,
        createdAt,
        actorId,
        actorAvatarUrl,
        actorUsername,
      );
}
