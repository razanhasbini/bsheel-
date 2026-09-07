import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:app_models/app_models.dart';
import 'package:supabase_contracts/supabase_contracts.dart';
import 'saved_posts_repository.dart';

class SupabaseSavedPostsRepository implements SavedPostsRepository {
  final SupabaseClient client;
  SupabaseSavedPostsRepository(this.client);

  @override
  Future<List<SavedPostModel>> getSavedPosts(String userId) async {
    final data = await client
        .from(Tables.savedPosts)
        .select()
        .eq(SavedPostColumns.userId, userId)
        .order(SavedPostColumns.createdAt, ascending: false);
    return (data as List<dynamic>)
        .map((row) => SavedPostModel.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<List<SavedPostWithQuest>> getSavedPostsWithQuests(String userId) async {
    // Use the get_user_saved_posts RPC — it joins quest + author + media
    // server-side and respects the visibility filter (excludes deleted
    // submissions). Returns the full SavedPostWithQuest model from
    // app_models, not the 3-field stub.
    final result = await client.rpc(
      RpcNames.getUserSavedPosts,
      params: {'p_user_id': userId},
    );
    final list = (result as List<dynamic>?) ?? const [];
    return list
        .map((row) => SavedPostWithQuest.fromRpc(row as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<bool> isPostSaved(String submissionId, String userId) async {
    final data = await client
        .from(Tables.savedPosts)
        .select(SavedPostColumns.id)
        .eq(SavedPostColumns.submissionId, submissionId)
        .eq(SavedPostColumns.userId, userId)
        .maybeSingle();
    return data != null;
  }

  @override
  Future<void> savePost(String submissionId, String userId) async {
    await client.from(Tables.savedPosts).upsert(
      {
        SavedPostColumns.submissionId: submissionId,
        SavedPostColumns.userId: userId,
      },
      onConflict: '${SavedPostColumns.userId},${SavedPostColumns.submissionId}',
    );
  }

  @override
  Future<void> unsavePost(String submissionId, String userId) async {
    await client
        .from(Tables.savedPosts)
        .delete()
        .eq(SavedPostColumns.submissionId, submissionId)
        .eq(SavedPostColumns.userId, userId);
  }
}
