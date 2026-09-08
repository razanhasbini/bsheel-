import 'package:app_models/app_models.dart';

import '../api/api_client.dart';
import '../media/api_media_signer.dart';
import 'saved_posts_repository.dart';

class ApiSavedPostsRepository implements SavedPostsRepository {
  ApiSavedPostsRepository(this._client) : _media = ApiMediaSigner(_client);

  final ApiClient _client;
  final ApiMediaSigner _media;

  Future<List<Map<String, dynamic>>> _rows() async {
    final rows = <Map<String, dynamic>>[];
    const pageSize = 100;
    for (var offset = 0;; offset += pageSize) {
      final page = apiObjectList(
        await _client.get(
          'social/saved/posts',
          query: {'limit': pageSize, 'offset': offset},
        ),
      );
      rows.addAll(page);
      if (page.length < pageSize) return rows;
    }
  }

  @override
  Future<List<SavedPostModel>> getSavedPosts(String userId) async {
    return (await _rows())
        .map(
          (row) => SavedPostModel.fromJson({
            'id': row['saved_id'],
            'user_id': userId,
            'submission_id': row['submission_id'],
            'created_at': row['saved_at'],
          }),
        )
        .toList(growable: false);
  }

  @override
  Future<List<SavedPostWithQuest>> getSavedPostsWithQuests(
    String userId,
  ) async {
    final rows = await _rows();
    final signed = await _media.signMany([
      ...rows.map((row) => row['author_avatar_url']?.toString() ?? ''),
    ]);
    return Future.wait(
      rows.map((row) async {
        final media = row['media_url']?.toString() ?? '';
        final avatar = row['author_avatar_url']?.toString();
        return SavedPostWithQuest.fromRpc({
          ...row,
          'media_url': await _media.signJsonOrSingle(media),
          'author_avatar_url': avatar == null ? null : signed[avatar] ?? avatar,
        });
      }),
    );
  }

  @override
  Future<bool> isPostSaved(String submissionId, String userId) async {
    final data = apiObject(
      await _client.get('social/saved/posts/$submissionId'),
    );
    return data['saved'] == true;
  }

  @override
  Future<void> savePost(String submissionId, String userId) async {
    await _client.put('social/saved/posts/$submissionId');
  }

  @override
  Future<void> unsavePost(String submissionId, String userId) async {
    await _client.delete('social/saved/posts/$submissionId');
  }
}
