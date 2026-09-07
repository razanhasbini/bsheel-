import 'dart:convert';

/// Represents one member's data in a collab feed post.
class CollabFeedMember {
  final String userId;
  final String username;
  final String displayName;
  final String? avatarUrl;
  final String? bio;
  final String? submissionId;
  final String? mediaUrl;
  final String? mediaType;
  final String? submissionStatus;
  final String? caption;
  final bool showInFeed;
  final int voteCount;
  final bool viewerVoted;

  const CollabFeedMember({
    required this.userId,
    required this.username,
    required this.displayName,
    this.avatarUrl,
    this.bio,
    this.submissionId,
    this.mediaUrl,
    this.mediaType,
    this.submissionStatus,
    this.caption,
    this.showInFeed = true,
    this.voteCount = 0,
    this.viewerVoted = false,
  });

  CollabFeedMember copyWith({
    String? avatarUrl,
    String? mediaUrl,
    int? voteCount,
    bool? viewerVoted,
  }) {
    return CollabFeedMember(
      userId: userId,
      username: username,
      displayName: displayName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      bio: bio,
      submissionId: submissionId,
      mediaUrl: mediaUrl ?? this.mediaUrl,
      mediaType: mediaType,
      submissionStatus: submissionStatus,
      caption: caption,
      showInFeed: showInFeed,
      voteCount: voteCount ?? this.voteCount,
      viewerVoted: viewerVoted ?? this.viewerVoted,
    );
  }

  List<String> get mediaUrls {
    if (mediaUrl == null || mediaUrl!.isEmpty) return [];
    final trimmed = mediaUrl!.trim();
    if (trimmed.startsWith('[')) {
      try {
        return List<String>.from(jsonDecode(trimmed) as List);
      } catch (_) {}
    }
    return [mediaUrl!];
  }

  factory CollabFeedMember.fromJson(Map<String, dynamic> json) {
    return CollabFeedMember(
      userId: json['user_id'] as String,
      username: json['username'] as String? ?? '',
      displayName: json['display_name'] as String? ?? '',
      avatarUrl: json['avatar_url'] as String?,
      bio: json['bio'] as String?,
      submissionId: json['submission_id'] as String?,
      mediaUrl: json['media_url'] as String?,
      mediaType: json['media_type'] as String?,
      submissionStatus: json['submission_status'] as String?,
      caption: json['caption'] as String?,
      showInFeed: json['show_in_feed'] as bool? ?? true,
      voteCount: (json['vote_count'] as num?)?.toInt() ?? 0,
      viewerVoted: json['viewer_voted'] as bool? ?? false,
    );
  }
}
