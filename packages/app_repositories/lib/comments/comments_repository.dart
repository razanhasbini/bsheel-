import 'package:app_models/app_models.dart';

abstract class CommentsRepository {
  /// Fetch all comments for [submissionId] with author profile fields
  /// in a single JOIN query (no N+1).
  Future<List<CommentModel>> getComments(String submissionId);

  /// Insert a new comment on [submissionId] with [text] as the body.
  /// If [parentId] is provided, the comment is a reply to that comment.
  Future<void> addComment(String submissionId, String text, {String? parentId});

  /// Delete a comment owned by the current user. UX-107.
  /// RLS policy `delete_own_comments` enforces ownership server-side.
  Future<void> deleteComment(String commentId);
}
