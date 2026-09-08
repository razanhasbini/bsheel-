import 'package:app_models/app_models.dart';
import 'package:app_contracts/app_contracts.dart';

import '../api/api_client.dart';
import 'reactions_repository.dart';

class ApiReactionsRepository implements ReactionsRepository {
  const ApiReactionsRepository(this._client);

  final ApiClient _client;

  @override
  Future<ReactionModel?> getMyVote(String submissionId, String userId) async {
    final data = await _client.get('social/posts/$submissionId/vote');
    if (data == null) return null;
    return ReactionModel.fromJson(apiObject(data));
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
    return ReactionModel.fromJson(
      apiObject(
        await _client.put(
          'social/posts/$submissionId/vote',
          body: {'type': type},
        ),
      ),
    );
  }

  @override
  Future<void> removeVote(String submissionId, String userId) async {
    await _client.delete('social/posts/$submissionId/vote');
  }
}
