import 'package:app_contracts/app_contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/backend/app_backend.dart';
import '../../../../core/router/admin_route_names.dart';
import '../../../../core/theme/bsheel_design.dart';
import '../../../../shared/layout/admin_shell.dart';
import '../../../../shared/widgets/bsheel_widgets.dart';
import '../../../moderation/presentation/providers/pending_submissions_provider.dart';

// ── Providers ────────────────────────────────────────────────────────

/// All seven dashboard counters come from one `/admin/stats` query — the
/// page previously issued seven separate count round-trips.
final _dashboardStatsProvider =
    FutureProvider.autoDispose<Map<String, int>>((ref) async {
  final stats = await AppBackend.repositories.admin.stats();
  int count(String key) => (stats[key] as num?)?.toInt() ?? 0;
  return {
    'users': count('users'),
    'pending': count('pending'),
    'quests': count('quests'),
    'approvedToday': count('approvedToday'),
    'activeQuests': count('activeQuests'),
    'appeals': count('appeals'),
    'pendingReports': count('pendingReports'),
  };
});

/// How many queue rows the dashboard shows. The dashboard answers "what
/// would I pick up next", not "show me everything", so it reads the head
/// of the queue rather than the whole thing.
const int _queueRows = 5;

/// The head of the review queue — pending submissions, oldest first, from
/// the same admin read the moderation queue page issues. The first row is
/// therefore the oldest thing waiting on a person, which is also where the
/// "oldest" footnote on the awaiting-review tile comes from.
final _queueHeadProvider =
    FutureProvider.autoDispose<List<PendingSubmission>>((ref) async {
  final rows = await AppBackend.repositories.moderation.listSubmissionsForAdmin(
    status: SubmissionStatus.pending,
    order: 'asc',
    limit: _queueRows,
  );
  return rows.map(PendingSubmission.fromJson).toList();
});

/// How far back the throughput chart and the actions list read. The
/// design draws fourteen bars; the window is capped by [_decidedLimit],
/// so the chart renders only the days it can actually see (see
/// [_ThroughputPanel]) rather than painting a truncated day as a zero.
const int _throughputDays = 14;

/// One API page of decided submissions. Both right-column panels read the
/// same fetch — the chart buckets it by day, the actions list takes the
/// head of it — so the dashboard does not issue two overlapping reads for
/// the same rows.
///
/// It asked for 400 and the endpoint caps `limit` at 100, so every request
/// came back 400 Bad Request and both panels rendered empty — indistinguishable
/// from a quiet fortnight. The cap is the contract; ask for exactly it.
const int _decidedLimit = adminSubmissionListMaxLimit;

/// Decided submissions, newest decision first.
///
/// There is no `admin_audit_log` read endpoint on the API (the table is
/// written but never exposed), so this is the whole of the admin activity
/// the console can honestly show: moderation decisions. Anything else an
/// admin does — setting the Quest of the Day, editing the bank — is
/// audited server-side and cannot be read back yet.
final _decidedProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final rows = await AppBackend.repositories.moderation.listSubmissionsForAdmin(
    status: 'all',
    order: 'desc',
    limit: _decidedLimit,
  );
  // `status: all` includes what is still pending; a decision is a row with
  // a `reviewed_at`, so filter on that rather than on the status string.
  final decided = rows
      .where(
        (r) =>
            DateTime.tryParse(
              (r[SubmissionColumns.reviewedAt] ?? '').toString(),
            ) !=
            null,
      )
      .toList()
    ..sort((a, b) => _reviewedAt(b)!.compareTo(_reviewedAt(a)!));
  return decided;
});

DateTime? _reviewedAt(Map<String, dynamic> row) => DateTime.tryParse(
      (row[SubmissionColumns.reviewedAt] ?? '').toString(),
    );

