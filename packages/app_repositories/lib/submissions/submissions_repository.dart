import 'dart:typed_data';
import 'package:app_models/app_models.dart';

/// What kind of soft-delete the user is asking for.
enum SoftDeleteMode {
  /// Hide from the public feed but keep on the user's profile.
  hiddenFromFeed,

  /// Remove from feed AND profile, decrement XP via the DB trigger,
  /// re-add to BSHEEEL is impossible afterwards. Permanent from the
  /// user's perspective.
  deleted,

  /// Restore a previously hidden/deleted post.
  visible,
}

abstract class SubmissionsRepository {
  Future<SubmissionModel> createSubmission(SubmissionModel submission);
  Future<String> uploadSubmissionMedia(
    String userId,
    String submissionId,
    Uint8List fileBytes,
    String fileName,
    String mediaType, {
    int index = 0,
  });
  Future<SubmissionModel?> getSubmission(String submissionId);
  Future<List<SubmissionModel>> getUserSubmissions(String userId);

  /// Apply a visibility change to a submission. Centralised so the
  /// three previously-inline `.update({visibility, deleted_at})` paths
  /// in feed_post_details_page can't drift apart (ARC-028).
  Future<void> setSubmissionVisibility(
    String submissionId,
    SoftDeleteMode mode,
  );
}
