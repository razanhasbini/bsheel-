import 'package:supabase_contracts/supabase_contracts.dart';

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
    final profile = (json['profiles!comments_user_id_fkey'] ??
        json[Tables.profiles]) as Map<String, dynamic>?;

    return CommentModel(
      id: (json[CommentColumns.id] ?? '').toString(),
      submissionId: (json[CommentColumns.submissionId] ?? '').toString(),
      userId: (json[CommentColumns.userId] ?? '').toString(),
      body: (json[CommentColumns.body] ?? '').toString(),
      createdAt: DateTime.parse(json[CommentColumns.createdAt] as String),
      username: (profile?[ProfileColumns.username] ??
              json['username'] ??
              '')
          .toString(),
      displayName: (profile?[ProfileColumns.displayName] ??
              json['display_name'] ??
              '')
          .toString(),
      avatarUrl: (profile?[ProfileColumns.avatarUrl] ??
          json['avatar_url']) as String?,
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
