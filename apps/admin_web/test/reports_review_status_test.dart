import 'package:admin_web/features/reports/presentation/pages/reports_page.dart';
import 'package:app_contracts/app_contracts.dart';
import 'package:app_repositories/app_repositories.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Stands in for `PATCH admin/reports/:id` and records what the page sent.
///
/// The backend's `ReviewReportDto` validates the body against
/// `['reviewed', 'dismissed', 'actioned']`, so anything else is a 400 the
/// moderator sees as "nothing changed".
class _FakeAdminApi extends Fake implements ApiAdminRepository {
  _FakeAdminApi(this.rows);

  final List<Map<String, dynamic>> rows;
  final List<String> sent = [];

  @override
  Future<List<Map<String, dynamic>>> reports({
    String status = ReportStatus.pending,
    int limit = 50,
    int offset = 0,
  }) async =>
      rows;

  @override
  Future<void> reviewReport(
    String reportId, {
    required String status,
    String? adminNote,
  }) async {
    sent.add(status);
  }
}

Map<String, dynamic> _report(String status) => {
      'id': 'a5f2f0de-0000-4000-8000-000000000001',
      'reported_type': 'submission',
      'reported_id': 'b5f2f0de-0000-4000-8000-000000000002',
      'reported_user_id': null,
      'reported_username': 'target',
      'reason': 'This is not a real quest photo.',
      'status': status,
      'profiles': {'username': 'reporter', 'display_name': 'Reporter'},
    };

Future<_FakeAdminApi> _pumpReports(
  WidgetTester tester,
  String status,
) async {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final api = _FakeAdminApi([_report(status)]);
  await tester.pumpWidget(ProviderScope(
    overrides: [reportsApiProvider.overrideWithValue(api)],
    child: const MaterialApp(home: Scaffold(body: ReportsPage())),
  ));
  await tester.pumpAndSettle();
  return api;
}

void main() {
  testWidgets('a decided report is put back with a status the API accepts',
      (tester) async {
    final api = await _pumpReports(tester, ReportStatus.actioned);

    // The page opens on the untriaged view, so switch to the decided one.
    await tester.tap(find.textContaining('ACTIONED'));
    await tester.pumpAndSettle();

    // The button used to read REOPEN and send `pending`, which the review
    // endpoint rejects — so reopening a decided report never worked.
    expect(find.text('REOPEN'), findsNothing);
    await tester.tap(find.text('MARK REVIEWED'));
    await tester.pumpAndSettle();

    expect(api.sent, [ReportStatus.reviewed]);
    expect(ReportStatus.reviewable, contains(api.sent.single),
        reason: 'the status must be one PATCH admin/reports/:id accepts');
    expect(api.sent.single, isNot(ReportStatus.pending),
        reason: 'pending is the column default, not an accepted transition');
  });

  testWidgets('a reviewed report is decidable again', (tester) async {
    final api = await _pumpReports(tester, ReportStatus.reviewed);

    await tester.tap(find.textContaining('REVIEWED'));
    await tester.pumpAndSettle();

    // `reviewed` means "seen, no decision recorded", so the decision
    // buttons come back — that is what makes clearing a decision useful.
    expect(find.text('DISMISS'), findsOneWidget);
    await tester.tap(find.text('DISMISS'));
    await tester.pumpAndSettle();
    expect(api.sent, [ReportStatus.dismissed]);
  });

  test('ReportStatus.reviewable is exactly what the endpoint accepts', () {
    // Mirrors `ReviewReportDto` in
    // backend/src/modules/admin/presentation/admin.dto.ts.
    expect(ReportStatus.reviewable,
        [ReportStatus.reviewed, ReportStatus.dismissed, ReportStatus.actioned]);
    expect(ReportStatus.reviewable, isNot(contains(ReportStatus.pending)),
        reason: 'the API has no transition back to the untriaged queue');
    // Every reviewable status is still a legal column value, so a request
    // the DTO accepts cannot fail the CHECK constraint underneath it.
    for (final status in ReportStatus.reviewable) {
      expect(ReportStatus.all, contains(status));
    }
  });
}
