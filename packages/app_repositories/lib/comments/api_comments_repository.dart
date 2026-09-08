import 'package:app_models/app_models.dart';

import '../api/api_client.dart';
import '../media/api_media_signer.dart';
import 'comments_repository.dart';

class ApiCommentsRepository implements CommentsRepository {
  ApiCommentsRepository(this._client) : _media = ApiMediaSigner(_client);

  final ApiClient _client;
  final ApiMediaSigner _media;

  @override
  Future<List<CommentModel>> getComments(String submissionId) async {
    final rows = <Map<String, dynamic>>[];
    const pageSize = 200;
    for (var offset = 0;; offset += pageSize) {
      final page = apiObjectList(
        await _client.get(
          'social/posts/$submissionId/comments',
          query: {'limit': pageSize, 'offset': offset},
        ),
      );
      rows.addAll(page);
      if (page.length < pageSize) break;
    }
    final signed = await _media.signMany(
      rows.map((row) => row['avatar_url']?.toString() ?? ''),
    );
    final comments = rows.map((row) {
      final avatar = row['avatar_url']?.toString();
      return CommentModel.fromJson({
        ...row,
        'avatar_url': avatar == null ? null : signed[avatar] ?? avatar,
      });
    }).toList(growable: false);
    final replies = <String, List<CommentModel>>{};
    final topLevel = <CommentModel>[];
    for (final comment in comments) {
      final parentId = comment.parentId;
      if (parentId == null) {
        topLevel.add(comment);
      } else {
        replies.putIfAbsent(parentId, () => []).add(comment);
      }
    }
    return topLevel
        .map(
          (comment) => comment.copyWithReplies(replies[comment.id] ?? const []),
        )
        .toList(growable: false);
  }

  @override
  Future<void> addComment(
    String submissionId,
    String text, {
    String? parentId,
  }) async {
    await _client.post(
      'social/posts/$submissionId/comments',
      body: {
        'body': text,
        if (parentId != null) 'parentId': parentId,
      },
    );
  }

  @override
  Future<void> deleteComment(String commentId) async {
    await _client.delete('social/comments/$commentId');
  }
}
