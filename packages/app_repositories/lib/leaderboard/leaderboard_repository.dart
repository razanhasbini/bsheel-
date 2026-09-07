import 'package:app_models/app_models.dart';

abstract class LeaderboardRepository {
  Future<List<LeaderboardUserModel>> getLeaderboard({int limit = 50});
  Future<List<LeaderboardUserModel>> getFollowingLeaderboard({int limit = 50});
}
