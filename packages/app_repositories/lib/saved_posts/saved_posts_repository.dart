import 'package:app_models/app_models.dart';

abstract class SavedPostsRepository {
  Future<List<SavedPostModel>> getSavedPosts(String userId);
  Future<List<SavedPostWithQuest>> getSavedPostsWithQuests(String userId);
  Future<bool> isPostSaved(String submissionId, String userId);
  Future<void> savePost(String submissionId, String userId);
  Future<void> unsavePost(String submissionId, String userId);
}
