import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/providers/admin_counts_provider.dart';
import '../../../../core/backend/app_backend.dart';
import '../../../../core/router/admin_route_names.dart';
import '../../../../core/theme/bsheel_design.dart';
import '../../../../shared/widgets/bsheel_widgets.dart';

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

// ── Page ─────────────────────────────────────────────────────────────

class AdminDashboardPage extends ConsumerWidget {
  const AdminDashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(_dashboardStatsProvider);
    final width = MediaQuery.of(context).size.width;
    final isMobile = width < 700;

    // Real admin name from the signed-in profile; falls back to "Admin"
    // while the lookup is in flight (same source as the sidebar footer).
    final adminName =
        ref.watch(adminMetaProvider).valueOrNull?.displayName.trim() ?? '';
    final firstName = adminName.isEmpty ? 'Admin' : adminName.split(' ').first;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Page hero ─────────────────────────────────────────
          BsheelCard(
            padding: EdgeInsets.symmetric(
              horizontal: isMobile ? 22 : 36,
              vertical: isMobile ? 24 : 32,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      BsheelEyebrow('Today · ${_dateLabel()}'),
                      const SizedBox(height: 14),
                      BsheelDisplay(
                        'Good {${_greetingWord()},}\n$firstName.',
                        baseStyle: BsheelType.displayXl.copyWith(
                          fontSize: isMobile ? 36 : 48,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!isMobile)
                  statsAsync.when(
                    data: (s) => Text(
                      '${s['pending']} PENDING · ${s['appeals']} APPEALS\n'
                      '${s['pendingReports']} REPORTS · ${s['activeQuests']} ACTIVE QUESTS',
                      textAlign: TextAlign.right,
                      style: BsheelType.labelLg,
                    ),
                    loading: () => const SizedBox.shrink(),
                    error: (_, __) => const SizedBox.shrink(),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // ── Tile grid ────────────────────────────────────────
          statsAsync.when(
            loading: () => const _TilesSkeleton(),
            error: (e, _) => _ErrorBanner(error: '$e'),
            data: (s) => _TileGrid(
              tiles: [
                BsheelTile(
                  eyebrow: 'Queue depth',
                  value: '${s['pending']}',
                  color: BsheelColors.accent,
                  onTap: () =>
                      context.goNamed(AdminRouteNames.pendingSubmissions),
                ),
                BsheelTile(
                  eyebrow: 'Reports open',
                  value: '${s['pendingReports']}',
                  color: BsheelColors.hot,
                  foreground: BsheelColors.paper,
                  onTap: () => context.goNamed(AdminRouteNames.reports),
                ),
                BsheelTile(
                  eyebrow: 'Approved · 24h',
                  value: '${s['approvedToday']}',
                  onTap: () =>
                      context.goNamed(AdminRouteNames.submissionHistory),
                ),
                BsheelTile(
                  eyebrow: 'Active quests',
                  value: '${s['activeQuests']}',
                  color: BsheelColors.primary,
                  foreground: BsheelColors.paper,
                  onTap: () => context.goNamed(AdminRouteNames.questManagement),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          // ── Moderation breakdown + Today's queue card row ─────
          if (!isMobile)
            Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 2,
                  child: _ModerationLoadCard(stats: statsAsync),
                ),
                const SizedBox(width: 18),
                Expanded(child: _QueueProgressCard(stats: statsAsync)),
              ],
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ModerationLoadCard(stats: statsAsync),
                const SizedBox(height: 18),
                _QueueProgressCard(stats: statsAsync),
              ],
            ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  String _greetingWord() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'morning';
    if (hour < 17) return 'afternoon';
    return 'evening';
  }

  String _dateLabel() {
    final now = DateTime.now();
    const months = [
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
    const wk = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
    return '${wk[now.weekday - 1]} ${now.day} ${months[now.month - 1]}';
  }
}

// ── Tile grid layout ─────────────────────────────────────────────────

class _TileGrid extends StatelessWidget {
  const _TileGrid({required this.tiles});
  final List<Widget> tiles;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final cols = c.maxWidth < 600
            ? 1
            : c.maxWidth < 1180
                ? 2
                : 4;
        const gap = 18.0;
        final w = (c.maxWidth - gap * (cols - 1)) / cols;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: tiles.map((t) => SizedBox(width: w, child: t)).toList(),
        );
      },
    );
  }
}

class _TilesSkeleton extends StatelessWidget {
  const _TilesSkeleton();

