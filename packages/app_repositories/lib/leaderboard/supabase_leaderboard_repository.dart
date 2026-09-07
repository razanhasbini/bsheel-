import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:app_models/app_models.dart';
import 'package:supabase_contracts/supabase_contracts.dart';
import 'leaderboard_repository.dart';

class SupabaseLeaderboardRepository implements LeaderboardRepository {
  final SupabaseClient client;
  SupabaseLeaderboardRepository(this.client);

  @override
  Future<List<LeaderboardUserModel>> getLeaderboard({int limit = 50}) async {
    final data = await client.rpc(
      RpcNames.getLeaderboard,
      params: {'p_limit': limit},
    ) as List<dynamic>;
    return data
        .map(
          (row) =>
              LeaderboardUserModel.fromJson(row as Map<String, dynamic>),
        )
        .toList();
  }

  @override
  Future<List<LeaderboardUserModel>> getFollowingLeaderboard({
    int limit = 50,
  }) async {
    final data = await client.rpc(
      RpcNames.getFollowingLeaderboard,
      params: {'p_limit': limit},
    ) as List<dynamic>;
    return data
        .map(
          (row) =>
              LeaderboardUserModel.fromJson(row as Map<String, dynamic>),
        )
        .toList();
  }
}
