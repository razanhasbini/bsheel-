import 'package:supabase_contracts/supabase_contracts.dart';

class ModerationDecisionModel {
  final String submissionId;
  final String decision;
  final String? reviewNote;
  final String reviewedBy;
  final DateTime reviewedAt;

  const ModerationDecisionModel({
    required this.submissionId,
    required this.decision,
    this.reviewNote,
    required this.reviewedBy,
    required this.reviewedAt,
  });

  factory ModerationDecisionModel.fromJson(Map<String, dynamic> json) {
    return ModerationDecisionModel(
      submissionId: (json[SubmissionColumns.id] ?? '').toString(),
      decision: (json[SubmissionColumns.status] as String?) ?? SubmissionStatus.pending,
      reviewNote: json[SubmissionColumns.reviewNote] as String?,
      reviewedBy: (json[SubmissionColumns.reviewedBy] ?? '').toString(),
      reviewedAt: _toDateTime(json[SubmissionColumns.reviewedAt]),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      SubmissionColumns.status: decision,
      SubmissionColumns.reviewNote: reviewNote,
      SubmissionColumns.reviewedBy: reviewedBy,
      SubmissionColumns.reviewedAt: reviewedAt.toIso8601String(),
    };
  }

  static DateTime _toDateTime(dynamic value) {
    if (value is DateTime) return value;
    if (value == null) return DateTime.now();
    return DateTime.parse(value as String);
  }
}
