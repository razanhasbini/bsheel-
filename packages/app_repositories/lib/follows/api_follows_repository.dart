import '../api/api_client.dart';
import '../media/api_media_signer.dart';
import 'follows_repository.dart';

class ApiFollowsRepository implements FollowsRepository {
  ApiFollowsRepository(this._client) : _media = ApiMediaSigner(_client);

  final ApiClient _client;
  final ApiMediaSigner _media;

  @override
  Future<bool> isFollowing(String targetUserId) async {
    final data = apiObject(
      await _client.get('social/users/$targetUserId/following'),
    );
    return data['following'] == true;
  }

  @override
  Future<String> follow(String targetUserId) async {
    final data = apiObject(
      await _client.post('social/users/$targetUserId/follow'),
    );
    return data['id'] as String;
  }

  @override
  Future<void> unfollow(String targetUserId) async {
    await _client.delete('social/users/$targetUserId/follow');
  }

  @override
  Future<List<FollowProfile>> listConnections({
    required String userId,
    required bool isFollowers,
  }) async {
    final rows = <Map<String, dynamic>>[];
    const pageSize = 100;
    for (var offset = 0;; offset += pageSize) {
      final page = apiObjectList(await _client.get(
        'social/users/$userId/connections',
        query: {
          'followers': isFollowers,
          'limit': pageSize,
          'offset': offset,
        },
      ),);
      rows.addAll(page);
      if (page.length < pageSize) break;
    }
    final signed = await _media.signMany(
      rows.map((row) => row['avatar_url']?.toString() ?? ''),
    );
    return rows.map((row) {
      final avatar = row['avatar_url']?.toString();
      return (
        id: row['id'].toString(),
        username: row['username']?.toString() ?? '',
        displayName: row['display_name']?.toString() ?? '',
        avatarUrl: avatar == null ? null : signed[avatar] ?? avatar,
      );
    }).toList(growable: false);
  }

  @override
  Future<FollowCounts> getFollowCounts(String userId) async {
    final data = apiObject(
      await _client.get('social/users/$userId/follow-counts'),
    );
    return (
      followers: (data['followers'] as num?)?.toInt() ?? 0,
      following: (data['following'] as num?)?.toInt() ?? 0,
    );
  }
}
