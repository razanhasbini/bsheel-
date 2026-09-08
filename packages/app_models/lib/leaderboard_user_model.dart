import 'package:supabase_contracts/supabase_contracts.dart';

import 'src/json_coercions.dart';

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
      rank: coerceInt(json[LeaderboardRpcColumns.rank]),
      userId: (json[LeaderboardRpcColumns.userId] ?? '').toString(),
      username: (json[ProfileColumns.username] ?? '').toString(),
      displayName: (json[ProfileColumns.displayName] ?? '').toString(),
      avatarUrl: json[ProfileColumns.avatarUrl] as String?,
      xp: coerceInt(json[ProfileColumns.xp]),
      // Same default as ProfileModel — see [defaultLevel]. This used to
      // fall back to 0, so a NULL level read "LVL 0" here and "LVL 1" on
      // the same user's profile.
      level: coerceInt(json[ProfileColumns.level], defaultValue: defaultLevel),
      questsCompleted: coerceInt(json[ProfileColumns.questsCompleted]),
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

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is LeaderboardUserModel &&
        other.rank == rank &&
        other.userId == userId &&
        other.username == username &&
        other.displayName == displayName &&
        other.avatarUrl == avatarUrl &&
        other.xp == xp &&
        other.level == level &&
        other.questsCompleted == questsCompleted;
  }

  @override
  int get hashCode => Object.hash(
        rank,
        userId,
        username,
        displayName,
        avatarUrl,
        xp,
        level,
        questsCompleted,
      );
}
