import 'package:app_models/app_models.dart';

import '../api/api_client.dart';
import '../media/api_media_signer.dart';
import 'search_repository.dart';

class ApiSearchRepository implements SearchRepository {
  ApiSearchRepository(this._client) : _media = ApiMediaSigner(_client);

  final ApiClient _client;
  final ApiMediaSigner _media;
  String? _cacheKey;
  DateTime? _cachedAt;
  Future<Map<String, dynamic>>? _cachedRequest;

  Future<Map<String, dynamic>> _search(String query, int limit) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty)
      return const {
        'users': <Object>[],
        'quests': <Object>[],
        'posts': <Object>[],
      };
    final requestedLimit = limit < 24 ? 24 : limit;
    final key = '$trimmed\u0000$requestedLimit';
    final now = DateTime.now();
    if (_cacheKey == key &&
        _cachedAt != null &&
        now.difference(_cachedAt!) < const Duration(seconds: 1) &&
        _cachedRequest != null) {
      return _cachedRequest!;
    }
    final request = _client.get(
      'search',
      query: {
        'q': trimmed,
        'limit': requestedLimit,
        'offset': 0,
      },
    ).then(apiObject);
    _cacheKey = key;
    _cachedAt = now;
    _cachedRequest = request;
    return request;
  }

  @override
  Future<List<ProfileModel>> searchUsers(String query, {int limit = 20}) async {
    final rows =
        apiObjectList((await _search(query, limit))['users']).take(limit);
    return Future.wait(
      rows.map((row) async {
        final profile = ProfileModel.fromJson(row);
        return profile.copyWith(
          avatarUrl: await _media.signNullable(profile.avatarUrl),
        );
      }),
    );
  }

  @override
  Future<List<QuestModel>> searchQuests(String query, {int limit = 20}) async =>
      apiObjectList((await _search(query, limit))['quests'])
          .take(limit)
          .map(QuestModel.fromJson)
          .toList(growable: false);

  @override
  Future<List<SubmissionModel>> searchPosts(
    String query, {
    required String currentUserId,
    int limit = 24,
  }) async {
    final rows =
        apiObjectList((await _search(query, limit))['posts']).take(limit);
    return Future.wait(
      rows.map((row) async {
        final submission = SubmissionModel.fromJson(row);
        final signed = await _media.signJsonOrSingle(submission.mediaUrl);
        return SubmissionModel(
          id: submission.id,
          userQuestId: submission.userQuestId,
          userId: submission.userId,
          mediaUrl: signed,
          mediaType: submission.mediaType,
          caption: submission.caption,
          status: submission.status,
          reviewedBy: submission.reviewedBy,
          reviewNote: submission.reviewNote,
          submittedAt: submission.submittedAt,
          reviewedAt: submission.reviewedAt,
          appealNote: submission.appealNote,
          appealed: submission.appealed,
          showInFeed: submission.showInFeed,
          visibility: submission.visibility,
          deletedAt: submission.deletedAt,
          questTitle: submission.questTitle,
          authorUsername: submission.authorUsername,
          authorDisplayName: submission.authorDisplayName,
        );
      }),
    );
  }
}
