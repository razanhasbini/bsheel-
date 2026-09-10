import 'package:app_models/app_models.dart';

abstract class CollabRepository {
  Future<Map<String, dynamic>> createGroup(String userQuestId, String mode);
  Future<CollabGroupPreviewModel> getGroupDetails(String code);

  /// Joins a group, optionally giving up the caller's in-progress quest.
  ///
  /// Pass [abandonActiveQuest] rather than calling [abandonQuest] first: the
  /// server then does both in one transaction, so a join that fails leaves
  /// the existing quest alone.
  Future<Map<String, dynamic>> joinGroup(
    String code, {
    bool abandonActiveQuest = false,
  });
  Future<CollabGroupStatusModel> getGroupStatus(String userQuestId);
  Future<void> abandonQuest(String userQuestId);

  /// Leaves a group while keeping the quest as an ordinary solo assignment.
  Future<void> leaveGroup(String groupId);
  Future<void> voteCollab(String groupId, String submissionId);
  Future<void> unvoteCollab(String groupId, String submissionId);
}
