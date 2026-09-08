import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/backend/app_backend.dart';
import '../../../../shared/layout/admin_shell.dart';
import '../../../../shared/widgets/bsheel_widgets.dart';

// ── Provider ──────────────────────────────────────────────────────────────────

final webSignupsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  return AppBackend.repositories.admin.waitlist(limit: 500);
});

// ── Page ──────────────────────────────────────────────────────────────────────

class WebSignupsPage extends ConsumerStatefulWidget {
  const WebSignupsPage({super.key});

  @override
  ConsumerState<WebSignupsPage> createState() => _WebSignupsPageState();
}

class _WebSignupsPageState extends ConsumerState<WebSignupsPage> {
  /// The size of one invite batch. Named so the label and the (absent)
  /// call site cannot drift.
  static const int _inviteBatchSize = 25;

  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(webSignupsProvider);
    final total = async.valueOrNull?.length;

    return AdminPane(
      title: 'Web signups',
      meta: total == null ? 'Waitlist' : 'Waitlist · $total',
      child: async.when(
        loading: () => const BsheelLoadingList(rows: 6, rowHeight: 44),
        error: (e, _) => BsheelErrorState(
          title: 'Waitlist didn’t load',
          message: 'The waitlist didn’t come back, so nobody has been invited '
              'and no address was lost. $e',
          onRetry: () => ref.invalidate(webSignupsProvider),
        ),
        data: (rows) {
          if (rows.isEmpty) {
            return BsheelEmptyState(
              title: 'No signups yet',
              message:
                  'Nobody has joined the waitlist from the marketing site. '
                  'Check the site’s signup form is live, then reload.',
              actionLabel: 'Reload',
              onAction: () => ref.invalidate(webSignupsProvider),
            );
          }

          final visible = _filter(rows);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: BsheelSearchField(
                      controller: _search,
                      hint: 'Search email…',
                      onChanged: (v) =>
                          setState(() => _query = v.trim().toLowerCase()),
                    ),
                  ),
                  const SizedBox(width: 9),
                  // No bulk-invite endpoint exists on the admin repository or
                  // the API, so the control states the action and stays
                  // unavailable rather than pretending to send mail.
                  const BsheelButton.positive(
                    label: 'Invite $_inviteBatchSize',
                    onPressed: null,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (visible.isEmpty)
                BsheelEmptyState(
                  title: 'No match',
                  message:
                      'No waiting address contains “${_search.text.trim()}”. '
                      'Clear the search to see the whole waitlist.',
                  actionLabel: 'Clear search',
                  onAction: () {
                    _search.clear();
                    setState(() => _query = '');
                  },
                )
              else
                BsheelTable(
                  depth: 4,
                  columns: const [
                    BsheelColumn('Email'),
                    BsheelColumn('Joined', width: 96),
                    BsheelColumn('Status', width: 92),
                  ],
                  rows: [
                    for (final r in visible)
                      BsheelRow([
                        BsheelCell.mono(_email(r)),
                        BsheelCell.meta(_joined(r)),
                        BsheelCell.pill(
                          BsheelPill.status(_status(r)),
                        ),
                      ]),
                  ],
                ),
            ],
          );
        },
      ),
    );
  }

  List<Map<String, dynamic>> _filter(List<Map<String, dynamic>> rows) {
    if (_query.isEmpty) return rows;
    return rows
        .where((r) => _email(r).toLowerCase().contains(_query))
        .toList(growable: false);
  }

  static String _email(Map<String, dynamic> row) =>
      (row['email'] ?? '').toString();

  /// The waitlist table carries no status column, so a row with nothing
  /// recorded is still waiting on a person — gold. An invited row, once the
  /// API can mark one, arrives already carrying its own status.
  static String _status(Map<String, dynamic> row) {
    final raw = (row['status'] ?? '').toString().trim();
    return raw.isEmpty ? 'waiting' : raw;
  }

  static String _joined(Map<String, dynamic> row) {
    final dt = DateTime.tryParse((row['created_at'] ?? '').toString());
    return dt == null ? '—' : _formatDate(dt);
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

  /// `11 MAR` — the form the design draws.
  static String _formatDate(DateTime dt) {
    final local = dt.toLocal();
    return '${local.day.toString().padLeft(2, '0')} '
        '${_months[local.month - 1]}';
  }
}
