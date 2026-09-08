import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/backend/app_backend.dart';
import '../../../../core/theme/bsheel_design.dart';
import '../../../../shared/widgets/bsheel_widgets.dart';

// ── Provider ──────────────────────────────────────────────────────────────────

final webSignupsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  return AppBackend.repositories.admin.waitlist(limit: 500);
});

// ── Page ──────────────────────────────────────────────────────────────────────

class WebSignupsPage extends ConsumerWidget {
  const WebSignupsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(webSignupsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BsheelCard(
          padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const BsheelEyebrow('Web · Signups'),
              const SizedBox(height: 14),
              BsheelDisplay(
                'The {waitlist.}',
                baseStyle: BsheelType.hero(context),
              ),
              const SizedBox(height: 12),
              Text(
                'Email addresses captured from the marketing site waitlist.',
                style: BsheelType.bodyMd.copyWith(color: BsheelColors.inkSoft),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Expanded(
          child: async.when(
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
            data: (rows) {
              if (rows.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.inbox_outlined,
                        size: 64,
                        color: BsheelColors.primary.withAlpha(100),
                      ),
                      const SizedBox(height: QuestSpacing.md),
                      Text(
                        'NO SIGNUPS YET',
                        style: BsheelType.displaySm
                            .copyWith(color: BsheelColors.inkMuted),
                      ),
                    ],
                  ),
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: QuestSpacing.md,
                      vertical: QuestSpacing.sm,
                    ),
                    decoration: BoxDecoration(
                      color: BsheelColors.ink,
                      borderRadius: BorderRadius.circular(BsheelRadii.sm),
                    ),
                    child: Text(
                      '${rows.length} TOTAL',
                      style: BsheelType.labelSm.copyWith(
                        color: BsheelColors.paper,
                        letterSpacing: 1.4,
                      ),
                    ),
                  ),
                  const SizedBox(height: QuestSpacing.md),
                  Expanded(
                    child: ListView.separated(
                      itemCount: rows.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: QuestSpacing.xs),
                      itemBuilder: (context, index) {
                        final r = rows[index];
                        return _SignupRow(data: r);
                      },
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _SignupRow extends StatelessWidget {
  final Map<String, dynamic> data;

  const _SignupRow({required this.data});

  @override
  Widget build(BuildContext context) {
    final email = (data['email'] ?? '') as String;
    final source = (data['source'] ?? '') as String;
    final createdAt = DateTime.tryParse((data['created_at'] ?? '') as String);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: QuestSpacing.md,
        vertical: QuestSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: BsheelColors.paper,
        border: Border.all(color: BsheelColors.ink, width: 1),
        borderRadius: BorderRadius.circular(BsheelRadii.sm),
      ),
      child: Row(
        children: [
          const Icon(Icons.email_outlined, color: BsheelColors.ink, size: 20),
          const SizedBox(width: QuestSpacing.sm),
          Expanded(
            child: Text(
              email,
              style: BsheelType.bodyMd.copyWith(
                color: BsheelColors.ink,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (source.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: BsheelColors.bg,
                border: Border.all(color: BsheelColors.ink),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                source.toUpperCase(),
                style: BsheelType.labelSm.copyWith(
                  color: BsheelColors.inkMuted,
                  letterSpacing: 1.2,
                ),
              ),
            ),
            const SizedBox(width: QuestSpacing.sm),
          ],
          if (createdAt != null)
            Text(
              _formatDate(createdAt),
              style: BsheelType.labelSm.copyWith(
                color: BsheelColors.inkMuted,
              ),
            ),
        ],
      ),
    );
  }

  static String _formatDate(DateTime dt) {
    final local = dt.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} '
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }
}
