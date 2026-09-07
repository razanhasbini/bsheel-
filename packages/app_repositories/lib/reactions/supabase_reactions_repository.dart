import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:app_models/app_models.dart';
import 'package:supabase_contracts/supabase_contracts.dart';
import 'reactions_repository.dart';

class SupabaseReactionsRepository implements ReactionsRepository {
  final SupabaseClient client;
  SupabaseReactionsRepository(this.client);

  @override
  Future<ReactionModel?> getMyVote(String submissionId, String userId) async {
    final data = await client
        .from(Tables.reactions)
        .select()
        .eq(ReactionColumns.submissionId, submissionId)
        .eq(ReactionColumns.userId, userId)
        .maybeSingle();
    if (data == null) return null;
    return ReactionModel.fromJson(data);
  }

  @override
  Future<ReactionModel> vote(
    String submissionId,
    String userId,
    String type,
  ) async {
    if (type != ReactionType.upvote && type != ReactionType.downvote) {
      throw ArgumentError.value(type, 'type', 'must be upvote or downvote');
    }
    final data = await client
        .from(Tables.reactions)
        .upsert(
          {
            ReactionColumns.submissionId: submissionId,
            ReactionColumns.userId: userId,
            ReactionColumns.type: type,
          },
          onConflict: '${ReactionColumns.submissionId},${ReactionColumns.userId}',
        )
        .select()
        .single();
    return ReactionModel.fromJson(data);
  }

  @override
  Future<void> removeVote(String submissionId, String userId) async {
    await client
        .from(Tables.reactions)
        .delete()
        .eq(ReactionColumns.submissionId, submissionId)
        .eq(ReactionColumns.userId, userId);
  }
}
