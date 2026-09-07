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
      isCollab: json['is_collab'] as bool? ?? false,
      groupId: json['group_id'] as String?,
      mode: json['mode'] as String?,
      status: json['status'] as String?,
      code: json['code'] as String?,
      maxMembers: (json['max_members'] as num?)?.toInt(),
      expiresAt: json['expires_at'] != null
          ? DateTime.parse(json['expires_at'] as String)
          : null,
      members: membersList
          .map((m) => CollabMemberStatus.fromJson(m as Map<String, dynamic>))
          .toList(),
    );
  }
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
      submissionTimeSeconds: (json['submission_time_seconds'] as num?)?.toInt(),
      voteCount: (json['vote_count'] as num?)?.toInt() ?? 0,
    );
  }
}
