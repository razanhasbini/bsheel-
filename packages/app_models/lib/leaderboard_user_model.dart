import 'package:supabase_contracts/supabase_contracts.dart';

class LeaderboardUserModel {
  final int rank;
  final String userId;
  final String username;
  final String displayName;
  final String? avatarUrl;
  final int xp;
  final int level;
  final int questsCompleted;

  const LeaderboardUserModel({
    required this.rank,
    required this.userId,
    required this.username,
    required this.displayName,
    this.avatarUrl,
    required this.xp,
    required this.level,
    this.questsCompleted = 0,
  });

  factory LeaderboardUserModel.fromJson(Map<String, dynamic> json) {
    return LeaderboardUserModel(
      rank: _toInt(json[LeaderboardRpcColumns.rank]),
      userId: (json[LeaderboardRpcColumns.userId] ?? '').toString(),
      username: (json[ProfileColumns.username] ?? '').toString(),
      displayName: (json[ProfileColumns.displayName] ?? '').toString(),
      avatarUrl: json[ProfileColumns.avatarUrl] as String?,
      xp: _toInt(json[ProfileColumns.xp]),
      level: _toInt(json[ProfileColumns.level]),
      questsCompleted: _toInt(json[ProfileColumns.questsCompleted]),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      LeaderboardRpcColumns.rank: rank,
      LeaderboardRpcColumns.userId: userId,
      ProfileColumns.username: username,
      ProfileColumns.displayName: displayName,
      ProfileColumns.avatarUrl: avatarUrl,
      ProfileColumns.xp: xp,
      ProfileColumns.level: level,
      ProfileColumns.questsCompleted: questsCompleted,
    };
  }

  static int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}
