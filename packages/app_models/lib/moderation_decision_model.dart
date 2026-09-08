import 'package:supabase_contracts/supabase_contracts.dart';

import 'src/json_coercions.dart';

/// The moderator's decision on one submission, shaped as the PATCH body
/// that writes it back.
///
/// Deliberately without `==` / `hashCode`: this is a write-only payload
/// that is built once per moderator action and never held in provider
/// state, so value equality would buy no rebuild de-duplication.
class ModerationDecisionModel {
  final String submissionId;
  final String decision;
  final String? reviewNote;
  final String reviewedBy;

  /// When the decision was recorded, or null on a row that has not been
  /// reviewed yet. Nullable on purpose: this used to be a non-null field
  /// whose parser fabricated `DateTime.now()` for a missing `reviewed_at`,
  /// which made an un-reviewed submission look as though it had just been
  /// decided. See the timestamp rule in `src/json_coercions.dart`.
  final DateTime? reviewedAt;

  const ModerationDecisionModel({
    required this.submissionId,
    required this.decision,
    this.reviewNote,
    required this.reviewedBy,
    this.reviewedAt,
  });

  factory ModerationDecisionModel.fromJson(Map<String, dynamic> json) {
    return ModerationDecisionModel(
      submissionId: (json[SubmissionColumns.id] ?? '').toString(),
      decision: (json[SubmissionColumns.status] as String?) ??
          SubmissionStatus.pending,
      reviewNote: json[SubmissionColumns.reviewNote] as String?,
      reviewedBy: (json[SubmissionColumns.reviewedBy] ?? '').toString(),
      reviewedAt: coerceNullableTimestamp(json[SubmissionColumns.reviewedAt]),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      SubmissionColumns.status: decision,
      SubmissionColumns.reviewNote: reviewNote,
      SubmissionColumns.reviewedBy: reviewedBy,
      SubmissionColumns.reviewedAt: reviewedAt?.toIso8601String(),
    };
  }
}
