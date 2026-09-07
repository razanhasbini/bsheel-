/// Composite of a `saved_posts` row joined with submission + quest info.
/// Returned by the `get_user_saved_posts` RPC so the BSHEEEL list can
/// render in one round-trip without an N+1 detail fetch.
class SavedPostWithQuest {
  final String savedId;
  final DateTime savedAt;
  final String submissionId;
  final String mediaUrl;
  final String mediaType;
  final String visibility;
  final String status;
  final String questId;
  final String questTitle;
  final String questDescription;
  final String questCategory;
  final int xpReward;
  final String authorId;
  final String authorUsername;
  final String authorDisplayName;
  final String? authorAvatarUrl;

  const SavedPostWithQuest({
    required this.savedId,
    required this.savedAt,
    required this.submissionId,
    required this.mediaUrl,
    required this.mediaType,
    required this.visibility,
    required this.status,
    required this.questId,
    required this.questTitle,
    required this.questDescription,
    required this.questCategory,
    required this.xpReward,
    required this.authorId,
    required this.authorUsername,
    required this.authorDisplayName,
    this.authorAvatarUrl,
  });

  factory SavedPostWithQuest.fromRpc(Map<String, dynamic> json) {
    return SavedPostWithQuest(
      savedId: (json['saved_id'] ?? '').toString(),
      savedAt: DateTime.parse(json['saved_at'] as String),
      submissionId: (json['submission_id'] ?? '').toString(),
      mediaUrl: (json['media_url'] ?? '').toString(),
      mediaType: (json['media_type'] ?? 'image').toString(),
      visibility: (json['visibility'] ?? 'visible').toString(),
      status: (json['status'] ?? '').toString(),
      questId: (json['quest_id'] ?? '').toString(),
      questTitle: (json['quest_title'] ?? '').toString(),
      questDescription: (json['quest_description'] ?? '').toString(),
      questCategory: (json['quest_category'] ?? '').toString(),
      xpReward: _toInt(json['xp_reward']),
      authorId: (json['author_id'] ?? '').toString(),
      authorUsername: (json['author_username'] ?? '').toString(),
      authorDisplayName: (json['author_display_name'] ?? '').toString(),
      authorAvatarUrl: json['author_avatar_url'] as String?,
    );
  }

  static int _toInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }
}
