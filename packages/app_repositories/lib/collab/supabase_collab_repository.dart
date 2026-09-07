import 'package:app_models/app_models.dart';
import 'package:supabase_contracts/supabase_contracts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'collab_repository.dart';

class SupabaseCollabRepository implements CollabRepository {
  final SupabaseClient _client;

  SupabaseCollabRepository(this._client);

  @override
  Future<Map<String, dynamic>> createGroup(String userQuestId, String mode) async {
    final result = await _client.rpc(
      RpcNames.createCollabGroup,
      params: {'p_user_quest_id': userQuestId, 'p_mode': mode},
    );
    return Map<String, dynamic>.from(result as Map);
  }

  @override
  Future<CollabGroupPreviewModel> getGroupDetails(String code) async {
    final result = await _client.rpc(
      RpcNames.getCollabGroupDetails,
      params: {'p_code': code},
    );
    return CollabGroupPreviewModel.fromJson(Map<String, dynamic>.from(result as Map));
  }

  @override
  Future<Map<String, dynamic>> joinGroup(String code) async {
    final result = await _client.rpc(
      RpcNames.joinCollabGroup,
      params: {'p_code': code},
    );
    return Map<String, dynamic>.from(result as Map);
  }

  @override
  Future<CollabGroupStatusModel> getGroupStatus(String userQuestId) async {
    final result = await _client.rpc(
      RpcNames.getCollabGroupStatus,
      params: {'p_user_quest_id': userQuestId},
    );
    return CollabGroupStatusModel.fromJson(Map<String, dynamic>.from(result as Map));
  }

  @override
  Future<void> abandonQuest(String userQuestId) async {
    await _client.rpc(
      RpcNames.abandonQuest,
      params: {'p_user_quest_id': userQuestId},
    );
  }

  @override
  Future<void> voteCollab(String groupId, String submissionId) async {
    await _client.rpc(
      RpcNames.voteCollab,
      params: {'p_group_id': groupId, 'p_submission_id': submissionId},
    );
  }

  @override
  Future<void> unvoteCollab(String groupId, String submissionId) async {
    await _client.rpc(
      RpcNames.unvoteCollab,
      params: {'p_group_id': groupId, 'p_submission_id': submissionId},
    );
  }
}
