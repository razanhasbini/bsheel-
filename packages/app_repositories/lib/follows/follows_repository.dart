/// Lightweight profile summary used by follower/following lists.
typedef FollowProfile = ({
  String id,
  String username,
  String displayName,
  String? avatarUrl,
});

/// Follower + following counts for a user.
typedef FollowCounts = ({int followers, int following});

abstract class FollowsRepository {
  Future<bool> isFollowing(String targetUserId);
  /// Returns the new follow row ID.
  Future<String> follow(String targetUserId);
  Future<void> unfollow(String targetUserId);

  /// List the profiles `userId` is followed by (`isFollowers=true`)
  /// or following (`isFollowers=false`).
  Future<List<FollowProfile>> listConnections({
    required String userId,
    required bool isFollowers,
  });

  /// Returns how many users follow [userId] and how many [userId] follows.
  Future<FollowCounts> getFollowCounts(String userId);
}
