import 'package:app_models/app_models.dart';
import 'package:supabase_contracts/supabase_contracts.dart';
import 'package:test/test.dart';

Map<String, dynamic> decisionRow({
  Map<String, dynamic> overrides = const {},
}) =>
    {
      SubmissionColumns.id: 'sub-1',
      SubmissionColumns.status: SubmissionStatus.rejected,
      SubmissionColumns.reviewNote: 'off-brief',
      SubmissionColumns.reviewedBy: 'admin-1',
      SubmissionColumns.reviewedAt: '2026-05-03T13:00:00Z',
      ...overrides,
    };

void main() {
  group('ModerationDecisionModel.fromJson', () {
    test('parses a rejection', () {
      final decision = ModerationDecisionModel.fromJson(decisionRow());

      expect(decision.submissionId, 'sub-1');
      expect(decision.decision, 'rejected');
      expect(decision.reviewNote, 'off-brief');
      expect(decision.reviewedBy, 'admin-1');
      expect(decision.reviewedAt, DateTime.utc(2026, 5, 3, 13));
    });

    test('an approval carries a null review note', () {
      final decision = ModerationDecisionModel.fromJson(decisionRow(
        overrides: {
          SubmissionColumns.status: SubmissionStatus.approved,
          SubmissionColumns.reviewNote: null,
        },
      ));

      expect(decision.decision, 'approved');
      expect(decision.reviewNote, isNull);
    });

    test('a null or missing status defaults to pending', () {
      expect(
        ModerationDecisionModel.fromJson(decisionRow(overrides: {
          SubmissionColumns.status: null,
        })).decision,
        SubmissionStatus.pending,
      );
      final row = decisionRow()..remove(SubmissionColumns.status);
      expect(
        ModerationDecisionModel.fromJson(row).decision,
        SubmissionStatus.pending,
      );
    });

    test('missing ids coerce to empty strings', () {
      final row = decisionRow()
        ..remove(SubmissionColumns.id)
        ..remove(SubmissionColumns.reviewedBy);
      final decision = ModerationDecisionModel.fromJson(row);

      expect(decision.submissionId, isEmpty);
      expect(decision.reviewedBy, isEmpty);
    });

    test('a missing reviewed_at stays null instead of becoming "now"', () {
      // Regression guard. This was the one model whose timestamp helper
      // fabricated DateTime.now() for a missing value, so an un-reviewed
      // row parsed as though it had just been decided. A missing review
      // timestamp means "not reviewed" — the field is nullable now.
      final row = decisionRow()..remove(SubmissionColumns.reviewedAt);

      expect(ModerationDecisionModel.fromJson(row).reviewedAt, isNull);
    });

    test('an explicit null or unparseable reviewed_at is also null', () {
      expect(
        ModerationDecisionModel.fromJson(decisionRow(
          overrides: {SubmissionColumns.reviewedAt: null},
        )).reviewedAt,
        isNull,
      );
      expect(
        ModerationDecisionModel.fromJson(decisionRow(
          overrides: {SubmissionColumns.reviewedAt: 'just now'},
        )).reviewedAt,
        isNull,
      );
    });

    test('a DateTime instance passes through', () {
      final at = DateTime.utc(2026, 5, 3, 13);
      expect(
        ModerationDecisionModel.fromJson(decisionRow(overrides: {
          SubmissionColumns.reviewedAt: at,
        })).reviewedAt,
        at,
      );
    });
  });

  group('ModerationDecisionModel.toJson', () {
    test('a null reviewed_at serialises as null', () {
      final row = decisionRow()..remove(SubmissionColumns.reviewedAt);
      final json = ModerationDecisionModel.fromJson(row).toJson();

      expect(json.containsKey(SubmissionColumns.reviewedAt), isTrue);
      expect(json[SubmissionColumns.reviewedAt], isNull);
    });

    test('is an update payload: 4 keys, no submission id', () {
      // The submission id addresses the row in the URL, so including it in
      // the body would be an attempt to rewrite the primary key.
      final json = ModerationDecisionModel.fromJson(decisionRow()).toJson();

      expect(json.keys.toSet(), {
        SubmissionColumns.status,
        SubmissionColumns.reviewNote,
        SubmissionColumns.reviewedBy,
        SubmissionColumns.reviewedAt,
      });
      expect(json.containsKey(SubmissionColumns.id), isFalse);
      expect(json[SubmissionColumns.status], 'rejected');
      expect(json[SubmissionColumns.reviewedAt], '2026-05-03T13:00:00.000Z');
    });

    test('round-tripping loses the submission id', () {
      final original = ModerationDecisionModel.fromJson(decisionRow());
      final restored = ModerationDecisionModel.fromJson(original.toJson());

      expect(restored.decision, original.decision);
      expect(restored.reviewNote, original.reviewNote);
      expect(restored.reviewedBy, original.reviewedBy);
      expect(restored.reviewedAt, original.reviewedAt);
      expect(original.submissionId, 'sub-1');
      expect(restored.submissionId, isEmpty);
    });
  });
}
