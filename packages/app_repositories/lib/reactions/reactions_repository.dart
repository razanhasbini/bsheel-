import 'package:app_models/app_models.dart';

abstract class ReactionsRepository {
  /// Get the current user's vote on a submission (null if no vote).
  Future<ReactionModel?> getMyVote(String submissionId, String userId);

  /// Cast a vote (upvote or downvote). Replaces any existing vote.
  Future<ReactionModel> vote(String submissionId, String userId, String type);

  /// Remove the user's vote on a submission.
  Future<void> removeVote(String submissionId, String userId);
}