/// The moment the counters last landed, for the header's freshness line.
///
/// Derived rather than folded into [_dashboardStatsProvider] so that
/// provider stays exactly the counter map every other reader expects. It
/// recomputes only when the stats `AsyncValue` itself changes, so the
/// stamp does not drift on unrelated rebuilds.
final _statsFetchedAtProvider = Provider.autoDispose<DateTime?>((ref) {
  final stats = ref.watch(_dashboardStatsProvider);
  return stats.hasValue ? DateTime.now() : null;
});

String _hhmm(DateTime at) {
  final local = at.toLocal();
  final h = local.hour.toString().padLeft(2, '0');
  final m = local.minute.toString().padLeft(2, '0');
  return '$h:$m';
}

// ── Page ─────────────────────────────────────────────────────────────

/// What needs a human, ordered by how long it has waited.
class AdminDashboardPage extends ConsumerWidget {
  const AdminDashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fetchedAt = ref.watch(_statsFetchedAtProvider);

    return AdminPage(
      title: 'Dashboard',
      // The design's meta line is the freshness stamp and nothing else —
      // who is signed in is already the sidebar footer's job, and saying
      // it twice on the same screen is what pushed the stamp off the end
      // of the line on a narrow window.
      meta: fetchedAt == null ? null : 'Updated ${_hhmm(fetchedAt)}',
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _StatTiles(),
          SizedBox(height: 22),
          _WorkColumns(),
        ],
      ),
    );
  }
}

/// The queue beside the two read-only panels, `1.35fr / 1fr` as drawn.
/// Below the two-column threshold they stack, queue first: the queue is
/// the only thing on this page a moderator can act on.
class _WorkColumns extends StatelessWidget {
  const _WorkColumns();

  /// Under this the 4-column queue table and a 300px-ish panel column
  /// cannot both hold their minimums.
  static const double _twoColumnMin = 900;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < _twoColumnMin) {
          return const Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _QueueSection(),
              SizedBox(height: 20),
              _ThroughputPanel(),
              SizedBox(height: 20),
              _RecentActionsPanel(),
            ],
          );
        }
        return const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 135, child: _QueueSection()),
            SizedBox(width: 20),
            Expanded(
              flex: 100,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _ThroughputPanel(),
                  SizedBox(height: 20),
                  _RecentActionsPanel(),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

// ── Stat tiles ───────────────────────────────────────────────────────

class _StatTiles extends ConsumerWidget {
  const _StatTiles();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(_dashboardStatsProvider);
    final queueHead = ref.watch(_queueHeadProvider).valueOrNull;

    return statsAsync.when(
      loading: () => _TileGrid(
        children: List.generate(4, (_) => const BsheelSkeleton(height: 100)),
      ),
      error: (error, _) => BsheelErrorState(
        title: 'Counters unavailable',
        message: "The counters didn't come back. Nothing was lost — no "
            'decision has been recorded, and the queue below is unaffected.',
        onRetry: () => ref.invalidate(_dashboardStatsProvider),
      ),
      data: (s) {
        // First run: a wall of zeroes tells a new operator nothing, so the
        // tiles are suppressed until there is something to count.
        if (s.values.every((count) => count == 0)) {
          return BsheelEmptyState(
            title: 'Nothing to count yet',
            message: 'No users, quests or submissions have landed. Fill the '
                'quest bank first — assignments and submissions follow from '
                'there, and these counters fill in behind them.',
            actionLabel: 'Open quest bank',
            onAction: () => context.goNamed(AdminRouteNames.questManagement),
          );
        }

        // The queue is read oldest-first, so its first row is the oldest
        // thing waiting. No queue read yet means no footnote — never a
        // guessed number.
        final oldest = (queueHead == null || queueHead.isEmpty)
            ? null
            : bsheelWaiting(
                queueHead.first.submittedAt.toIso8601String(),
                fallback: '',
              );

        return _TileGrid(
          children: [
            BsheelStatTile(
              label: 'Awaiting review',
              value: '${s['pending']}',
              footnote:
                  (oldest == null || oldest.isEmpty) ? null : 'Oldest $oldest',
              ground: BsheelColors.accent,
              onTap: () => context.goNamed(AdminRouteNames.pendingSubmissions),
            ),
            BsheelStatTile(
              label: 'Appeals open',
              value: '${s['appeals']}',
              footnote: 'Second review',
              ground: BsheelColors.danger,
              onTap: () => context.goNamed(AdminRouteNames.appeals),
            ),
            BsheelStatTile(
              label: 'Reports',
              value: '${s['pendingReports']}',
              footnote: 'Untriaged',
              onTap: () => context.goNamed(AdminRouteNames.reports),
            ),
            BsheelStatTile(
              label: 'Decided today',
              value: '${s['approvedToday']}',
              // `approvedToday` counts approvals in the last 24h, so the
              // footnote says which decisions the number covers rather
              // than inventing the median the design draws.
              footnote: 'Approved · 24h',
              ground: BsheelColors.success,
              onTap: () => context.goNamed(AdminRouteNames.submissionHistory),
            ),
          ],
        );
      },
    );
  }
}

