import 'package:app_core/app_core.dart';
import 'package:app_models/app_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../core/providers/analytics_providers.dart';
import 'stat_tile.dart';

/// The funnel (#81 §8).
///
/// Drawn as two blocks, not one gradient, because the numbers are not the
/// same kind of thing. Exposure is what a phone told us it drew;
/// participation is what the server wrote while doing the work. A single
/// uniform funnel invites a business to read an impression as solidly as a
/// completion, and impressions are the one figure nobody can audit.
///
/// So the halves are visually separated, the attested half is labelled
/// where the numbers are rather than in a footnote, and when no telemetry
/// has been reported the exposure block says *that* instead of showing
/// zeroes.
class FunnelSection extends ConsumerWidget {
  const FunnelSection({super.key, required this.businessId});

  final String businessId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final funnel = ref.watch(funnelProvider(businessId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeading(
          title: 'From seen to completed',
          subtitle: 'The top half is reported by the app; the bottom half is '
              'what Bsheel recorded. They are not the same kind of number.',
        ),
        funnel.when(
          loading: () => const LinearProgressIndicator(),
          error: (_, __) => SectionError(
            onRetry: () => ref.invalidate(funnelProvider(businessId)),
          ),
          data: (data) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ExposureBlock(funnel: data),
              const SizedBox(height: 14),
              _ParticipationBlock(funnel: data),
            ],
          ),
        ),
      ],
    );
  }
}

class _ExposureBlock extends StatelessWidget {
  const _ExposureBlock({required this.funnel});

  final BusinessFunnel funnel;

  @override
  Widget build(BuildContext context) {
    final exposure = funnel.exposure;

    return ArcadeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('REACH AND INTEREST', style: QuestTypography.osLabelSmall),
              const SizedBox(width: 8),
              // On the numbers, not in a footnote: a caveat somewhere else
              // gets quoted without it.
              if (funnel.exposureIsClientReported)
                Text('reported by the app',
                    style: QuestTypography.osBodySmall
                        .copyWith(color: QuestColors.textDim(context))),
            ],
          ),
          const SizedBox(height: 12),
          if (exposure == null)
            // Not zeroes. "Nothing was reported" is a statement about
            // Bsheel; "nobody saw it" would be a claim about the business.
            const EmptyNote(
              text: 'The app has not reported any views for this period yet, '
                  'so there is nothing to show here. That is not the same as '
                  'nobody seeing your quests.',
            )
          else
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                SizedBox(
                  width: 190,
                  child: StatTile(
                    label: 'Times shown',
                    value: '${exposure.impressions}',
                    note: 'Screens, not people',
                  ),
                ),
                SizedBox(
                  width: 190,
                  child: StatTile(
                    label: 'People reached',
                    value: '${exposure.reach}',
                  ),
                ),
                SizedBox(
                  width: 190,
                  child: StatTile(
                    label: 'Opened',
                    value: '${exposure.detailViews}',
                    note: _rate('of times shown', funnel.impressionToView),
                  ),
                ),
                SizedBox(
                  width: 190,
                  child: StatTile(
                    label: 'BSHEEEL pressed',
                    value: '${exposure.bsheeels}',
                    note: _rate('of those opened', funnel.viewToBsheeel),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _ParticipationBlock extends StatelessWidget {
  const _ParticipationBlock({required this.funnel});

  final BusinessFunnel funnel;

  @override
  Widget build(BuildContext context) {
    final participation = funnel.participation;

    return ArcadeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('WHAT ACTUALLY HAPPENED',
                  style: QuestTypography.osLabelSmall),
              const SizedBox(width: 8),
              Text('recorded by Bsheel',
                  style: QuestTypography.osBodySmall
                      .copyWith(color: QuestColors.textDim(context))),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              SizedBox(
                width: 190,
                child: StatTile(
                  label: 'Quests started',
                  value: '${participation.activations}',
                  // Only meaningful when the stage above it was reported at
                  // all, and null rather than 0% when it was not.
                  note: _rate('of BSHEEELs', funnel.bsheeelToActivation),
                ),
              ),
              SizedBox(
                width: 190,
                child: StatTile(
                  label: 'Completed',
                  value: '${participation.completions}',
                  note:
                      _rate('of those started', funnel.activationToCompletion),
                ),
              ),
              SizedBox(
                width: 190,
                child: StatTile(
                  label: 'Visitors',
                  value: '${participation.visitors}',
                  note: 'People, not completions',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A conversion note, or nothing at all.
///
/// Null means the stage above was empty or unreported. Printing "0%" there
/// would read as a real conversion failure rather than an absent
/// denominator.
String? _rate(String suffix, double? value) =>
    value == null ? null : '${(value * 100).round()}% $suffix';
