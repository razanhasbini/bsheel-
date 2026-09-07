import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:app_models/app_models.dart';
import 'package:supabase_contracts/supabase_contracts.dart';

import 'moderation_repository.dart';

class SupabaseModerationRepository implements ModerationRepository {
  final SupabaseClient client;
  SupabaseModerationRepository(this.client);

  @override
  Future<SubmissionModel?> getSubmissionById(String submissionId) async {
    final data = await client
        .from(Tables.submissions)
        .select()
        .eq(SubmissionColumns.id, submissionId)
        .maybeSingle();
    if (data == null) return null;
    return SubmissionModel.fromJson(Map<String, dynamic>.from(data));
  }

  @override
  Future<List<SubmissionModel>> getPendingSubmissions() async {
    final response = await client
        .from(Tables.submissions)
        .select()
        .eq(SubmissionColumns.status, SubmissionStatus.pending)
        .order(SubmissionColumns.submittedAt, ascending: true);

    return (response as List<dynamic>)
        .map((row) => SubmissionModel.fromJson(Map<String, dynamic>.from(row)))
        .toList();
  }

  @override
  Future<void> approveSubmission(
    String submissionId,
    String reviewedBy, {
    String? note,
  }) async {
    await client.from(Tables.submissions).update({
      SubmissionColumns.status: SubmissionStatus.approved,
      SubmissionColumns.reviewedBy: reviewedBy,
      SubmissionColumns.reviewNote: note,
      SubmissionColumns.reviewedAt: DateTime.now().toUtc().toIso8601String(),
    }).eq(SubmissionColumns.id, submissionId);
  }

  @override
  Future<void> rejectSubmission(
    String submissionId,
    String reviewedBy, {
    String? note,
  }) async {
    await client.from(Tables.submissions).update({
      SubmissionColumns.status: SubmissionStatus.rejected,
      SubmissionColumns.reviewedBy: reviewedBy,
      SubmissionColumns.reviewNote: note,
      SubmissionColumns.reviewedAt: DateTime.now().toUtc().toIso8601String(),
    }).eq(SubmissionColumns.id, submissionId);
  }
}
