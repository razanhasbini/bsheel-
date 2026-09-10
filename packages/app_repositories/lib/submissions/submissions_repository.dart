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

  /// Submits the one allowed appeal for a rejected, non-deleted submission.
  ///
  /// Declared here so the appeal action can be faked in a widget test. It was
  /// reachable only on the concrete class, which is why `AppBackend` had to
  /// expose the implementation type and why nothing could test the flow.
  ///
  /// Server-side guards, with their error codes: the caller must own the
  /// submission (`NOT_SUBMISSION_OWNER`), it must be rejected
  /// (`SUBMISSION_NOT_REJECTED`), unappealed (`ALREADY_APPEALED`) and not
  /// soft-deleted (`DELETED_SUBMISSION`).
  Future<void> appealSubmission(String submissionId, String appealNote);
  Future<List<SubmissionModel>> getUserSubmissions(String userId);

  /// Apply a visibility change to a submission. Centralised so the
  /// three previously-inline `.update({visibility, deleted_at})` paths
  /// in feed_post_details_page can't drift apart (ARC-028).
  Future<void> setSubmissionVisibility(
    String submissionId,
    SoftDeleteMode mode,
  );
}
