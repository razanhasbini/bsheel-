import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:app_models/app_models.dart';
import 'package:supabase_contracts/supabase_contracts.dart';
import '../media/signed_media_urls.dart';
import 'comments_repository.dart';

class SupabaseCommentsRepository implements CommentsRepository {
  final SupabaseClient client;
  SupabaseCommentsRepository(this.client);

  @override
  Future<List<CommentModel>> getComments(String submissionId) async {
    final commentsData = await client
        .from(Tables.comments)
        .select(
          '${CommentColumns.id}, ${CommentColumns.submissionId}, '
          '${CommentColumns.userId}, ${CommentColumns.body}, '
          '${CommentColumns.createdAt}, ${CommentColumns.parentId}',
        )
        .eq(CommentColumns.submissionId, submissionId)
        .order(CommentColumns.createdAt, ascending: true) as List<dynamic>;

    if (commentsData.isEmpty) return [];

    final userIds = commentsData
        .map(
          (r) => (r as Map<String, dynamic>)[CommentColumns.userId] as String,
        )
        .toSet()
        .toList();

    final profilesData = await client
        .from(Tables.profiles)
        .select(
          '${ProfileColumns.id}, ${ProfileColumns.username}, '
          '${ProfileColumns.displayName}, ${ProfileColumns.avatarUrl}',
        )
        .inFilter(ProfileColumns.id, userIds) as List<dynamic>;

    final profileMap = <String, Map<String, dynamic>>{
      for (final p in profilesData)
        (p as Map<String, dynamic>)[ProfileColumns.id] as String: p,
    };

    final allComments = await Future.wait(
      commentsData.map((row) async {
        final r = Map<String, dynamic>.from(row as Map);
        final profile = profileMap[r[CommentColumns.userId] as String] ?? {};
        return CommentModel(
          id: (r[CommentColumns.id] ?? '').toString(),
          submissionId: (r[CommentColumns.submissionId] ?? '').toString(),
          userId: (r[CommentColumns.userId] ?? '').toString(),
          body: (r[CommentColumns.body] ?? '').toString(),
          createdAt: DateTime.parse(r[CommentColumns.createdAt] as String),
          username: (profile[ProfileColumns.username] ?? '').toString(),
          displayName: (profile[ProfileColumns.displayName] ?? '').toString(),
          avatarUrl: await SignedMediaUrls.signNullable(
            client,
            profile[ProfileColumns.avatarUrl] as String?,
          ),
          parentId: r[CommentColumns.parentId] as String?,
        );
      }),
    );

    // Build thread: top-level comments with nested replies
    final topLevel = <CommentModel>[];
    final repliesByParent = <String, List<CommentModel>>{};

    for (final c in allComments) {
      if (c.parentId == null) {
        topLevel.add(c);
      } else {
        repliesByParent.putIfAbsent(c.parentId!, () => []).add(c);
      }
    }

    return topLevel
        .map((c) => c.copyWithReplies(repliesByParent[c.id] ?? []))
        .toList();
  }

  @override
  Future<void> addComment(
    String submissionId,
    String text, {
    String? parentId,
  }) async {
    final user = client.auth.currentUser;
    if (user == null) throw Exception('Not authenticated');

    await client.from(Tables.comments).insert({
      CommentColumns.submissionId: submissionId,
      CommentColumns.userId: user.id,
      CommentColumns.body: text,
      if (parentId != null) CommentColumns.parentId: parentId,
    });
  }

  @override
  Future<void> deleteComment(String commentId) async {
    final user = client.auth.currentUser;
    if (user == null) throw Exception('Not authenticated');
    // RLS policy `delete_own_comments` (auth.uid() = user_id) ensures
    // the server rejects attempts to delete someone else's comment, so
    // we can issue the delete without re-checking ownership client-side.
    await client
        .from(Tables.comments)
        .delete()
        .eq(CommentColumns.id, commentId);
  }
}
