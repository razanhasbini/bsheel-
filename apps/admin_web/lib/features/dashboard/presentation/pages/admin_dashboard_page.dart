import 'package:app_contracts/app_contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/backend/app_backend.dart';
import '../../../../core/providers/admin_counts_provider.dart';
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

    // Real admin name from the signed-in profile; falls back to "Admin"
    // while the lookup is in flight (same source as the sidebar footer).
    // The design's header is the page title, so the greeting the old hero
    // carried lives on the meta line instead.
    final adminName =
        ref.watch(adminMetaProvider).valueOrNull?.displayName.trim() ?? '';
    final firstName = adminName.isEmpty ? 'Admin' : adminName.split(' ').first;

    return AdminPage(
      title: 'Dashboard',
      meta: fetchedAt == null
          ? firstName
          : '$firstName · Updated ${_hhmm(fetchedAt)}',
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _StatTiles(),
          SizedBox(height: 22),
          _QueueSection(),
        ],
      ),
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
              footnote: (oldest == null || oldest.isEmpty)
                  ? null
                  : 'Oldest $oldest',
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
        final width =
            (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final child in children)
              SizedBox(width: width, child: child),
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
              columns: const [
                BsheelColumn('Submission'),
                BsheelColumn('User', width: 96),
                BsheelColumn('Waiting', width: 92),
                BsheelColumn('Type', width: 82),
              ],
              rows: [
                for (final submission in queue)
                  _queueRow(context, submission),
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
