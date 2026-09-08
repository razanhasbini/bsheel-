import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:app_contracts/app_contracts.dart';

import '../../../../core/backend/app_backend.dart';
import '../../../../core/router/admin_route_names.dart';

import '../../../../core/theme/bsheel_design.dart';
import '../../../../shared/widgets/bsheel_widgets.dart';

/// Every submission, newest first. Media keys are signed by the adapter.
final _allSubmissionsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  return AppBackend.repositories.moderation.listSubmissionsForAdmin(
    status: 'all',
    order: 'desc',
  );
});

class SubmissionHistoryPage extends ConsumerStatefulWidget {
  const SubmissionHistoryPage({super.key});

  @override
  ConsumerState<SubmissionHistoryPage> createState() =>
      _SubmissionHistoryPageState();
}

class _SubmissionHistoryPageState extends ConsumerState<SubmissionHistoryPage> {
  String _filter = 'all';
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final subsAsync = ref.watch(_allSubmissionsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BsheelCard(
          padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const BsheelEyebrow('Moderation · History'),
              const SizedBox(height: 14),
              BsheelDisplay(
                'The {ledger.}',
                baseStyle: BsheelType.hero(context),
              ),
              const SizedBox(height: 12),
              Text(
                'Every submission, every status. Use filters to narrow down '
                'when an old call needs revisiting.',
                style: BsheelType.bodyMd.copyWith(color: BsheelColors.inkSoft),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        // Filters row — on mobile, wrap chips and search vertically
        LayoutBuilder(
          builder: (context, constraints) {
            final isMobile = constraints.maxWidth < 600;
            final chips = [
              _FilterChip(
                label: 'ALL',
                value: 'all',
                current: _filter,
                onTap: () => setState(() => _filter = 'all'),
              ),
              _FilterChip(
                label: 'PENDING',
                value: SubmissionStatus.pending,
                current: _filter,
                color: BsheelColors.cool,
                onTap: () => setState(() => _filter = SubmissionStatus.pending),
              ),
              _FilterChip(
                label: 'APPROVED',
                value: SubmissionStatus.approved,
                current: _filter,
                color: BsheelColors.success,
                onTap: () =>
                    setState(() => _filter = SubmissionStatus.approved),
              ),
              _FilterChip(
                label: 'REJECTED',
                value: SubmissionStatus.rejected,
                current: _filter,
                color: BsheelColors.hot,
                onTap: () =>
                    setState(() => _filter = SubmissionStatus.rejected),
              ),
            ];
            final searchField = TextField(
              style: BsheelType.bodySm,
              decoration: InputDecoration(
                hintText: 'Search...',
                hintStyle: BsheelType.bodySm.copyWith(
                  color: BsheelColors.inkMuted,
                ),
                prefixIcon: const Icon(
                  Icons.search,
                  color: BsheelColors.inkMuted,
                ),
                filled: true,
                fillColor: BsheelColors.paper,
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(BsheelRadii.md),
                  borderSide: const BorderSide(color: BsheelColors.line),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(BsheelRadii.md),
                  borderSide: const BorderSide(
                    color: BsheelColors.line,
                    width: BsheelBorders.thin,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(BsheelRadii.md),
                  borderSide: const BorderSide(
                    color: BsheelColors.ink,
                    width: BsheelBorders.thin,
                  ),
                ),
              ),
              onChanged: (v) => setState(() => _search = v.toLowerCase()),
            );
            if (isMobile) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: QuestSpacing.sm,
                    runSpacing: QuestSpacing.sm,
                    children: chips,
                  ),
                  const SizedBox(height: QuestSpacing.sm),
                  searchField,
                ],
              );
            }
            return Row(
              children: [
                ...chips
                    .expand((c) => [c, const SizedBox(width: QuestSpacing.sm)]),
                const SizedBox(width: QuestSpacing.sm),
                Expanded(child: searchField),
              ],
            );
          },
        ),
        const SizedBox(height: QuestSpacing.md),
        Expanded(
          child: subsAsync.when(
            loading: () => const Center(
              child: CircularProgressIndicator(color: BsheelColors.primary),
            ),
            error: (e, _) => Center(
              child: Text(
                'Error: $e',
                textAlign: TextAlign.center,
                style: BsheelType.bodySm.copyWith(
                  color: BsheelColors.onCream(BsheelColors.danger),
                ),
              ),
            ),
            data: (subs) {
              final filtered = subs.where((s) {
                if (_filter != 'all' &&
                    s[SubmissionColumns.status] != _filter) {
                  return false;
                }
                if (_search.isNotEmpty) {
                  final username =
                      (s['username'] ?? '').toString().toLowerCase();
                  final caption = (s[SubmissionColumns.caption] ?? '')
                      .toString()
                      .toLowerCase();
                  return username.contains(_search) ||
                      caption.contains(_search);
                }
                return true;
              }).toList();

              if (filtered.isEmpty) {
                return Center(
                  child: Text(
                    'No submissions found.',
                    style: BsheelType.bodyMd.copyWith(
                      color: BsheelColors.inkMuted,
                    ),
                  ),
                );
              }

              return LayoutBuilder(
                builder: (context, constraints) {
                  if (constraints.maxWidth < 600) {
                    return ListView.separated(
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: QuestSpacing.sm),
                      itemBuilder: (context, i) =>
                          _buildMobileCard(context, filtered[i]),
                    );
                  }
                  return Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: BsheelColors.paper,
                      border: Border.all(
                        color: BsheelColors.line,
                        width: BsheelBorders.thin,
                      ),
                      borderRadius: BorderRadius.circular(BsheelRadii.lg),
                    ),
                    // Seven columns cannot fit a narrow window: the
                    // table scrolls sideways inside its card rather than
                    // painting outside it.
                    child: SingleChildScrollView(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minWidth:
                                constraints.maxWidth - BsheelBorders.thick * 2,
                          ),
                          child: DataTable(
                            headingRowColor: WidgetStateProperty.all(
                              BsheelColors.surface,
                            ),
                            dataRowColor: WidgetStateProperty.resolveWith(
                              (states) => BsheelColors.paper,
                            ),
                            columnSpacing: 20,
                            headingTextStyle: BsheelType.labelSm.copyWith(
                              color: BsheelColors.inkMuted,
                              letterSpacing: 1.5,
                            ),
                            dataTextStyle: BsheelType.bodySm.copyWith(
                              color: BsheelColors.ink,
                            ),
                            columns: const [
                              DataColumn(label: Text('MEDIA')),
                              DataColumn(label: Text('USER')),
                              DataColumn(label: Text('QUEST')),
                              DataColumn(label: Text('CAPTION')),
                              DataColumn(label: Text('STATUS')),
                              DataColumn(label: Text('SUBMITTED')),
                              DataColumn(label: Text('ACTIONS')),
                            ],
                            rows: filtered
                                .asMap()
                                .entries
                                .map((e) => _buildRow(context, e.value, e.key))
                                .toList(),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildMobileCard(BuildContext context, Map<String, dynamic> sub) {
    final username = sub['username'] ?? '-';
    final questTitle = sub['quest_title'] ?? '-';
    final caption = sub[SubmissionColumns.caption]?.toString() ?? '';
    final status = sub[SubmissionColumns.status]?.toString() ?? '';
    final mediaUrl = sub[SubmissionColumns.mediaUrl]?.toString() ?? '';
    final mediaType = sub[SubmissionColumns.mediaType]?.toString() ?? 'image';
    final submittedAt = DateTime.tryParse(
      sub[SubmissionColumns.submittedAt]?.toString() ?? '',
    );
    final id = sub[SubmissionColumns.id]?.toString() ?? '';

    final (Color statusBg, Color statusFg) = switch (status) {
      'approved' => (
          BsheelColors.success.withAlpha(30),
          BsheelColors.success,
        ),
      'rejected' => (BsheelColors.hot.withAlpha(30), BsheelColors.hot),
      _ => (
          BsheelColors.cool.withAlpha(30),
          BsheelColors.cool,
        ),
    };

    return Container(
      decoration: BoxDecoration(
        color: BsheelColors.paper,
        border: Border.all(
          color: BsheelColors.line,
          width: BsheelBorders.thin,
        ),
        borderRadius: BorderRadius.circular(BsheelRadii.lg),
      ),
      padding: const EdgeInsets.all(QuestSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(BsheelRadii.md),
            child: mediaType == 'video'
                ? Container(
                    width: 48,
                    height: 48,
                    color: BsheelColors.ink,
                    child: const Icon(
                      Icons.videocam,
                      size: 24,
                      color: BsheelColors.cool,
                    ),
                  )
                : Image.network(
                    mediaUrl,
                    width: 48,
                    height: 48,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      width: 48,
                      height: 48,
                      color: BsheelColors.ink,
                      child: const Icon(
                        Icons.broken_image,
                        size: 24,
                        color: BsheelColors.inkMuted,
                      ),
                    ),
                  ),
          ),
          const SizedBox(width: QuestSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '@$username',
                  style: BsheelType.bodySm.copyWith(
                    fontWeight: FontWeight.w500,
                    color: BsheelColors.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  questTitle,
                  style: BsheelType.labelSm.copyWith(
                    color: BsheelColors.inkMuted,
                  ),
                ),
                if (caption.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    caption,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: BsheelType.bodySm.copyWith(
                      color: BsheelColors.inkSoft,
                      fontSize: 11,
                    ),
                  ),
                ],
                const SizedBox(height: QuestSpacing.xs),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: QuestSpacing.sm,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: statusBg,
                        borderRadius: BorderRadius.circular(BsheelRadii.full),
                        border: Border.all(color: statusFg.withAlpha(80)),
                      ),
                      child: Text(
                        status.toUpperCase(),
                        style: BsheelType.labelSm.copyWith(
                          color: statusFg,
                          fontSize: 10,
                        ),
                      ),
                    ),
                    if (submittedAt != null) ...[
                      const SizedBox(width: QuestSpacing.sm),
                      Text(
                        '${submittedAt.month.toString().padLeft(2, '0')}/${submittedAt.day.toString().padLeft(2, '0')} '
                        '${submittedAt.hour.toString().padLeft(2, '0')}:${submittedAt.minute.toString().padLeft(2, '0')}',
                        style: BsheelType.labelSm.copyWith(
                          color: BsheelColors.inkMuted,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          if (status == SubmissionStatus.pending)
            IconButton(
              icon: const Icon(
                Icons.rate_review,
                size: 18,
                color: BsheelColors.primary,
              ),
              tooltip: 'Review',
              onPressed: () => context.goNamed(
                AdminRouteNames.submissionReview,
                pathParameters: {'id': id},
              ),
            ),
        ],
      ),
    );
  }

  DataRow _buildRow(BuildContext context, Map<String, dynamic> sub, int index) {
    final username = sub['username'] ?? '-';
    final questTitle = sub['quest_title'] ?? '-';
    final caption = sub[SubmissionColumns.caption]?.toString() ?? '';
    final status = sub[SubmissionColumns.status]?.toString() ?? '';
    final mediaUrl = sub[SubmissionColumns.mediaUrl]?.toString() ?? '';
    final mediaType = sub[SubmissionColumns.mediaType]?.toString() ?? 'image';
    final submittedAt = DateTime.tryParse(
      sub[SubmissionColumns.submittedAt]?.toString() ?? '',
    );
    final id = sub[SubmissionColumns.id]?.toString() ?? '';

    final (Color statusBg, Color statusFg) = switch (status) {
      'approved' => (BsheelColors.success.withAlpha(30), BsheelColors.success),
      'rejected' => (BsheelColors.hot.withAlpha(30), BsheelColors.hot),
      _ => (BsheelColors.cool.withAlpha(30), BsheelColors.cool),
    };

    final rowColor = index.isEven ? BsheelColors.paper : BsheelColors.surface;

    return DataRow(
      color: WidgetStateProperty.all(rowColor),
      cells: [
        DataCell(
          ClipRRect(
            borderRadius: BorderRadius.circular(BsheelRadii.md),
            child: mediaType == 'video'
                ? Container(
                    width: 40,
                    height: 40,
                    color: BsheelColors.ink,
                    child: const Icon(
                      Icons.videocam,
                      size: 20,
                      color: BsheelColors.cool,
                    ),
                  )
                : Image.network(
                    mediaUrl,
                    width: 40,
                    height: 40,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      width: 40,
                      height: 40,
                      color: BsheelColors.ink,
                      child: const Icon(
                        Icons.broken_image,
                        size: 20,
                        color: BsheelColors.inkMuted,
                      ),
                    ),
                  ),
          ),
        ),
        DataCell(
          Text(
            '@$username',
            style: BsheelType.bodySm.copyWith(color: BsheelColors.ink),
          ),
        ),
        DataCell(
          Text(
            questTitle,
            overflow: TextOverflow.ellipsis,
            style: BsheelType.bodySm.copyWith(color: BsheelColors.ink),
          ),
        ),
        DataCell(
          SizedBox(
            width: 150,
            child: Text(
              caption.isEmpty ? '-' : caption,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: BsheelType.bodySm.copyWith(
                color: BsheelColors.inkMuted,
              ),
            ),
          ),
        ),
        DataCell(
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: QuestSpacing.sm,
              vertical: 2,
            ),
            decoration: BoxDecoration(
              color: statusBg,
              borderRadius: BorderRadius.circular(BsheelRadii.full),
              border: Border.all(color: statusFg.withAlpha(80)),
            ),
            child: Text(
              status.toUpperCase(),
              style: BsheelType.labelSm.copyWith(
                color: statusFg,
                fontSize: 10,
              ),
            ),
          ),
        ),
        DataCell(
          Text(
            submittedAt != null
                ? '${submittedAt.month.toString().padLeft(2, '0')}/${submittedAt.day.toString().padLeft(2, '0')} ${submittedAt.hour.toString().padLeft(2, '0')}:${submittedAt.minute.toString().padLeft(2, '0')}'
                : '-',
            style: BsheelType.labelSm.copyWith(
              color: BsheelColors.inkMuted,
            ),
          ),
        ),
        DataCell(
          status == SubmissionStatus.pending
              ? IconButton(
                  icon: const Icon(
                    Icons.rate_review,
                    size: 18,
                    color: BsheelColors.primary,
                  ),
                  tooltip: 'Review',
                  onPressed: () => context.goNamed(
                    AdminRouteNames.submissionReview,
                    pathParameters: {'id': id},
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final String value;
  final String current;
  final Color? color;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.value,
    required this.current,
    this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isActive = value == current;
    final c = color ?? BsheelColors.primary;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          // 44px minimum click target (spec 1).
          constraints: const BoxConstraints(
            minHeight: BsheelLayout.minTarget,
          ),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: QuestSpacing.md),
          decoration: BoxDecoration(
            color: isActive ? c.withAlpha(30) : Colors.transparent,
            borderRadius: BorderRadius.circular(BsheelRadii.full),
            border: Border.all(
              color: isActive ? c : BsheelColors.line,
              width: BsheelBorders.thin,
            ),
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: BsheelType.labelSm.copyWith(
              // The active fill is a 12% tint, so the label reads on cream.
              color: isActive ? BsheelColors.onCream(c) : BsheelColors.inkSoft,
              fontWeight: isActive ? FontWeight.w500 : FontWeight.w400,
              fontSize: 10,
            ),
          ),
        ),
      ),
    );
  }
}
