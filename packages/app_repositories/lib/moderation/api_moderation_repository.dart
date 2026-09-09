import 'package:app_models/app_models.dart';

import '../api/api_client.dart';
import '../media/api_media_signer.dart';
import 'moderation_repository.dart';

class ApiModerationRepository implements ModerationRepository {
  ApiModerationRepository(this._client) : _media = ApiMediaSigner(_client);

  final ApiClient _client;
  final ApiMediaSigner _media;

  @override
  Future<SubmissionModel?> getSubmissionById(String submissionId) async {
    try {
      final row = apiObject(await _client.get('submissions/$submissionId'));
      return _signed(SubmissionModel.fromJson(row));
    } on ApiException catch (error) {
      if (error.statusCode == 404) return null;
      rethrow;
    }
  }

  @override
  Future<List<SubmissionModel>> getPendingSubmissions() async {
    final rows = <Map<String, dynamic>>[];
    const pageSize = 100;
    for (var offset = 0;; offset += pageSize) {
      final page = apiObjectList(
        await _client.get(
          'submissions/admin/pending',
          query: {'limit': pageSize, 'offset': offset},
        ),
      );
      rows.addAll(page);
      if (page.length < pageSize) break;
    }
    return Future.wait(
      rows.map((row) => _signed(SubmissionModel.fromJson(row))),
    );
  }

  @override
  Future<Map<String, dynamic>?> reviewDetail(String submissionId) async {
    try {
      final row = apiObject(
        await _client.get('submissions/admin/$submissionId'),
      );
      final signed = await _withSignedMedia(row);
      final avatar = signed['avatar_url']?.toString();
      if (avatar == null || avatar.isEmpty) return signed;
      return {...signed, 'avatar_url': await _media.signNullable(avatar)};
    } on ApiException catch (error) {
      if (error.statusCode == 404) return null;
      rethrow;
    }
  }

  @override
  Future<List<Map<String, dynamic>>> reviewQueue({
    int limit = 100,
    int offset = 0,
    String? cursor,
  }) async {
    final rows = apiObjectList(
      await _client.get(
        'submissions/admin/review-queue',
        query: {
          'limit': limit,
          if (cursor == null) 'offset': offset,
          if (cursor != null) 'cursor': cursor,
        },
      ),
    );
    return Future.wait(rows.map(_withSignedMedia));
  }

  @override
  Future<List<Map<String, dynamic>>> listSubmissionsForAdmin({
    String status = 'pending',
    bool? appealed,
    String? visibility,
    String order = 'asc',
    int limit = 100,
    int offset = 0,
    String? cursor,
  }) async {
    final rows = apiObjectList(
      await _client.get(
        'submissions/admin',
        query: {
          'status': status,
          if (appealed != null) 'appealed': appealed.toString(),
          if (visibility != null) 'visibility': visibility,
          'order': order,
          'limit': limit,
          // Mutually exclusive: the server ignores an offset once a cursor
          // is present, and sending both would only invite confusion.
          if (cursor == null) 'offset': offset,
          if (cursor != null) 'cursor': cursor,
        },
      ),
    );
    // Media keys are private; sign them before the table renders them.
    return Future.wait(rows.map(_withSignedMedia));
  }

  Future<Map<String, dynamic>> _withSignedMedia(
    Map<String, dynamic> row,
  ) async {
    final raw = row['media_url']?.toString();
    if (raw == null || raw.isEmpty) return row;
    return {...row, 'media_url': await _media.signJsonOrSingle(raw)};
  }

  @override
  Future<void> approveSubmission(
    String submissionId,
    String reviewedBy, {
    String? note,
  }) async {
    await _client.post(
      'submissions/$submissionId/approve',
      body: {'reviewNote': note},
    );
  }

  @override
  Future<void> rejectSubmission(
    String submissionId,
    String reviewedBy, {
    String? note,
  }) async {
    await _client.post(
      'submissions/$submissionId/reject',
      body: {'reviewNote': note?.trim().isNotEmpty == true ? note : 'Rejected'},
    );
  }

  Future<SubmissionModel> _signed(SubmissionModel submission) async {
    final url = await _media.signJsonOrSingle(submission.mediaUrl);
    return SubmissionModel(
      id: submission.id,
      userQuestId: submission.userQuestId,
      userId: submission.userId,
      mediaUrl: url,
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
  }
}
