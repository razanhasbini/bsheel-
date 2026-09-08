import 'package:app_contracts/app_contracts.dart';

import 'src/json_coercions.dart';

/// A comment, plus the reply subtree a caller has threaded onto it.
///
/// Deliberately the one model in this package with NO `==` / `hashCode`:
/// [replies] is a recursive tree, so value equality would walk the whole
/// thread on every comparison and its depth is unbounded. Riverpod would
/// pay that cost on each rebuild check to save a rebuild of a list that the
/// repository rebuilds wholesale anyway, so identity equality is the
/// cheaper trade here.
class CommentModel {
  final String id;
  final String submissionId;
  final String userId;
  final String body;
  final DateTime createdAt;
  final String username;
  final String displayName;
  final String? avatarUrl;
  final String? parentId;
  final List<CommentModel> replies;

  const CommentModel({
    required this.id,
    required this.submissionId,
    required this.userId,
    required this.body,
    required this.createdAt,
    required this.username,
    required this.displayName,
    this.avatarUrl,
    this.parentId,
    this.replies = const [],
  });

  factory CommentModel.fromJson(Map<String, dynamic> json) {
    // `coerceEmbed` so the array-shaped PostgREST embed parses too — this
    // used to be a hard `as Map<String, dynamic>?` cast that threw on it
    // while SubmissionModel tolerated both shapes.
    final profile = coerceEmbed(json['profiles!comments_user_id_fkey']) ??
        coerceEmbed(json[EmbedKeys.profiles]);

    return CommentModel(
      id: (json[CommentColumns.id] ?? '').toString(),
      submissionId: (json[CommentColumns.submissionId] ?? '').toString(),
      userId: (json[CommentColumns.userId] ?? '').toString(),
      body: (json[CommentColumns.body] ?? '').toString(),
      createdAt: coerceTimestamp(json[CommentColumns.createdAt]),
      username: (profile?[ProfileColumns.username] ?? json['username'] ?? '')
          .toString(),
      displayName:
          (profile?[ProfileColumns.displayName] ?? json['display_name'] ?? '')
              .toString(),
      avatarUrl:
          (profile?[ProfileColumns.avatarUrl] ?? json['avatar_url']) as String?,
      parentId: json[CommentColumns.parentId] as String?,
    );
  }

  CommentModel copyWithReplies(List<CommentModel> replies) {
    return CommentModel(
      id: id,
      submissionId: submissionId,
      userId: userId,
      body: body,
      createdAt: createdAt,
      username: username,
      displayName: displayName,
      avatarUrl: avatarUrl,
      parentId: parentId,
      replies: replies,
    );
  }
}