  @override
  Widget build(BuildContext context) {
    Widget shell() => Container(
          height: 130,
          decoration: BoxDecoration(
            color: BsheelColors.paper,
            borderRadius: BorderRadius.circular(BsheelRadii.lg),
            border: Border.all(
              color: BsheelColors.line,
              width: BsheelBorders.thin,
            ),
          ),
        );
    return LayoutBuilder(
      builder: (context, c) {
        return Row(
          children: List.generate(4, (i) {
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: i == 3 ? 0 : 18),
                child: shell(),
              ),
            );
          }),
        );
      },
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.error});
  final String error;

  @override
  Widget build(BuildContext context) {
    return BsheelCard.flat(
      child: Text(
        error,
        style: BsheelType.bodySm.copyWith(color: BsheelColors.hot),
      ),
    );
  }
}

// ── Moderation load card (real counts, tag-dot legend) ───────────────

class _ModerationLoadCard extends StatelessWidget {
  const _ModerationLoadCard({required this.stats});
  final AsyncValue<Map<String, int>> stats;

  @override
  Widget build(BuildContext context) {
    final s = stats.valueOrNull;
    final pending = s?['pending'] ?? 0;
    final appeals = s?['appeals'] ?? 0;
    final reports = s?['pendingReports'] ?? 0;
    final approvedToday = s?['approvedToday'] ?? 0;

    return BsheelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const BsheelEyebrow('Moderation · live counts'),
          const SizedBox(height: 6),
          BsheelDisplay(
            s != null && pending == 0
                ? 'Queue is {clear.}'
                : 'Work the {queue.}',
            baseStyle: BsheelType.displayMd,
          ),
          const SizedBox(height: 16),
          if (s == null)
            Text(
              '—',
              style: BsheelType.bodyMd.copyWith(color: BsheelColors.inkMuted),
            )
          else
            Wrap(
              spacing: 18,
              runSpacing: 8,
              children: [
                _TagDot(color: BsheelColors.accent, label: '$pending in queue'),
                _TagDot(color: BsheelColors.primary, label: '$appeals appeals'),
                _TagDot(color: BsheelColors.hot, label: '$reports reports'),
                _TagDot(
                  color: BsheelColors.cool,
                  label: '$approvedToday approved · 24h',
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _TagDot extends StatelessWidget {
  const _TagDot({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: BsheelColors.ink, width: 1.5),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: BsheelType.bodyMd.copyWith(fontSize: 13),
        ),
      ],
    );
  }
}

// ── Today's queue (ink-fill card with progress) ─────────────────────

class _QueueProgressCard extends ConsumerWidget {
  const _QueueProgressCard({required this.stats});
  final AsyncValue<Map<String, int>> stats;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Share of the last 24h's reviewable work that has been approved:
    // approved (24h) vs approved (24h) + still pending. Empty queue with
    // nothing approved reads as fully cleared.
    final s = stats.valueOrNull;
    final approved = s?['approvedToday'] ?? 0;
    final pending = s?['pending'] ?? 0;
    final total = approved + pending;
    final double? progress =
        s == null ? null : (total == 0 ? 1.0 : approved / total);

    return BsheelCard(
      color: BsheelColors.ink,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BsheelEyebrow(
            "Today's queue",
            color: BsheelColors.paper.withValues(alpha: 0.85),
          ),
          const SizedBox(height: 6),
          Text(
            'Clear it\nout.',
            style: BsheelType.displayMd.copyWith(
              color: BsheelColors.paper,
              fontSize: 26,
              height: 1.05,
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Text(
                'CLEARED · 24H',
                style: BsheelType.labelMd.copyWith(
                  color: BsheelColors.paper.withValues(alpha: 0.7),
                ),
              ),
              const Spacer(),
              Text(
                progress == null ? '—' : '${(progress * 100).round()}%',
                style: BsheelType.displaySm.copyWith(
                  fontSize: 18,
                  color: BsheelColors.paper,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          BsheelProgress(
            value: progress ?? 0,
            fill: BsheelColors.accent,
          ),
          const SizedBox(height: 18),
          BsheelButton.primary(
            label: 'Open queue →',
            onPressed: () => GoRouter.of(context)
                .goNamed(AdminRouteNames.pendingSubmissions),
          ),
        ],
      ),
    );
  }
}
