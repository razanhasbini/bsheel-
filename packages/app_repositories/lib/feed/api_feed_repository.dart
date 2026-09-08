import 'package:app_models/app_models.dart';

import '../api/api_client.dart';
import '../media/api_media_signer.dart';
import 'feed_repository.dart';

class ApiFeedRepository implements FeedRepository {
  ApiFeedRepository(this._client) : _media = ApiMediaSigner(_client);

  final ApiClient _client;
  final ApiMediaSigner _media;

  @override
  Future<List<FeedPostModel>> getFeed({
    int limit = 20,
    int offset = 0,
    String sort = 'recent',
    FeedScope scope = FeedScope.all,
  }) async {
    final rows = apiObjectList(
      await _client.get(
        'feed',
        query: {
          'limit': limit,
          'offset': offset,
          'sort': sort,
          'scope': scope.rpcValue,
        },
      ),
    );
    return _signPosts(rows.map(FeedPostModel.fromRpc).toList());
  }

  @override
  Future<FeedPostModel> getFeedPostDetails(String submissionId) async {
    final row = apiObject(await _client.get('submissions/$submissionId'));
    final normalized = <String, dynamic>{
      ...row,
      'submission_id': row['id'],
      'user_id': row['user_id'],
      'username': row['author_username'],
      'display_name': row['author_display_name'],
      'quest_id': row['quest_id'],
      'quest_title': row['quest_title'],
      'quest_description': row['quest_description'],
      'quest_category': row['quest_category'],
      'upvote_count': row['upvote_count'] ?? 0,
      'downvote_count': row['downvote_count'] ?? 0,
      'net_score': row['net_score'] ?? 0,
    };
    final signed = await _signPosts([FeedPostModel.fromRpc(normalized)]);
    return signed.single;
  }

  Future<List<FeedPostModel>> _signPosts(List<FeedPostModel> posts) async {
    return Future.wait(
      posts.map((post) async {
        final signedMedia = await _media.signJsonOrSingle(post.mediaUrl);
        final signedAvatar = await _media.signNullable(post.avatarUrl);
        final members = await Future.wait(
          post.collabMembers.map((member) async {
            return member.copyWith(
              mediaUrl: member.mediaUrl == null
                  ? null
                  : await _media.signJsonOrSingle(member.mediaUrl!),
              avatarUrl: await _media.signNullable(member.avatarUrl),
            );
          }),
        );
        return post.copyWith(
          mediaUrl: signedMedia,
          avatarUrl: signedAvatar,
          collabMembers: members,
        );
      }),
    );
  }
}
