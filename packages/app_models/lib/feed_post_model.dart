import 'dart:convert';
import 'package:supabase_contracts/supabase_contracts.dart';
import 'collab_feed_member.dart';

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
    this.visibility = 'visible',
    this.isCollab = false,
    this.collabGroupId,
    this.collabMode,
    this.collabMemberCount = 0,
    this.collabMembers = const [],
    this.expiresAt,
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
      submittedAt: _toDateTime(json[SubmissionColumns.submittedAt]),
      userId: (json[FeedRpcColumns.userId] ?? '').toString(),
      username: (json[ProfileColumns.username] ?? '').toString(),
      displayName: (json[ProfileColumns.displayName] ?? '').toString(),
      avatarUrl: json[ProfileColumns.avatarUrl] as String?,
      bio: json[ProfileColumns.bio] as String?,
      questId: (json[FeedRpcColumns.questId] ?? '').toString(),
      questTitle: (json[FeedRpcColumns.questTitle] ?? '').toString(),
      questDescription: (json[FeedRpcColumns.questDescription] ?? '').toString(),
      questCategory: (json[FeedRpcColumns.questCategory] ?? '').toString(),
      xpReward: _toInt(json[FeedRpcColumns.xpReward]),
      upvoteCount: _toInt(json[FeedRpcColumns.upvoteCount]),
      downvoteCount: _toInt(json[FeedRpcColumns.downvoteCount]),
      netScore: _toInt(json[FeedRpcColumns.netScore]),
      hotScore: _toDouble(json[FeedRpcColumns.hotScore]),
      isCollab: json[CollabFeedRpcColumns.isCollab] as bool? ?? false,
      collabGroupId: json[CollabFeedRpcColumns.collabGroupId] as String?,
      collabMode: json[CollabFeedRpcColumns.collabMode] as String?,
      collabMemberCount: _toInt(json[CollabFeedRpcColumns.collabMemberCount]),
      collabMembers: members,
      expiresAt: _toNullableDateTime(json['expires_at']),
    );
  }

  /// Returns all media URLs. Handles both a single URL string and a
  /// JSON-encoded array (used when multiple files are uploaded).
  List<String> get mediaUrls {
    final trimmed = mediaUrl.trim();
    if (trimmed.startsWith('[')) {
      try {
        return List<String>.from(jsonDecode(trimmed) as List);
      } catch (_) {}
    }
    return [mediaUrl];
  }

  FeedPostModel copyWith({
    String? mediaUrl,
    String? avatarUrl,
    List<CollabFeedMember>? collabMembers,
    int? upvoteCount,
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
    );
  }

  static double _toDouble(dynamic value) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0.0;
  }

  static int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static DateTime _toDateTime(dynamic value) {
    if (value is DateTime) return value;
    return DateTime.parse(value as String);
  }

  static DateTime? _toNullableDateTime(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    return DateTime.tryParse(value.toString());
  }
}
