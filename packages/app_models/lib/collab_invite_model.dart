import 'src/json_coercions.dart';
import 'src/value_equality.dart';

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
      // `coerceInt`, not `as num?`: this used to be a hard cast that threw
      // on the '2' PostgREST sends for a bigint count, where QuestModel
      // would have parsed it.
      memberCount: coerceInt(json['member_count']),
      // 5 is the party-size cap the join screen assumes.
      maxMembers: coerceInt(json['max_members'], defaultValue: 5),
      expiresAt: coerceTimestamp(json['expires_at']),
      members: membersList
          .map((m) =>
              CollabGroupPreviewMember.fromJson(m as Map<String, dynamic>))
          .toList(),
      questTitle: json['quest_title'] as String? ?? '',
      questDescription: json['quest_description'] as String? ?? '',
      questCategory: json['quest_category'] as String? ?? '',
      questDifficulty: json['quest_difficulty'] as String? ?? '',
      questXpReward: coerceInt(json['quest_xp_reward'], defaultValue: 10),
      // Clamped to the same 1..168 range as QuestModel — see
      // [normalizeQuestDurationHours]. This model used to apply no bounds.
      questDurationHours:
          normalizeQuestDurationHours(json['quest_duration_hours']),
      creatorUsername: json['creator_username'] as String? ?? '',
      creatorDisplayName: json['creator_display_name'] as String? ?? '',
      creatorAvatarUrl: json['creator_avatar_url'] as String?,
    );
  }

  /// The [members] list is bounded by [maxMembers] (a handful), so
  /// element-wise equality stays cheap.
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CollabGroupPreviewModel &&
        other.groupId == groupId &&
        other.code == code &&
        other.mode == mode &&
        other.status == status &&
        other.memberCount == memberCount &&
        other.maxMembers == maxMembers &&
        other.expiresAt == expiresAt &&
        other.questTitle == questTitle &&
        other.questDescription == questDescription &&
        other.questCategory == questCategory &&
        other.questDifficulty == questDifficulty &&
        other.questXpReward == questXpReward &&
        other.questDurationHours == questDurationHours &&
        other.creatorUsername == creatorUsername &&
        other.creatorDisplayName == creatorDisplayName &&
        other.creatorAvatarUrl == creatorAvatarUrl &&
        listEquals(other.members, members);
  }

  @override
  int get hashCode => Object.hashAll([
        groupId,
        code,
        mode,
        status,
        memberCount,
        maxMembers,
        expiresAt,
        questTitle,
        questDescription,
        questCategory,
        questDifficulty,
        questXpReward,
        questDurationHours,
        creatorUsername,
        creatorDisplayName,
        creatorAvatarUrl,
        ...members,
      ]);
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

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CollabGroupPreviewMember &&
        other.userId == userId &&
        other.username == username &&
        other.displayName == displayName &&
        other.avatarUrl == avatarUrl;
  }

  @override
  int get hashCode => Object.hash(userId, username, displayName, avatarUrl);
}
