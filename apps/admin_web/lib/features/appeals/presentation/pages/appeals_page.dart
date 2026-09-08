import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/backend/app_backend.dart';
import '../../../../core/router/admin_route_names.dart';
import '../../../../core/theme/bsheel_design.dart';
import '../../../../shared/widgets/bsheel_widgets.dart';

/// Submissions awaiting a second review after the user appealed: pending
/// AND already appealed, oldest first so the longest wait is actioned next.
final appealsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  return AppBackend.repositories.moderation.listSubmissionsForAdmin(
    status: 'pending',
    appealed: true,
    order: 'asc',
  );
});

class AppealsPage extends ConsumerWidget {
  const AppealsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appealsAsync = ref.watch(appealsProvider);

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BsheelCard(
            padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const BsheelEyebrow('Moderation · Appeals'),
                const SizedBox(height: 14),
                BsheelDisplay(
                  'The {appeals} desk.',
                  baseStyle: BsheelType.displayXl.copyWith(fontSize: 44),
                ),
                const SizedBox(height: 12),
                Text(
                  'Submissions rejected then re-opened by the user. Review '
                  "with priority — they're already a touch frustrated.",
                  style: BsheelType.bodyMd.copyWith(
                    color: BsheelColors.inkSoft,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          appealsAsync.when(
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
            data: (appeals) {
              if (appeals.isEmpty) return const _EmptyState();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final a in appeals) ...[
                    _AppealCard(
                      data: a,
                      onReview: () => context.goNamed(
                        AdminRouteNames.submissionReview,
                        pathParameters: {'id': a['id'].toString()},
                      ),
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
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const BsheelCard(
      child: Column(
        children: [
          SizedBox(height: 24),
          SizedBox(height: 18),
          BsheelDisplay(
            'All {caught up.}',
            baseStyle: BsheelType.displayMd,
          ),
          SizedBox(height: 6),
          Text(
            'No appeals waiting on review.',
            style: BsheelType.bodySm,
          ),
          SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _AppealCard extends StatelessWidget {
  const _AppealCard({required this.data, required this.onReview});
  final Map<String, dynamic> data;
  final VoidCallback onReview;

  @override
  Widget build(BuildContext context) {
    final username = data['username'] ?? 'unknown';
    final displayName = data['display_name'] ?? username;
    final questTitle = data['quest_title'] ?? 'Unknown Quest';
    final category = data['quest_category'] ?? '';
    final appealNote = data['appeal_note']?.toString() ?? '';
    final submittedAt = data['submitted_at']?.toString() ?? '';

    return BsheelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const BsheelPill('APPEAL', tone: BsheelPillTone.coral),
              if (category.toString().isNotEmpty)
                BsheelPill(
                  category.toString(),
                  tone: BsheelPillTone.sky,
                  small: true,
                ),
              Text(bsheelTimeAgo(submittedAt), style: BsheelType.labelSm),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            questTitle,
            style: BsheelType.displaySm,
          ),
          const SizedBox(height: 6),
          Text('@$username · $displayName', style: BsheelType.bodySm),
          if (appealNote.isNotEmpty) ...[
            const SizedBox(height: 14),
            Container(
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
                  const BsheelEyebrow('Their note'),
                  const SizedBox(height: 6),
                  Text(
                    appealNote,
                    style: BsheelType.bodyMd.copyWith(
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 18),
          Align(
            alignment: Alignment.centerRight,
            child: BsheelButton(
              label: 'Review →',
              onPressed: onReview,
            ),
          ),
        ],
      ),
    );
  }
}