/// Four across on a full-width shell, two on a tablet, one on a phone.
class _TileGrid extends StatelessWidget {
  const _TileGrid({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth < 560
            ? 1
            : constraints.maxWidth < 900
                ? 2
                : 4;
        const gap = 12.0;
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final child in children) SizedBox(width: width, child: child),
          ],
        );
      },
    );
  }
}

// ── Queue — oldest first ─────────────────────────────────────────────

class _QueueSection extends ConsumerWidget {
  const _QueueSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queueAsync = ref.watch(_queueHeadProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(child: BsheelLabel('Queue — oldest first')),
            const SizedBox(width: 12),
            BsheelLink(
              'Open moderation',
              onTap: () => context.goNamed(AdminRouteNames.pendingSubmissions),
            ),
          ],
        ),
        const SizedBox(height: 10),
        queueAsync.when(
          loading: () =>
              const BsheelLoadingList(rows: _queueRows, rowHeight: 40),
          error: (error, _) => BsheelErrorState(
            title: 'Queue unavailable',
            message: "The queue didn't come back. Nothing was lost — no "
                'decision has been recorded and nothing left the queue.',
            onRetry: () => ref.invalidate(_queueHeadProvider),
          ),
          data: (queue) {
            if (queue.isEmpty) {
              return BsheelEmptyState.allClear(
                message: 'Nothing is waiting on a moderator. New submissions '
                    'land here the moment they arrive.',
                actionLabel: 'Open moderation',
                onAction: () =>
                    context.goNamed(AdminRouteNames.pendingSubmissions),
              );
            }
            return BsheelTable(
              // 4px here, not the 5px a full-page table takes: on the
              // dashboard this is one panel among several, and the design
              // reserves the deeper shadow for a table that *is* the page.
              depth: 4,
              columns: const [
                BsheelColumn('Submission'),
                BsheelColumn('User', width: 96),
                BsheelColumn('Waiting', width: 92),
                BsheelColumn('Type', width: 82),
              ],
              rows: [
                for (final submission in queue) _queueRow(context, submission),
              ],
            );
          },
        ),
      ],
    );
  }

  BsheelRow _queueRow(BuildContext context, PendingSubmission submission) {
    final iso = submission.submittedAt.toIso8601String();
    final stale = bsheelIsStale(iso);

    return BsheelRow(
      [
        BsheelCell.title(submission.questTitle ?? '—'),
        BsheelCell.mono(submission.username ?? '—', bold: false),
        BsheelCell.mono(
          bsheelWaiting(iso),
          // Coral once an item has waited past the review window — the one
          // row that has been ignored too long is the point of this table.
          color: stale ? BsheelColors.dangerText : BsheelColors.ink,
          bold: stale,
        ),
        submission.appealed
            ? BsheelCell.pill(
                const BsheelPill(
                  'Appeal',
                  tone: BsheelPillTone.gold,
                  small: true,
                ),
              )
            : BsheelCell.label('First'),
      ],
      onTap: () => context.goNamed(
        AdminRouteNames.submissionReview,
        pathParameters: {'id': submission.id},
      ),
    );
  }
}

