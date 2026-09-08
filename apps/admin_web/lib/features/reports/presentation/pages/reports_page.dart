import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_contracts/supabase_contracts.dart';

import '../../../../core/backend/app_backend.dart';
import '../../../../core/theme/bsheel_design.dart';
import '../../../../shared/widgets/bsheel_widgets.dart';

final reportsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  return AppBackend.repositories.admin.reports(
    status: 'all',
    limit: 100,
  );
});

class ReportsPage extends ConsumerStatefulWidget {
  const ReportsPage({super.key});

  @override
  ConsumerState<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends ConsumerState<ReportsPage> {
  static const _filters = ['pending', 'actioned', 'dismissed', 'all'];
  int _segIndex = 0;

  String get _filter => _filters[_segIndex];

  @override
  Widget build(BuildContext context) {
    final reportsAsync = ref.watch(reportsProvider);

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BsheelCard(
            padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const BsheelEyebrow('Moderation · Reports'),
                const SizedBox(height: 14),
                BsheelDisplay(
                  'Content {reports.}',
                  baseStyle: BsheelType.displayXl.copyWith(fontSize: 44),
                ),
                const SizedBox(height: 12),
                Text(
                  "User-flagged content. Act within 24h — it's how trust gets earned.",
                  style: BsheelType.bodyMd.copyWith(
                    color: BsheelColors.inkSoft,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              BsheelSegmented(
                options: _filters.map((s) => s.toUpperCase()).toList(),
                selected: _segIndex,
                onChanged: (i) => setState(() => _segIndex = i),
              ),
            ],
          ),
          const SizedBox(height: 18),
          reportsAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(40),
              child: Center(
                child: CircularProgressIndicator(color: BsheelColors.ink),
              ),
            ),
            error: (e, _) => BsheelCard.flat(
              color: BsheelColors.hot,
              child: Text(
                'Error: $e',
                style: BsheelType.bodySm.copyWith(color: BsheelColors.paper),
              ),
            ),
            data: (reports) {
              final filtered = _filter == 'all'
                  ? reports
                  : reports.where((r) => r['status'] == _filter).toList();
              if (filtered.isEmpty) return _EmptyState(filter: _filter);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final r in filtered) ...[
                    _ReportCard(
                      data: r,
                      onAction: (status) =>
                          _updateReportStatus(r['id'], status),
                      onBan: () => _banReportedUser(r),
                    ),
                    const SizedBox(height: 14),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _updateReportStatus(String id, String status) async {
    await AppBackend.repositories.admin.reviewReport(
      id,
      status: status,
    );
    ref.invalidate(reportsProvider);
    if (mounted) _toast('Report marked $status.');
  }

  Future<void> _banReportedUser(Map<String, dynamic> r) async {
    if (r['reported_id'] == null) return;

    // The API resolves the reported user for both user and submission
    // reports, so the client no longer needs a second lookup.
    final userId = r['reported_user_id']?.toString();
    if (userId == null) return;

    // Resolve a human-readable name so the admin confirms the right target
    // before an account-level action fires. Falls back to the raw id.
    final username = r['reported_username']?.toString() ?? userId;

    if (!mounted) return;
    final confirmed = await _confirmBan(username);
    if (confirmed != true || !mounted) return;

    try {
      await AppBackend.repositories.admin.setAccountStatus(
        userId,
        'banned',
        'Banned while actioning content report ${r['id']}',
      );
      await _updateReportStatus(r['id'], 'actioned');
      if (mounted) _toast('User banned.');
    } catch (e) {
      if (mounted) _toast('Failed: $e', error: true);
    }
  }

  Future<bool?> _confirmBan(String username) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: BsheelColors.paper,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(BsheelRadii.md),
          side: const BorderSide(color: BsheelColors.hot, width: 1),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.block_rounded,
                      color: BsheelColors.hot,
                      size: 24,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'BAN USER',
                      style: BsheelType.displaySm
                          .copyWith(color: BsheelColors.hot),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  'Ban @$username? Their account is locked immediately '
                  'and they cannot use the app until unbanned. The report '
                  'will be marked actioned.',
                  style: BsheelType.bodySm
                      .copyWith(color: BsheelColors.ink, height: 1.4),
                ),
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: Text(
                        'CANCEL',
                        style: BsheelType.labelSm
                            .copyWith(color: BsheelColors.inkMuted),
                      ),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: BsheelColors.hot,
                        foregroundColor: BsheelColors.pureWhite,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(BsheelRadii.sm),
                        ),
                      ),
                      child: Text(
                        'BAN USER',
                        style: BsheelType.labelSm
                            .copyWith(color: BsheelColors.pureWhite),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _toast(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: BsheelColors.paper,
        content: Text(
          msg,
          style: BsheelType.bodySm.copyWith(
            color: error ? BsheelColors.hot : BsheelColors.ink,
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.filter});
  final String filter;

  @override
  Widget build(BuildContext context) {
    return BsheelCard(
      child: Column(
        children: [
          const SizedBox(height: 24),
          const SizedBox(height: 18),
          BsheelDisplay(
            'No {$filter} reports.',
            baseStyle: BsheelType.displayMd,
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _ReportCard extends StatelessWidget {
  const _ReportCard({
    required this.data,
    required this.onAction,
    required this.onBan,
  });
  final Map<String, dynamic> data;
  final ValueChanged<String> onAction;
  final VoidCallback onBan;

  @override
  Widget build(BuildContext context) {
    final reportedType = data['reported_type']?.toString() ?? '';
    final reason = data['reason']?.toString() ?? '';
    final status = data['status']?.toString() ?? 'pending';
    final createdAt = data['created_at']?.toString() ?? '';
    final profile = data[Tables.profiles] as Map<String, dynamic>?;
    final reporter = profile?[ProfileColumns.username] ?? 'unknown';
    final isPending = status == 'pending';

    final statusTone = switch (status) {
      'pending' => BsheelPillTone.coral,
      'actioned' => BsheelPillTone.green,
      'dismissed' => BsheelPillTone.ghost,
      _ => BsheelPillTone.sky,
    };

    return BsheelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              BsheelPill(reportedType, tone: BsheelPillTone.coral, small: true),
              BsheelPill(status, tone: statusTone, small: true),
              Text(bsheelTimeAgo(createdAt), style: BsheelType.labelSm),
            ],
          ),
          const SizedBox(height: 12),
          Text('Reported by @$reporter', style: BsheelType.bodySm),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: BsheelColors.bg,
              borderRadius: BorderRadius.circular(BsheelRadii.md),
              border: const Border(
                left: BorderSide(color: BsheelColors.hot, width: 1),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const BsheelEyebrow('Reason'),
                const SizedBox(height: 6),
                Text(
                  reason,
                  style: BsheelType.bodyMd.copyWith(
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
          if (isPending) ...[
            const SizedBox(height: 18),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 10,
              runSpacing: 10,
              children: [
                BsheelButton.ghost(
                  label: 'DISMISS',
                  small: true,
                  onPressed: () => onAction('dismissed'),
                ),
                BsheelButton.primary(
                  label: 'MARK ACTIONED',
                  small: true,
                  onPressed: () => onAction('actioned'),
                ),
                BsheelButton.coral(
                  label: 'BAN USER',
                  small: true,
                  icon: Icons.block_rounded,
                  onPressed: onBan,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
