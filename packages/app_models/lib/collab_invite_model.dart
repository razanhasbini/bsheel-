/// Preview of a collab group before joining (returned by get_collab_group_details).
class CollabGroupPreviewModel {
  final String groupId;
  final String code;
  final String mode;
  final String status;
  final int memberCount;
  final int maxMembers;
  final DateTime expiresAt;
  final List<CollabGroupPreviewMember> members;
  final String questTitle;
  final String questDescription;
  final String questCategory;
  final String questDifficulty;
  final int questXpReward;
  final int questDurationHours;
  final String creatorUsername;
  final String creatorDisplayName;
  final String? creatorAvatarUrl;

  const CollabGroupPreviewModel({
    required this.groupId,
    required this.code,
    required this.mode,
    required this.status,
    required this.memberCount,
    required this.maxMembers,
    required this.expiresAt,
    required this.members,
    required this.questTitle,
    required this.questDescription,
    required this.questCategory,
    required this.questDifficulty,
    required this.questXpReward,
    required this.questDurationHours,
    required this.creatorUsername,
    required this.creatorDisplayName,
    this.creatorAvatarUrl,
  });

  factory CollabGroupPreviewModel.fromJson(Map<String, dynamic> json) {
    final membersList = json['members'] as List<dynamic>? ?? [];
    return CollabGroupPreviewModel(
      groupId: json['group_id'] as String,
      code: json['code'] as String,
      mode: json['mode'] as String,
      status: json['status'] as String,
      memberCount: (json['member_count'] as num?)?.toInt() ?? 0,
      maxMembers: (json['max_members'] as num?)?.toInt() ?? 5,
      expiresAt: DateTime.parse(json['expires_at'] as String),
      members: membersList
          .map((m) => CollabGroupPreviewMember.fromJson(m as Map<String, dynamic>))
          .toList(),
      questTitle: json['quest_title'] as String? ?? '',
      questDescription: json['quest_description'] as String? ?? '',
      questCategory: json['quest_category'] as String? ?? '',
      questDifficulty: json['quest_difficulty'] as String? ?? '',
      questXpReward: (json['quest_xp_reward'] as num?)?.toInt() ?? 10,
      questDurationHours: (json['quest_duration_hours'] as num?)?.toInt() ?? 4,
      creatorUsername: json['creator_username'] as String? ?? '',
      creatorDisplayName: json['creator_display_name'] as String? ?? '',
      creatorAvatarUrl: json['creator_avatar_url'] as String?,
    );
  }
}

class CollabGroupPreviewMember {
  final String userId;
  final String username;
  final String displayName;
  final String? avatarUrl;

  const CollabGroupPreviewMember({
    required this.userId,
    required this.username,
    required this.displayName,
    this.avatarUrl,
  });

  factory CollabGroupPreviewMember.fromJson(Map<String, dynamic> json) {
    return CollabGroupPreviewMember(
      userId: json['user_id'] as String,
      username: json['username'] as String? ?? '',
      displayName: json['display_name'] as String? ?? '',
      avatarUrl: json['avatar_url'] as String?,
    );
  }
}