// ── Review throughput ────────────────────────────────────────────────

/// Decisions per day, newest on the right, as a bar per day.
///
/// The label carries the number of days the chart actually covers rather
/// than a flat `14 DAYS`: the fetch is one API page, so on a busy console
/// it may only reach back a few days, and drawing the days it cannot see
/// as empty bars would read as "nobody worked" instead of "not fetched".
class _ThroughputPanel extends ConsumerWidget {
  const _ThroughputPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final decidedAsync = ref.watch(_decidedProvider);

    return decidedAsync.when(
      loading: () => const _Panel(
        label: 'Review throughput',
        child: BsheelSkeleton(height: 124, radius: BsheelRadii.lg),
      ),
      // The chart is a read-only aside. A failure here must not shout over
      // the queue, which is the page's actual job, so it states the gap on
      // one line and leaves the retry to the queue's own error state.
      error: (_, __) => const _Panel(
        label: 'Review throughput',
        child: _PanelNote('The decision history did not come back, so the '
            'chart is empty. Nothing else on this page is affected.'),
      ),
      data: (decided) {
        if (decided.isEmpty) {
          return const _Panel(
            label: 'Review throughput',
            child: _PanelNote('No submission has been decided yet, so there '
                'is nothing to plot.'),
          );
        }

        final today = DateTime.now().toLocal();
        final midnight = DateTime(today.year, today.month, today.day);

        // Only count back as far as the fetch reached, so a truncated
        // window shows fewer bars rather than false zeroes.
        final oldest = _reviewedAt(decided.last)!.toLocal();
        final covered = midnight
                .difference(DateTime(oldest.year, oldest.month, oldest.day))
                .inDays +
            1;
        final days = covered.clamp(1, _throughputDays);

        final buckets = List<double>.filled(days, 0);
        for (final row in decided) {
          final at = _reviewedAt(row)!.toLocal();
          final age =
              midnight.difference(DateTime(at.year, at.month, at.day)).inDays;
          if (age < 0 || age >= days) continue;
          buckets[days - 1 - age] += 1;
        }

        return _Panel(
          label: 'Review throughput · $days ${days == 1 ? "day" : "days"}',
          child: BsheelBarChart(values: buckets),
        );
      },
    );
  }
}

// ── Recent admin actions ─────────────────────────────────────────────

/// The last few moderation decisions, newest first.
class _RecentActionsPanel extends ConsumerWidget {
  const _RecentActionsPanel();

  /// Three rows is what the design draws, and what fits beside the chart
  /// without the column outgrowing the queue next to it.
  static const int _rows = 3;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final decidedAsync = ref.watch(_decidedProvider);

