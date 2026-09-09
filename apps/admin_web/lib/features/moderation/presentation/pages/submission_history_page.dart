import 'dart:js_interop';

import 'package:app_contracts/app_contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:web/web.dart' as web;

import '../../../../core/backend/app_backend.dart';
import '../../../../core/router/admin_route_names.dart';
import '../../../../core/theme/bsheel_design.dart';
import '../../../../shared/layout/admin_shell.dart';
import '../../../../shared/widgets/bsheel_widgets.dart';

/// Every submission, newest first. Media keys are signed by the adapter.
final _allSubmissionsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  return AppBackend.repositories.moderation.listSubmissionsForAdmin(
    status: 'all',
    order: 'desc',
  );
});

/// The decided-submission ledger: one table, five filters, one page at a
/// time, and a CSV of whatever the moderator is currently looking at.
///
/// `OUTCOME` is derived rather than stored: the database has three
/// statuses, but a moderator reads five outcomes, because a rejection
/// that survived an appeal is final and a rejection that hasn't been
/// appealed yet is not. `RE-REJECTED` therefore resolves to the ink pill —
/// it is the one outcome nothing can follow.
class SubmissionHistoryPage extends ConsumerStatefulWidget {
  const SubmissionHistoryPage({super.key});

  @override
  ConsumerState<SubmissionHistoryPage> createState() =>
      _SubmissionHistoryPageState();
}

class _SubmissionHistoryPageState extends ConsumerState<SubmissionHistoryPage> {
  /// Filter keys. `all` plus the two decided statuses from the contract,
  /// plus the two appeal outcomes the table derives.
  static const String _fAll = 'all';
  static const String _fAppealed = SubmissionColumns.appealed;
  static const String _fReRejected = 're-rejected';

  /// Rows per page. The provider fetches one API page; this is how much of
  /// it the table shows at once.
  static const int _pageSize = 12;

  final TextEditingController _searchController = TextEditingController();
  String _filter = _fAll;
  String _search = '';
  int _page = 0;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final subsAsync = ref.watch(_allSubmissionsProvider);
    final loaded = subsAsync.valueOrNull;
    final visible = loaded == null ? null : _visible(loaded);

