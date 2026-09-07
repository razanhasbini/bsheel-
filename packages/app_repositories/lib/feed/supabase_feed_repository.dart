import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:app_models/app_models.dart';
import 'package:supabase_contracts/supabase_contracts.dart';
import '../media/signed_media_urls.dart';
import 'feed_repository.dart';

class SupabaseFeedRepository implements FeedRepository {
  final SupabaseClient client;
  SupabaseFeedRepository(this.client);

  @override
  Future<List<FeedPostModel>> getFeed({
    int limit = 20,
    int offset = 0,
    String sort = 'recent',
    FeedScope scope = FeedScope.all,
  }) async {
    final rpcData = await client.rpc(
      RpcNames.getFeed,
      params: {
        'p_limit': limit,
        'p_offset': offset,
        'p_sort': sort,
        'p_scope': scope.rpcValue,
      },
    ) as List<dynamic>;

    if (rpcData.isEmpty) return [];

    final posts = rpcData
        .map((row) => FeedPostModel.fromRpc(row as Map<String, dynamic>))
        .toList();
    return Future.wait(posts.map(_withSignedMedia));
  }

  @override
  Future<FeedPostModel> getFeedPostDetails(String submissionId) async {
    final rpcResult = await client.rpc(
      RpcNames.getSubmissionDetail,
      params: {'p_submission_id': submissionId},
    ) as List<dynamic>;

    if (rpcResult.isEmpty) {
      throw StateError('Submission $submissionId not found');
    }
    final row = rpcResult.first as Map<String, dynamic>;
    final upvotes = _toInt(row[FeedRpcColumns.upvoteCount]);
    final downvotes = _toInt(row[FeedRpcColumns.downvoteCount]);

    final membersRaw = row[CollabFeedRpcColumns.collabMembers];
    final List<CollabFeedMember> members;
    if (membersRaw is List) {
      members = membersRaw
          .map((m) => CollabFeedMember.fromJson(m as Map<String, dynamic>))
          .toList();
    } else {
      members = const [];
    }

    return _withSignedMedia(
      FeedPostModel(
        id: (row[FeedRpcColumns.submissionId] ?? '').toString(),
        mediaUrl: (row[SubmissionColumns.mediaUrl] ?? '').toString(),
        mediaType:
            (row[SubmissionColumns.mediaType] as String?) ?? MediaType.image,
        caption: row[SubmissionColumns.caption] as String?,
        submittedAt:
            DateTime.parse(row[SubmissionColumns.submittedAt] as String),
        userId: (row[FeedRpcColumns.userId] ?? '').toString(),
        username: (row[ProfileColumns.username] ?? '').toString(),
        displayName: (row[ProfileColumns.displayName] ?? '').toString(),
        avatarUrl: row[ProfileColumns.avatarUrl] as String?,
        bio: row[ProfileColumns.bio] as String?,
        questId: (row[FeedRpcColumns.questId] ?? '').toString(),
        questTitle: (row[FeedRpcColumns.questTitle] ?? '').toString(),
        questDescription:
            (row[FeedRpcColumns.questDescription] ?? '').toString(),
        questCategory: (row[FeedRpcColumns.questCategory] ?? '').toString(),
        xpReward: _toInt(row[FeedRpcColumns.xpReward]),
        upvoteCount: upvotes,
        downvoteCount: downvotes,
        netScore: _toInt(row[FeedRpcColumns.netScore]),
        showInFeed: row[SubmissionColumns.showInFeed] != false,
        visibility: (row[SubmissionColumns.visibility] as String?) ??
            SubmissionVisibility.visible,
        isCollab: row[CollabFeedRpcColumns.isCollab] as bool? ?? false,
        collabGroupId: row[CollabFeedRpcColumns.collabGroupId] as String?,
        collabMode: row[CollabFeedRpcColumns.collabMode] as String?,
        collabMemberCount: _toInt(row[CollabFeedRpcColumns.collabMemberCount]),
        collabMembers: members,
        expiresAt: _toNullableDateTime(row['expires_at']),
      ),
    );
  }

  Future<FeedPostModel> _withSignedMedia(FeedPostModel post) async {
    final signedMediaUrl = await SignedMediaUrls.signJsonOrSingle(
      client,
      post.mediaUrl,
    );
    final signedAvatarUrl = await SignedMediaUrls.signNullable(
      client,
      post.avatarUrl,
    );
    final signedMembers = await Future.wait(
      post.collabMembers.map((member) async {
        final mediaUrl = member.mediaUrl == null
            ? null
            : await SignedMediaUrls.signJsonOrSingle(client, member.mediaUrl!);
        final avatarUrl = await SignedMediaUrls.signNullable(
          client,
          member.avatarUrl,
        );
        return member.copyWith(mediaUrl: mediaUrl, avatarUrl: avatarUrl);
      }),
    );

    return post.copyWith(
      mediaUrl: signedMediaUrl,
      avatarUrl: signedAvatarUrl,
      collabMembers: signedMembers,
    );
  }

  static DateTime? _toNullableDateTime(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    return DateTime.tryParse(value.toString());
  }

  static int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}
