import 'package:app_contracts/app_contracts.dart';

import 'collab_feed_member.dart';
import 'src/json_coercions.dart';
import 'src/value_equality.dart';

/// Represents an enriched feed post from the get_feed RPC or a detail join query.
/// Combines submission data with profile info and quest info.
class FeedPostModel {
  final String id;
  final String mediaUrl;
  final String mediaType;
  final String? caption;
  final DateTime submittedAt;
  final String userId;
  final String username;
  final String displayName;
  final String? avatarUrl;
  final String? bio;
  final String questId;
  final String questTitle;
  final String questDescription;
  final String questCategory;
  final int xpReward;
  final int upvoteCount;
  final int downvoteCount;
  final int netScore;
  final double hotScore;
  final bool showInFeed;
  final String visibility;

  // Collab group fields
  final bool isCollab;
  final String? collabGroupId;
  final String? collabMode;
  final int collabMemberCount;
  final List<CollabFeedMember> collabMembers;

  /// When the post-owner's quest expires. Used by the collab "WAITING FOR"
  /// placeholder to flip its copy to "DIDN'T POST" once now > expires_at.
  /// Null for legacy rows or pre-0116 RPC clients.
  final DateTime? expiresAt;

  /// The viewer's own vote (`upvote`/`downvote`), or null when they have not
  /// voted. Comes with the row, so no per-card request is needed.
  final String? viewerVote;

  /// Whether the viewer saved this post. Comes with the row.
  final bool viewerSaved;

  /// Comment count. Comes with the row; the client used to fetch every
  /// comment to count them.
  final int commentCount;

  /// Keyset cursor for this row. Pass the last one to `?cursor=` for the next
  /// page — offset paging duplicates and skips cards when scores move.
  final String? nextCursor;

  const FeedPostModel({
    required this.id,
    required this.mediaUrl,
    required this.mediaType,
    this.caption,
    required this.submittedAt,
    required this.userId,
    required this.username,
    required this.displayName,
    this.avatarUrl,
    this.bio,
    required this.questId,
    required this.questTitle,
    this.questDescription = '',
    required this.questCategory,
    this.xpReward = 0,
    this.upvoteCount = 0,
    this.downvoteCount = 0,
    this.netScore = 0,
    this.hotScore = 0.0,
    this.showInFeed = true,
    this.visibility = SubmissionVisibility.visible,
    this.isCollab = false,
    this.collabGroupId,
    this.collabMode,
    this.collabMemberCount = 0,
    this.collabMembers = const [],
    this.expiresAt,
    this.viewerVote,
    this.viewerSaved = false,
    this.commentCount = 0,
    this.nextCursor,
  });

  /// Parse from the get_feed RPC response row.
  factory FeedPostModel.fromRpc(Map<String, dynamic> json) {
    final membersRaw = json[CollabFeedRpcColumns.collabMembers];
    final List<CollabFeedMember> members;
    if (membersRaw is List) {
      members = membersRaw
          .map((m) => CollabFeedMember.fromJson(m as Map<String, dynamic>))
          .toList();
    } else {
      members = const [];
    }

    return FeedPostModel(
      id: (json[FeedRpcColumns.submissionId] ?? '').toString(),
      mediaUrl: (json[SubmissionColumns.mediaUrl] ?? '').toString(),
      mediaType:
          (json[SubmissionColumns.mediaType] as String?) ?? MediaType.image,
      caption: json[SubmissionColumns.caption] as String?,
      submittedAt: coerceTimestamp(json[SubmissionColumns.submittedAt]),
      userId: (json[FeedRpcColumns.userId] ?? '').toString(),
      username: (json[ProfileColumns.username] ?? '').toString(),
      displayName: (json[ProfileColumns.displayName] ?? '').toString(),
      avatarUrl: json[ProfileColumns.avatarUrl] as String?,
      bio: json[ProfileColumns.bio] as String?,
      questId: (json[FeedRpcColumns.questId] ?? '').toString(),
      questTitle: (json[FeedRpcColumns.questTitle] ?? '').toString(),
      questDescription:
          (json[FeedRpcColumns.questDescription] ?? '').toString(),
      questCategory: (json[FeedRpcColumns.questCategory] ?? '').toString(),
      xpReward: coerceInt(json[FeedRpcColumns.xpReward]),
      upvoteCount: coerceInt(json[FeedRpcColumns.upvoteCount]),
      viewerVote: json[FeedRpcColumns.viewerVote] as String?,
      viewerSaved: json[FeedRpcColumns.viewerSaved] == true,
      commentCount: coerceInt(json[FeedRpcColumns.commentCount]),
      nextCursor: json[FeedRpcColumns.nextCursor]?.toString(),
      downvoteCount: coerceInt(json[FeedRpcColumns.downvoteCount]),
      netScore: coerceInt(json[FeedRpcColumns.netScore]),
      hotScore: coerceDouble(json[FeedRpcColumns.hotScore]),
      isCollab: coerceBool(
        json[CollabFeedRpcColumns.isCollab],
        ifMissing: false,
      ),
      collabGroupId: json[CollabFeedRpcColumns.collabGroupId] as String?,
      collabMode: json[CollabFeedRpcColumns.collabMode] as String?,
      collabMemberCount:
          coerceInt(json[CollabFeedRpcColumns.collabMemberCount]),
      collabMembers: members,
      expiresAt: coerceNullableTimestamp(json['expires_at']),
    );
  }

