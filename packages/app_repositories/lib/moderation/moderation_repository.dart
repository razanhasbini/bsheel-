import 'package:app_models/app_models.dart';

abstract class ModerationRepository {
  Future<SubmissionModel?> getSubmissionById(String submissionId);
  Future<List<SubmissionModel>> getPendingSubmissions();

  /// Full review context for one submission: the author's profile, the
  /// quest, and whether this repeats a quest the user already completed.
  /// Returns null when the submission does not exist.
  Future<Map<String, dynamic>?> reviewDetail(String submissionId);

  /// The moderation review queue: pending submissions, oldest first, each
  /// carrying the reviewer context the queue renders (per-user approved and
  /// rejected counts, and whether the media or caption repeats something
  /// that user already had rejected).
  /// Pass [cursor] from a previous page's last row `next_cursor` to page
  /// forward. [offset] is kept for callers that have not migrated; it is
  /// ignored when a cursor is supplied.
  Future<List<Map<String, dynamic>>> reviewQueue({
    int limit = 100,
    int offset = 0,
    String? cursor,
  });

  /// Raw admin rows for the moderation queues. `status` accepts
  /// `pending`, `approved`, `rejected` or `all`; `appealed` filters the
  /// appeals queue. Rows carry the joined reporter/quest fields the admin
  /// tables render, so they stay maps rather than models.
  Future<List<Map<String, dynamic>>> listSubmissionsForAdmin({
    String status = 'pending',
    bool? appealed,
    String? visibility,
    String order = 'asc',
    int limit = 100,
    int offset = 0,
  });
  Future<void> approveSubmission(
    String submissionId,
    String reviewedBy, {
    String? note,
  });
  Future<void> rejectSubmission(
    String submissionId,
    String reviewedBy, {
    String? note,
  });
}