    return decidedAsync.when(
      loading: () => const _Panel(
        label: 'Recent admin actions',
        footnote: _actionsFootnote,
        child: BsheelSkeleton(height: 116, radius: BsheelRadii.lg),
      ),
      error: (_, __) => const _Panel(
        label: 'Recent admin actions',
        child: _PanelNote('The decision log did not come back. No decision '
            'was lost — this panel only reads.'),
      ),
      data: (decided) {
        if (decided.isEmpty) {
          return const _Panel(
            label: 'Recent admin actions',
            footnote: _actionsFootnote,
            child: _PanelNote('Nothing has been decided yet. The first '
                'approval or rejection lands here.'),
          );
        }

        final rows = decided.take(_rows).toList();
        return _Panel(
          label: 'Recent admin actions',
          footnote: _actionsFootnote,
          child: Container(
            decoration: BoxDecoration(
              color: BsheelColors.card,
              borderRadius: BorderRadius.circular(BsheelRadii.lg),
              border: const Border.fromBorderSide(BsheelBorders.inkSide),
              boxShadow: BsheelShadows.md,
            ),
            child: Column(
              children: [
                for (var i = 0; i < rows.length; i++)
                  _ActionRow(row: rows[i], last: i == rows.length - 1),
              ],
            ),
          ),
        );
      },
    );
  }

  /// The design's footnote reads `IMMUTABLE — WRITTEN TO admin_audit_log`.
  /// The audit table exists and is written, but the API exposes no way to
  /// read it, so this panel is built from the submissions themselves and
  /// says exactly that instead of claiming a source it never touched.
  static const String _actionsFootnote =
      'Moderation decisions only — the full audit log is not readable yet';
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({required this.row, required this.last});

  final Map<String, dynamic> row;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final at = _reviewedAt(row)!.toLocal();
    final approved = (row[SubmissionColumns.status] ?? '').toString() ==
        SubmissionStatus.approved;
    final note = (row[SubmissionColumns.reviewNote] as String?)
        ?.split('\n')
        .map((line) => line.replaceFirst('•', '').trim())
        .where((line) => line.isNotEmpty)
        .join(', ');
    final moderator = _shortId(row[SubmissionColumns.reviewedBy]);
    final target = _shortId(row[SubmissionColumns.id]);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      constraints: const BoxConstraints(minHeight: BsheelLayout.minTarget),
      decoration: last
          ? null
          : const BoxDecoration(border: Border(bottom: BsheelBorders.rowSide)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _hhmm(at),
            style: BsheelType.labelMd.copyWith(letterSpacing: 0),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  const TextSpan(text: 'Moderator '),
                  TextSpan(text: moderator, style: _idStyle),
                  TextSpan(text: approved ? ' approved ' : ' rejected '),
                  TextSpan(text: target, style: _idStyle),
                  if (!approved && note != null && note.isNotEmpty)
                    TextSpan(text: ' — $note'),
                ],
              ),
              // 12px on a 14px line is the design's audit line. Body copy,
              // so it takes inkSoft rather than the placeholder muted.
              style: BsheelType.bodyXs.copyWith(color: BsheelColors.inkSoft),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  /// An id inside the sentence: mono, ink, so it reads as a value to
  /// quote rather than as part of the prose.
  static final TextStyle _idStyle = BsheelType.bodyXs.copyWith(
    fontFamily: BsheelFonts.mono,
    fontWeight: FontWeight.w700,
    color: BsheelColors.ink,
  );

  /// First six characters of a uuid — enough to match a support thread.
  static String _shortId(Object? value) {
    final s = (value ?? '').toString().replaceAll('-', '');
    if (s.isEmpty) return '—';
    return s.length <= 6 ? s : s.substring(0, 6);
  }
}

// ── Panel chrome ─────────────────────────────────────────────────────

/// A tracked mono label, the panel, and an optional footnote under it —
/// the shape both right-column panels share.
class _Panel extends StatelessWidget {
  const _Panel({required this.label, required this.child, this.footnote});

  final String label;
  final Widget child;
  final String? footnote;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BsheelLabel(label),
        const SizedBox(height: 10),
        child,
        if (footnote != null) ...[
          const SizedBox(height: 8),
          Text(
            footnote!.toUpperCase(),
            style: BsheelType.labelSm.copyWith(height: 1.5),
          ),
        ],
      ],
    );
  }
}

/// One sentence where a panel has nothing to draw. Dashed muted outline,
/// so an empty panel reads as empty rather than as broken.
class _PanelNote extends StatelessWidget {
  const _PanelNote(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return BsheelCard.muted(
      child: Text(
        message,
        style: BsheelType.bodySm.copyWith(color: BsheelColors.inkSoft),
      ),
    );
  }
}
