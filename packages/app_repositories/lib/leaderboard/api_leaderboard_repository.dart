import 'package:app_models/app_models.dart';

import '../api/api_client.dart';
import '../media/api_media_signer.dart';
import 'leaderboard_repository.dart';

class ApiLeaderboardRepository implements LeaderboardRepository {
  ApiLeaderboardRepository(this._client) : _media = ApiMediaSigner(_client);

  final ApiClient _client;
  final ApiMediaSigner _media;

  @override
  Future<List<LeaderboardUserModel>> getLeaderboard({int limit = 50}) =>
      _list('global', limit);

  @override
  Future<List<LeaderboardUserModel>> getFollowingLeaderboard(
          {int limit = 50,}) =>
      _list('following', limit);

  Future<List<LeaderboardUserModel>> _list(String scope, int limit) async {
    final rows = apiObjectList(await _client.get('leaderboard', query: {
      'scope': scope,
      'limit': limit,
      'offset': 0,
    },),);
    final signed = await _media.signMany(
      rows.map((row) => row['avatar_url']?.toString() ?? ''),
    );
    return rows.map((row) {
      final avatar = row['avatar_url']?.toString();
      return LeaderboardUserModel.fromJson({
        ...row,
        'avatar_url': avatar == null ? null : signed[avatar] ?? avatar,
      });
    }).toList(growable: false);
  }
}
