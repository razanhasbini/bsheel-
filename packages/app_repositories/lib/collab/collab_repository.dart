import 'package:app_models/app_models.dart';

abstract class CollabRepository {
  Future<Map<String, dynamic>> createGroup(String userQuestId, String mode);
  Future<CollabGroupPreviewModel> getGroupDetails(String code);
  Future<Map<String, dynamic>> joinGroup(String code);
  Future<CollabGroupStatusModel> getGroupStatus(String userQuestId);
  Future<void> abandonQuest(String userQuestId);
  Future<void> voteCollab(String groupId, String submissionId);
  Future<void> unvoteCollab(String groupId, String submissionId);
}
