import 'dart:typed_data';

import 'package:app_models/app_models.dart';

import '../api/api_client.dart';
import '../media/api_media_signer.dart';
import '../media/api_media_uploader.dart';
import 'submissions_repository.dart';

class ApiSubmissionsRepository implements SubmissionsRepository {
  ApiSubmissionsRepository(this._client)
      : _media = ApiMediaSigner(_client),
        _uploader = ApiMediaUploader(_client);

  final ApiClient _client;
  final ApiMediaSigner _media;
  final ApiMediaUploader _uploader;

  @override
  Future<SubmissionModel> createSubmission(SubmissionModel submission) async {
    final data = apiObject(
      await _client.post(
        'submissions',
        body: {
          'userQuestId': submission.userQuestId,
          'mediaUrl': submission.mediaUrl,
          'mediaType': submission.mediaType,
          'caption': submission.caption,
          'showInFeed': submission.showInFeed,
        },
      ),
    );
    return _signed(SubmissionModel.fromJson(data));
  }

  @override
  Future<String> uploadSubmissionMedia(
    String userId,
    String submissionId,
    Uint8List fileBytes,
    String fileName,
    String mediaType, {
    int index = 0,
  }) =>
      _uploader.upload(
        kind: 'submission',
        bytes: fileBytes,
        fileName: fileName,
        fallbackMediaType: mediaType,
      );

  @override
  Future<SubmissionModel?> getSubmission(String submissionId) async {
    try {
      final data = apiObject(await _client.get('submissions/$submissionId'));
      return _signed(SubmissionModel.fromJson(data));
    } on ApiException catch (error) {
      if (error.statusCode == 404) return null;
      rethrow;
    }
  }

  @override
  Future<List<SubmissionModel>> getUserSubmissions(String userId) async {
    final rows = <Map<String, dynamic>>[];
    const pageSize = 100;
    for (var offset = 0;; offset += pageSize) {
      final page = apiObjectList(
        await _client.get(
          'submissions/user/$userId',
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
  Future<void> setSubmissionVisibility(
    String submissionId,
    SoftDeleteMode mode,
  ) async {
    final visibility = switch (mode) {
      SoftDeleteMode.visible => 'visible',
      SoftDeleteMode.hiddenFromFeed => 'hidden_from_feed',
      SoftDeleteMode.deleted => 'deleted',
    };
    await _client.patch(
      'submissions/$submissionId/visibility',
      body: {'visibility': visibility},
    );
  }

  /// Submits the one allowed appeal for a rejected, non-deleted submission.
  Future<SubmissionModel> appealSubmission(
    String submissionId,
    String appealNote,
  ) async {
    final row = apiObject(
      await _client.post(
        'submissions/$submissionId/appeal',
        body: {'appealNote': appealNote.trim()},
      ),
    );
    return _signed(SubmissionModel.fromJson(row));
  }

  Future<SubmissionModel> _signed(SubmissionModel submission) async {
    final mediaUrl = await _media.signJsonOrSingle(submission.mediaUrl);
    return SubmissionModel(
      id: submission.id,
      userQuestId: submission.userQuestId,
      userId: submission.userId,
      mediaUrl: mediaUrl,
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
