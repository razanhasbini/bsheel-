import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_contracts/supabase_contracts.dart';

import '../../../../core/providers/supabase_provider.dart';
import '../../../../core/router/admin_route_names.dart';
import '../../../../core/theme/bsheel_design.dart';
import '../../../../shared/widgets/bsheel_widgets.dart';

final appealsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final client = ref.watch(supabaseClientProvider);
  final data = await client
      .from(Tables.submissions)
      .select(
        '*, profiles!submissions_user_id_fkey(${ProfileColumns.username}, ${ProfileColumns.displayName}, ${ProfileColumns.avatarUrl}), ${Tables.userQuests}(${Tables.quests}(${QuestColumns.title}, ${QuestColumns.category}))',
      )
      .eq(SubmissionColumns.status, SubmissionStatus.pending)
      .eq(SubmissionColumns.appealed, true)
      .order(SubmissionColumns.submittedAt, ascending: true);

  return List<Map<String, dynamic>>.from(data as List);
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
                        pathParameters: {'id': a[SubmissionColumns.id]},
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
    final profile = data[Tables.profiles] as Map<String, dynamic>?;
    final username = profile?[ProfileColumns.username] ?? 'unknown';
    final displayName = profile?[ProfileColumns.displayName] ?? username;
    final userQuest = data[Tables.userQuests] as Map<String, dynamic>?;
    final quest = userQuest?[Tables.quests] as Map<String, dynamic>?;
    final questTitle = quest?[QuestColumns.title] ?? 'Unknown Quest';
    final category = quest?[QuestColumns.category] ?? '';
    final appealNote = data[SubmissionColumns.appealNote]?.toString() ?? '';
    final submittedAt = data[SubmissionColumns.submittedAt]?.toString() ?? '';

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