  /// Returns all media URLs. Handles both a single URL string and a
  /// JSON-encoded array (used when multiple files are uploaded). An empty
  /// `media_url` yields `[]`, not `['']`.
  List<String> get mediaUrls => decodeMediaUrls(mediaUrl);

  FeedPostModel copyWith({
    String? mediaUrl,
    String? avatarUrl,
    List<CollabFeedMember>? collabMembers,
    int? upvoteCount,
    String? viewerVote,
    bool? viewerSaved,
    int? commentCount,
    String? nextCursor,
    int? downvoteCount,
    int? netScore,
  }) {
    return FeedPostModel(
      id: id,
      mediaUrl: mediaUrl ?? this.mediaUrl,
      mediaType: mediaType,
      caption: caption,
      submittedAt: submittedAt,
      userId: userId,
      username: username,
      displayName: displayName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      bio: bio,
      questId: questId,
      questTitle: questTitle,
      questDescription: questDescription,
      questCategory: questCategory,
      xpReward: xpReward,
      upvoteCount: upvoteCount ?? this.upvoteCount,
      viewerVote: viewerVote ?? this.viewerVote,
      viewerSaved: viewerSaved ?? this.viewerSaved,
      commentCount: commentCount ?? this.commentCount,
      nextCursor: nextCursor ?? this.nextCursor,
      downvoteCount: downvoteCount ?? this.downvoteCount,
      netScore: netScore ?? this.netScore,
      hotScore: hotScore,
      showInFeed: showInFeed,
      visibility: visibility,
      isCollab: isCollab,
      collabGroupId: collabGroupId,
      collabMode: collabMode,
      collabMemberCount: collabMemberCount,
      collabMembers: collabMembers ?? this.collabMembers,
      // `expiresAt` is not a copyWith parameter on purpose — nothing varies
      // it — but it MUST be forwarded. Omitting it reset the field to null on
      // every optimistic vote, which broke the collab
      // "WAITING FOR" -> "DIDN'T POST" flip that reads it.
      expiresAt: expiresAt,
    );
  }

  /// Value equality despite the [collabMembers] list: the list is bounded by
  /// the collab party size (`max_members`, at most a handful) and members
  /// are themselves cheap value objects, so the comparison stays O(1)-ish.
  /// This is the class where equality pays off most — the feed re-fetches
  /// the same rows constantly and identity equality rebuilt every tile.
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is FeedPostModel &&
        other.id == id &&
        other.mediaUrl == mediaUrl &&
        other.mediaType == mediaType &&
        other.caption == caption &&
        other.submittedAt == submittedAt &&
        other.userId == userId &&
        other.username == username &&
        other.displayName == displayName &&
        other.avatarUrl == avatarUrl &&
        other.bio == bio &&
        other.questId == questId &&
        other.questTitle == questTitle &&
        other.questDescription == questDescription &&
        other.questCategory == questCategory &&
        other.xpReward == xpReward &&
        other.upvoteCount == upvoteCount &&
        other.downvoteCount == downvoteCount &&
        other.netScore == netScore &&
        other.hotScore == hotScore &&
        other.showInFeed == showInFeed &&
        other.visibility == visibility &&
        other.isCollab == isCollab &&
        other.collabGroupId == collabGroupId &&
        other.collabMode == collabMode &&
        other.collabMemberCount == collabMemberCount &&
        other.expiresAt == expiresAt &&
        listEquals(other.collabMembers, collabMembers);
  }

  @override
  int get hashCode => Object.hashAll([
        id,
        mediaUrl,
        mediaType,
        caption,
        submittedAt,
        userId,
        username,
        displayName,
        avatarUrl,
        bio,
        questId,
        questTitle,
        questDescription,
        questCategory,
        xpReward,
        upvoteCount,
        downvoteCount,
        netScore,
        hotScore,
        showInFeed,
        visibility,
        isCollab,
        collabGroupId,
        collabMode,
        collabMemberCount,
        expiresAt,
        ...collabMembers,
      ]);
}