    return AdminPage(
      title: 'Submission history',
      actions: [
        BsheelSearchField(
          controller: _searchController,
          hint: 'Search user or quest…',
          width: 230,
          onChanged: (v) => setState(() {
            _search = v.trim().toLowerCase();
            _page = 0;
          }),
        ),
        // White, not cream: this button sits on the cream header bar,
        // where a cream fill would read as an outline with no body.
        BsheelButton.secondary(
          label: 'Export CSV',
          // Nothing to export until the ledger is on screen, and a button
          // that cannot act says so by losing its shadow.
          onPressed: (visible == null || visible.isEmpty)
              ? null
              : () => _exportCsv(visible),
        ),
      ],
      subheader: BsheelFilterChips(
        selected: _filter,
        onChanged: (v) => setState(() {
          _filter = v;
          _page = 0;
        }),
        filters: const [
          BsheelFilter(_fAll, 'All'),
          BsheelFilter(SubmissionStatus.approved, 'Approved'),
          BsheelFilter(SubmissionStatus.rejected, 'Rejected'),
          BsheelFilter(_fAppealed, 'Appealed'),
          BsheelFilter(_fReRejected, 'Re-rejected'),
        ],
      ),
      child: subsAsync.when(
        loading: () => const BsheelLoadingList(rows: 6, rowHeight: 44),
        error: (e, _) => BsheelErrorState(
          title: 'History didn’t load',
          message: 'The submission ledger didn’t come back. Nothing was '
              'changed and no decision was recorded — this page only reads. '
              '$e',
          onRetry: () => ref.invalidate(_allSubmissionsProvider),
        ),
        data: (subs) {
          if (subs.isEmpty) {
            return BsheelEmptyState(
              title: 'Nothing decided yet',
              message: 'No submission has been reviewed, so the ledger is '
                  'empty. Start with the moderation queue.',
              actionLabel: 'Open the queue',
              onAction: () =>
                  context.goNamed(AdminRouteNames.pendingSubmissions),
            );
          }

          final rows = _visible(subs);
          if (rows.isEmpty) {
            return BsheelEmptyState(
              title: 'No match',
              message: 'No submission matches this filter and search. Clear '
                  'them both to see the whole ledger again.',
              actionLabel: 'Clear filters',
              onAction: () {
                _searchController.clear();
                setState(() {
                  _filter = _fAll;
                  _search = '';
                  _page = 0;
                });
              },
            );
          }

          final pageCount = (rows.length / _pageSize).ceil();
          final page = _page.clamp(0, pageCount - 1);
          final start = page * _pageSize;
          final end = (start + _pageSize) < rows.length
              ? start + _pageSize
              : rows.length;
          final pageRows = rows.sublist(start, end);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              BsheelTable(
                depth: 5,
                columns: const [
                  BsheelColumn('ID', width: 86),
                  BsheelColumn('Quest'),
                  BsheelColumn('User', width: 100),
                  BsheelColumn('Decided', width: 112),
                  BsheelColumn('Moderator', width: 116),
                  BsheelColumn('Outcome', width: 112),
                ],
                rows: [
                  for (final s in pageRows)
                    BsheelRow(
                      [
                        BsheelCell.mono(_shortId(s[SubmissionColumns.id])),
                        BsheelCell.title(_text(s['quest_title'], '—')),
                        BsheelCell.mono(
                          _text(s[ProfileColumns.username], '—'),
                          bold: false,
                        ),
                        BsheelCell.meta(_decidedAt(s)),
                        BsheelCell.meta(
                          _shortId(s[SubmissionColumns.reviewedBy]),
                        ),
                        BsheelCell.pill(
                          BsheelPill.status(_outcomeLabel(_outcomeKey(s))),
                        ),
                      ],
                      onTap: () => context.goNamed(
                        AdminRouteNames.submissionReview,
                        pathParameters: {
                          'id': s[SubmissionColumns.id].toString(),
                        },
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${start + 1}–$end OF ${_grouped(rows.length)}',
                      style: BsheelType.monoSm,
                    ),
                  ),
                  // White on the cream page ground, same reason as the
                  // export button above.
                  BsheelButton.secondary(
                    label: 'Prev',
                    small: true,
                    onPressed: page == 0
                        ? null
                        : () => setState(() => _page = page - 1),
                  ),
                  const SizedBox(width: 7),
                  BsheelButton.secondary(
                    label: 'Next',
                    small: true,
                    onPressed: page >= pageCount - 1
                        ? null
                        : () => setState(() => _page = page + 1),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  // ── Filtering ─────────────────────────────────────────────────────

  List<Map<String, dynamic>> _visible(List<Map<String, dynamic>> subs) {
    return subs.where((s) {
      if (_filter != _fAll && _outcomeKey(s) != _filter) return false;
      if (_search.isEmpty) return true;
      final haystack = [
        s[ProfileColumns.username],
        s[ProfileColumns.displayName],
        s['quest_title'],
        s[SubmissionColumns.caption],
      ].map((v) => (v ?? '').toString().toLowerCase());
      return haystack.any((v) => v.contains(_search));
    }).toList(growable: false);
  }

  /// The outcome a moderator reads, which is the stored status plus
  /// whether the user already spent their one appeal on it.
  static String _outcomeKey(Map<String, dynamic> sub) {
    final status = (sub[SubmissionColumns.status] ?? '').toString();
    final appealed = sub[SubmissionColumns.appealed] == true;
    if (status == SubmissionStatus.approved) return SubmissionStatus.approved;
    if (status == SubmissionStatus.rejected) {
      return appealed ? _fReRejected : SubmissionStatus.rejected;
    }
    return appealed ? _fAppealed : SubmissionStatus.pending;
  }

  /// `appealed` is a column name; the pill says what the row is waiting
  /// for, so it reads `APPEAL` and takes gold.
  static String _outcomeLabel(String key) => key == _fAppealed ? 'appeal' : key;

  // ── Cell formatting ───────────────────────────────────────────────

  static String _text(Object? value, String fallback) {
    final s = (value ?? '').toString().trim();
    return s.isEmpty ? fallback : s;
  }

  /// First six characters of a uuid — enough to match against a support
  /// ticket, short enough for an 86px column.
  static String _shortId(Object? value) {
    final s = (value ?? '').toString().replaceAll('-', '');
    if (s.isEmpty) return '—';
    return s.length <= 6 ? s : s.substring(0, 6);
  }

  /// When the call was made. A row still waiting has no decision, so it
  /// says so rather than borrowing its submission time.
  static String _decidedAt(Map<String, dynamic> sub) {
    final dt = DateTime.tryParse(
      (sub[SubmissionColumns.reviewedAt] ?? '').toString(),
    );
    return dt == null ? '—' : _stamp(dt);
  }

  static const List<String> _months = [
    'JAN',
    'FEB',
    'MAR',
    'APR',
    'MAY',
    'JUN',
    'JUL',
    'AUG',
    'SEP',
    'OCT',
    'NOV',
    'DEC',
  ];

  /// `12 MAR 18:04` — the form the design draws.
  static String _stamp(DateTime dt) {
    final l = dt.toLocal();
    return '${l.day.toString().padLeft(2, '0')} ${_months[l.month - 1]} '
        '${l.hour.toString().padLeft(2, '0')}:'
        '${l.minute.toString().padLeft(2, '0')}';
  }

  /// `1,284`. The count is the one number on the page a person reads as a
  /// quantity rather than as an id.
  static String _grouped(int n) {
    final digits = n.toString();
    final out = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i != 0 && (digits.length - i) % 3 == 0) out.write(',');
      out.write(digits[i]);
    }
    return out.toString();
  }

  // ── CSV export ────────────────────────────────────────────────────

  /// Writes the rows currently on screen — filter and search included —
  /// as a CSV the browser downloads. Same transport as the users export.
  void _exportCsv(List<Map<String, dynamic>> rows) {
    try {
      final csv = StringBuffer()
        ..writeln(
          [
            'ID',
            'Quest',
            'User',
            'Decided',
            'Moderator',
            'Outcome',
            'Caption',
          ].map(_csv).join(','),
        );

      for (final s in rows) {
        csv.writeln(
          [
            _text(s[SubmissionColumns.id], ''),
            _text(s['quest_title'], ''),
            _text(s[ProfileColumns.username], ''),
            _decidedAt(s) == '—' ? '' : _decidedAt(s),
            _text(s[SubmissionColumns.reviewedBy], ''),
            _outcomeLabel(_outcomeKey(s)),
            _text(s[SubmissionColumns.caption], ''),
          ].map(_csv).join(','),
        );
      }

      final now = DateTime.now();
      final stamp = '${now.year}'
          '${now.month.toString().padLeft(2, '0')}'
          '${now.day.toString().padLeft(2, '0')}_'
          '${now.hour.toString().padLeft(2, '0')}'
          '${now.minute.toString().padLeft(2, '0')}';
      final filename = 'submission_history_$stamp.csv';

      final blob = web.Blob(
        // The BOM keeps Excel from mangling non-ASCII usernames.
        ['﻿${csv.toString()}'.toJS].toJS,
        web.BlobPropertyBag(type: 'text/csv;charset=utf-8'),
      );
      final url = web.URL.createObjectURL(blob);
      final anchor = web.HTMLAnchorElement()
        ..href = url
        ..setAttribute('download', filename)
        ..style.display = 'none';
      web.document.body?.append(anchor);
      anchor.click();
      anchor.remove();
      web.URL.revokeObjectURL(url);

      _toast('Exported ${rows.length} rows to $filename');
    } catch (e) {
      _toast('Export failed — nothing left the browser. $e');
    }
  }

  /// One CSV field: always quoted, inner quotes doubled, so a caption
  /// containing a comma or a newline cannot shift a column.
  static String _csv(String value) =>
      '"${value.replaceAll('"', '""').replaceAll('\r\n', ' ').replaceAll('\n', ' ')}"';

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}
