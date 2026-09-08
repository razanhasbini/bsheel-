import 'src/json_coercions.dart';
import 'src/value_equality.dart';

/// Full status of a collab group (returned by get_collab_group_status).
class CollabGroupStatusModel {
  final bool isCollab;
  final String? groupId;
  final String? mode;
  final String? status;
  final String? code;
  final int? maxMembers;
  final DateTime? expiresAt;
  final List<CollabMemberStatus> members;

  const CollabGroupStatusModel({
    required this.isCollab,
    this.groupId,
    this.mode,
    this.status,
    this.code,
    this.maxMembers,
    this.expiresAt,
    this.members = const [],
  });

  factory CollabGroupStatusModel.fromJson(Map<String, dynamic> json) {
    final membersList = json['members'] as List<dynamic>? ?? [];
    return CollabGroupStatusModel(
      isCollab: coerceBool(json['is_collab'], ifMissing: false),
      groupId: json['group_id'] as String?,
      mode: json['mode'] as String?,
      status: json['status'] as String?,
      code: json['code'] as String?,
      maxMembers: coerceNullableInt(json['max_members']),
      // Optional timestamp: an unparseable value degrades this one field to
      // null instead of throwing a FormatException that loses the whole
      // collab status.
      expiresAt: coerceNullableTimestamp(json['expires_at']),
      members: membersList
          .map((m) => CollabMemberStatus.fromJson(m as Map<String, dynamic>))
          .toList(),
    );
  }

  /// The [members] list is bounded by the collab party size, so
  /// element-wise equality stays cheap.
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CollabGroupStatusModel &&
        other.isCollab == isCollab &&
        other.groupId == groupId &&
        other.mode == mode &&
        other.status == status &&
        other.code == code &&
        other.maxMembers == maxMembers &&
        other.expiresAt == expiresAt &&
        listEquals(other.members, members);
  }

  @override
  int get hashCode => Object.hashAll([
        isCollab,
        groupId,
        mode,
        status,
        code,
        maxMembers,
        expiresAt,
        ...members,
      ]);
}

class CollabMemberStatus {
  final String userId;
  final String username;
  final String displayName;
  final String? avatarUrl;
  final String? questStatus;
  final String? submissionStatus;
  final int? submissionTimeSeconds;
  final int voteCount;

  const CollabMemberStatus({
    required this.userId,
    required this.username,
    required this.displayName,
    this.avatarUrl,
    this.questStatus,
    this.submissionStatus,
    this.submissionTimeSeconds,
    this.voteCount = 0,
  });

  factory CollabMemberStatus.fromJson(Map<String, dynamic> json) {
    return CollabMemberStatus(
      userId: json['user_id'] as String,
      username: json['username'] as String? ?? '',
      displayName: json['display_name'] as String? ?? '',
      avatarUrl: json['avatar_url'] as String?,
      questStatus: json['quest_status'] as String?,
      submissionStatus: json['submission_status'] as String?,
      // Nullable on purpose: "no submission" has to stay distinguishable
      // from "submitted instantly" for the versus timing display.
      submissionTimeSeconds: coerceNullableInt(json['submission_time_seconds']),
      voteCount: coerceInt(json['vote_count']),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CollabMemberStatus &&
        other.userId == userId &&
        other.username == username &&
        other.displayName == displayName &&
        other.avatarUrl == avatarUrl &&
        other.questStatus == questStatus &&
        other.submissionStatus == submissionStatus &&
        other.submissionTimeSeconds == submissionTimeSeconds &&
        other.voteCount == voteCount;
  }

  @override
  int get hashCode => Object.hash(
        userId,
        username,
        displayName,
        avatarUrl,
        questStatus,
        submissionStatus,
        submissionTimeSeconds,
        voteCount,
      );
}
