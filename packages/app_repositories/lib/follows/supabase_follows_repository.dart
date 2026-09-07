import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:supabase_contracts/supabase_contracts.dart';
import '../media/signed_media_urls.dart';
import 'follows_repository.dart';

class SupabaseFollowsRepository implements FollowsRepository {
  final SupabaseClient client;
  SupabaseFollowsRepository(this.client);

  @override
  Future<bool> isFollowing(String targetUserId) async {
    final user = client.auth.currentUser;
    if (user == null) return false;

    final data = await client
        .from(Tables.follows)
        .select(FollowColumns.id)
        .eq(FollowColumns.followerId, user.id)
        .eq(FollowColumns.followingId, targetUserId)
        .maybeSingle();

    return data != null;
  }

  @override
  Future<String> follow(String targetUserId) async {
    final user = client.auth.currentUser;
    if (user == null) throw Exception('Not authenticated');

    final data = await client
        .from(Tables.follows)
        .insert({
          FollowColumns.followerId: user.id,
          FollowColumns.followingId: targetUserId,
        })
        .select(FollowColumns.id)
        .single();

    return data[FollowColumns.id] as String;
  }

  @override
  Future<void> unfollow(String targetUserId) async {
    final user = client.auth.currentUser;
    if (user == null) throw Exception('Not authenticated');

    await client
        .from(Tables.follows)
        .delete()
        .eq(FollowColumns.followerId, user.id)
        .eq(FollowColumns.followingId, targetUserId);
  }

  @override
  Future<List<FollowProfile>> listConnections({
    required String userId,
    required bool isFollowers,
  }) async {
    // Followers: rows where following_id = userId, fetch their follower_id.
    // Following: rows where follower_id = userId, fetch their following_id.
    final idColumn =
        isFollowers ? FollowColumns.followerId : FollowColumns.followingId;
    final filterColumn =
        isFollowers ? FollowColumns.followingId : FollowColumns.followerId;

    final followRows = await client
        .from(Tables.follows)
        .select(idColumn)
        .eq(filterColumn, userId);
    final userIds = (followRows as List<dynamic>)
        .map((r) => (r as Map<String, dynamic>)[idColumn] as String)
        .toSet()
        .toList();
    if (userIds.isEmpty) return const [];

    final profiles = await client
        .from(Tables.profiles)
        .select('${ProfileColumns.id}, ${ProfileColumns.username}, '
            '${ProfileColumns.displayName}, ${ProfileColumns.avatarUrl}')
        .inFilter(ProfileColumns.id, userIds);

    return Future.wait(
      (profiles as List<dynamic>).map((p) async {
        final m = p as Map<String, dynamic>;
        return (
          id: (m[ProfileColumns.id] ?? '') as String,
          username: (m[ProfileColumns.username] ?? '') as String,
          displayName: (m[ProfileColumns.displayName] ?? '') as String,
          avatarUrl: await SignedMediaUrls.signNullable(
            client,
            m[ProfileColumns.avatarUrl] as String?,
          ),
        );
      }),
    );
  }

  @override
  Future<FollowCounts> getFollowCounts(String userId) async {
    // followers = rows where the user is the *target* (following_id)
    // following = rows where the user is the *initiator* (follower_id)
    // Issue both counts in parallel; halves profile-load latency.
    final results = await Future.wait([
      client
          .from(Tables.follows)
          .count(CountOption.exact)
          .eq(FollowColumns.followingId, userId),
      client
          .from(Tables.follows)
          .count(CountOption.exact)
          .eq(FollowColumns.followerId, userId),
    ]);
    return (followers: results[0], following: results[1]);
  }
}
