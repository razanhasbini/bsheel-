import 'package:app_models/app_models.dart';

abstract class SearchRepository {
  Future<List<ProfileModel>> searchUsers(String query, {int limit = 20});
  Future<List<QuestModel>> searchQuests(String query, {int limit = 20});

  /// Posts matching [query] in their quest title/description/category, plus
  /// the current user's own approved posts (so they can find what they have
  /// already shared regardless of the term). Approved + visible only.
  Future<List<SubmissionModel>> searchPosts(
    String query, {
    required String currentUserId,
    int limit = 24,
  });
}
