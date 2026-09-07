import 'package:app_models/app_models.dart';

abstract class ModerationRepository {
  Future<SubmissionModel?> getSubmissionById(String submissionId);
  Future<List<SubmissionModel>> getPendingSubmissions();
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
