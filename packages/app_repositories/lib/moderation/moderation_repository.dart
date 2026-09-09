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
  Future<List<Map<String, dynamic>>> reviewQueue({
    int limit = 100,
    int offset = 0,
  });

  /// The "unclear" queue (#47): proof the AI verification agent could not
  /// judge, still waiting on a human decision. Distinct from the ordinary
  /// review queue — every row here is one the agent explicitly declined,
  /// and each carries the reason it gave up plus its provenance findings.
  Future<List<Map<String, dynamic>>> unclearQueue({
    int limit = 100,
    int offset = 0,
  });

  /// How many escalations are waiting, for the sidebar badge.
  Future<int> unclearCount();

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
