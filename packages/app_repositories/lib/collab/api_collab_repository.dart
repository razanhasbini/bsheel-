import 'package:app_models/app_models.dart';

import '../api/api_client.dart';
import 'collab_repository.dart';

class ApiCollabRepository implements CollabRepository {
  const ApiCollabRepository(this._client);

  final ApiClient _client;

  @override
  Future<Map<String, dynamic>> createGroup(
    String userQuestId,
    String mode,
  ) async =>
      apiObject(
        await _client.post(
          'collab/groups',
          body: {
            'userQuestId': userQuestId,
            'mode': mode,
          },
        ),
      );

  @override
  Future<CollabGroupPreviewModel> getGroupDetails(String code) async =>
      CollabGroupPreviewModel.fromJson(
        apiObject(
          await _client
              .get('collab/groups/preview/${Uri.encodeComponent(code)}'),
        ),
      );

  @override
  Future<Map<String, dynamic>> joinGroup(
    String code, {
    bool abandonActiveQuest = false,
  }) async =>
      apiObject(
        await _client.post(
          'collab/groups/join',
          body: {
            'code': code,
            if (abandonActiveQuest) 'abandonActiveQuest': true,
          },
        ),
      );

  @override
  Future<CollabGroupStatusModel> getGroupStatus(String userQuestId) async =>
      CollabGroupStatusModel.fromJson(
        apiObject(
          await _client.get('collab/assignments/$userQuestId'),
        ),
      );

  @override
  Future<void> abandonQuest(String userQuestId) async {
    await _client.post('collab/assignments/$userQuestId/abandon');
  }

  @override
  Future<void> leaveGroup(String groupId) async {
    await _client.delete('collab/groups/$groupId/members/me');
  }

  @override
  Future<void> voteCollab(String groupId, String submissionId) async {
    await _client.put('collab/groups/$groupId/votes/$submissionId');
  }

  @override
  Future<void> unvoteCollab(String groupId, String submissionId) async {
    await _client.delete('collab/groups/$groupId/votes/$submissionId');
  }
}
