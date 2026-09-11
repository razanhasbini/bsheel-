import 'package:app_models/app_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/backend/app_backend.dart';
import '../../../../core/router/admin_route_names.dart';
import '../../../../core/theme/bsheel_design.dart';
import '../../../../shared/layout/admin_shell.dart';
import '../../../../shared/widgets/bsheel_widgets.dart';

/// `/moderation/unclear` — proof the AI agent declined to judge (#47).
///
/// Deliberately a separate queue rather than a filter on `/moderation`.
/// Every row here is one the agent explicitly gave up on, so the useful
/// thing to show is *why it gave up* and what its automated checks found —
/// context the ordinary queue has no column for. A moderator opening this
/// list is answering a different question: not "is this proof good" but
/// "the machine could not tell, can I".
///
/// Rows route to the shared review surface, so the decision itself is made
/// in exactly one place on the console. Approving or rejecting there clears
/// the escalation server-side, in the same transaction as the decision, so
/// nothing has to be dismissed by hand here.
final unclearQueueProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  return AppBackend.repositories.moderation.unclearQueue(limit: 100);
});

class UnclearQueuePage extends ConsumerWidget {
  const UnclearQueuePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queue = ref.watch(unclearQueueProvider);

    return AdminPage(
      title: 'Unclear',
      meta: switch (queue) {
        AsyncData(:final value) => value.isEmpty
            ? 'Nothing waiting'
            : '${value.length} waiting on a human',
        _ => null,
      },
      actions: [
        BsheelButton.ghost(
          label: 'REFRESH',
          onPressed: () => ref.invalidate(unclearQueueProvider),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _Explainer(),
          const SizedBox(height: 20),
          queue.when(
            loading: () => const BsheelLoadingList(rows: 3, rowHeight: 140),
            error: (error, _) => BsheelErrorState(
              title: 'Could not load the queue',
              message: '$error',
              onRetry: () => ref.invalidate(unclearQueueProvider),
            ),
            data: (rows) => rows.isEmpty
                ? const BsheelEmptyState(
                    title: 'NOTHING ESCALATED',
                    message:
                        'Every submission the agent looked at, it could decide on.',
                  )
                : Column(
                    children: [
                      for (final row in rows) ...[
                        _UnclearRow(row: row),
                        const SizedBox(height: 12),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

/// Why this queue exists, said once at the top.
///
/// Without it a moderator could reasonably read an escalation as an
/// accusation. It is the opposite: the agent declining is the safe outcome,
/// and these are the cases where its judgement was correctly withheld.
class _Explainer extends StatelessWidget {
  const _Explainer();

  @override
  Widget build(BuildContext context) {
    return BsheelCard.muted(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          'The verification agent could not decide on these. That is the safe '
          'outcome, not a red flag — a submission lands here when the proof is '
          'ambiguous, when part of it could not be examined, or when the quest '
          'is one no photograph can settle. Nothing has been held against the '
          'player. Approving or rejecting from a row clears it from this list.',
          style: BsheelType.bodyMd.copyWith(color: BsheelColors.inkSoft),
        ),
      ),
    );
  }
}

class _UnclearRow extends StatelessWidget {
  final Map<String, dynamic> row;

  const _UnclearRow({required this.row});

  /// The findings the agent recorded, worst first.
  ///
  /// Read out of the stored report rather than recomputed, so what a
  /// moderator sees is exactly what the policy weighed.
  List<({String detail, String weight})> get _findings {
    final forensics = row['forensics'];
    if (forensics is! Map) return const [];
    final findings = forensics['findings'];
    if (findings is! List) return const [];
    const order = {'decisive': 0, 'strong': 1, 'weak': 2, 'info': 3};
    final parsed = findings
        .whereType<Map>()
        .map((f) => (
              detail: '${f['detail'] ?? ''}',
              weight: '${f['weight'] ?? 'info'}',
            ))
        .where((f) => f.detail.isNotEmpty && f.weight != 'info')
        .toList();
    parsed
        .sort((a, b) => (order[a.weight] ?? 3).compareTo(order[b.weight] ?? 3));
    return parsed;
  }

  BsheelPillTone _toneFor(String weight) => switch (weight) {
        'decisive' => BsheelPillTone.coral,
        'strong' => BsheelPillTone.gold,
        _ => BsheelPillTone.ghost,
      };

  @override
  Widget build(BuildContext context) {
    final submissionId = '${row['submission_id'] ?? ''}';
    final name = '${row['display_name'] ?? row['username'] ?? 'Someone'}';
    final questTitle = '${row['quest_title'] ?? 'Unknown quest'}';
    final reason = '${row['escalation_reason'] ?? ''}';
    final rationale = '${row['rationale'] ?? ''}';
    final category = '${row['quest_category'] ?? ''}';
    final appealed = row['appealed'] == true;
    final relevance = coerceNullableDouble(row['relevance']);
    final findings = _findings;

    return BsheelCard(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(questTitle, style: BsheelType.titleMd),
                if (category.isNotEmpty)
                  BsheelPill(category.toUpperCase(), small: true),
                // An appealed submission in this queue is the sharpest case
                // on the console: a human already rejected it once and the
                // agent still cannot tell.
                if (appealed)
                  const BsheelPill('APPEALED',
                      tone: BsheelPillTone.violet, small: true),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Text(
                    name,
                    style:
                        BsheelType.bodyMd.copyWith(color: BsheelColors.inkSoft),
                  ),
                ),
                // Relevance, and only relevance, because this queue is for
                // triage: the one number that tells a moderator whether to
                // open this row first is how much the media had to do with
                // the quest. The verdict is already "could not tell" for
                // everything here, so showing its confidence would order the
                // queue by how unsure the agent was rather than by how
                // suspicious the submission is.
                if (relevance != null)
                  BsheelPill(
                    'RELEVANCE ${(relevance * 100).round()}%',
                    tone: relevance < 0.35
                        ? BsheelPillTone.coral
                        : BsheelPillTone.ghost,
                    small: true,
                  )
                else
                  // Absent is not low. Two thirds of the catalogue cannot be
                  // judged from a photograph at all, and those rows are
                  // waiting on authenticity, not on content.
                  const BsheelPill.muted('NOT PHOTO-JUDGEABLE', small: true),
              ],
            ),
            if (reason.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text('WHY IT STOPPED', style: BsheelType.labelSm),
              const SizedBox(height: 4),
              Text(reason, style: BsheelType.bodyMd),
            ],
            if (rationale.isNotEmpty && rationale != reason) ...[
              const SizedBox(height: 10),
              const Text('WHAT IT SAW', style: BsheelType.labelSm),
              const SizedBox(height: 4),
              Text(
                rationale,
                style: BsheelType.bodyMd.copyWith(color: BsheelColors.inkSoft),
              ),
            ],
            if (findings.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text('AUTOMATED CHECKS', style: BsheelType.labelSm),
              const SizedBox(height: 6),
              for (final finding in findings)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      BsheelPill(
                        finding.weight.toUpperCase(),
                        tone: _toneFor(finding.weight),
                        small: true,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          finding.detail,
                          style: BsheelType.bodyMd
                              .copyWith(color: BsheelColors.inkSoft),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerRight,
              child: BsheelButton(
                label: 'REVIEW',
                onPressed: submissionId.isEmpty
                    ? null
                    : () => context.pushNamed(
                          AdminRouteNames.submissionReview,
                          pathParameters: {'id': submissionId},
                        ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
