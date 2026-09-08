import 'src/json_coercions.dart';

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

  /// All of this member's media URLs — `[]` when there is no media, so a
  /// "waiting for member" slot renders as truly empty.
  List<String> get mediaUrls => decodeMediaUrls(mediaUrl);

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
      // Same rule as SubmissionModel.showInFeed: absent means the RPC did
      // not project the column (DB default is true), an unrecognisable
      // value fails closed to hidden.
      showInFeed: coerceBool(
        json['show_in_feed'],
        ifMissing: true,
        ifUnrecognised: false,
      ),
      voteCount: coerceInt(json['vote_count']),
      viewerVoted: coerceBool(json['viewer_voted'], ifMissing: false),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CollabFeedMember &&
        other.userId == userId &&
        other.username == username &&
        other.displayName == displayName &&
        other.avatarUrl == avatarUrl &&
        other.bio == bio &&
        other.submissionId == submissionId &&
        other.mediaUrl == mediaUrl &&
        other.mediaType == mediaType &&
        other.submissionStatus == submissionStatus &&
        other.caption == caption &&
        other.showInFeed == showInFeed &&
        other.voteCount == voteCount &&
        other.viewerVoted == viewerVoted;
  }

  @override
  int get hashCode => Object.hash(
        userId,
        username,
        displayName,
        avatarUrl,
        bio,
        submissionId,
        mediaUrl,
        mediaType,
        submissionStatus,
        caption,
        showInFeed,
        voteCount,
        viewerVoted,
      );
}
