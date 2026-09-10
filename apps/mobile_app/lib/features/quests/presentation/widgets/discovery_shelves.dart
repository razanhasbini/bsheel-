import 'package:app_core/app_core.dart';
import 'package:app_models/app_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/backend/app_backend.dart';
import '../../../../core/router/route_names.dart';

/// The discovery modules Home renders below the roll and Quest of the Day.
///
/// Everything about *which* shelves exist and what is in them is decided by
/// the server. That is not deference for its own sake: whether a hidden quest
/// has opened, whether an event window is still live, whether a campaign is
/// running are all facts a client can only guess at, and a wrong guess either
/// leaks content or renders a button that fails when pressed.
///
/// So this widget has exactly one job — draw what it was given, in the order
/// it was given — and deliberately no filtering of its own.
final homeModulesProvider = FutureProvider<List<DiscoveryModule>>((ref) async {
  return AppBackend.repositories.discovery.homeModules();
});

class DiscoveryShelves extends ConsumerWidget {
  const DiscoveryShelves({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final modules = ref.watch(homeModulesProvider);
    return modules.when(
      // Home already has plenty above this point, so discovery failing or
      // still loading should cost nothing visible rather than push a spinner
      // or an error card into a screen that is otherwise fine.
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (list) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [for (final module in list) _Shelf(module: module)],
      ),
    );
  }
}

class _Shelf extends StatelessWidget {
  const _Shelf({required this.module});

  final DiscoveryModule module;

  @override
  Widget build(BuildContext context) {
    final isJourney = module.journeys.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.only(top: QuestSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: QuestSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  module.title,
                  style: QuestTypography.osLabelLarge.copyWith(
                    color: QuestColors.text(context),
                  ),
                ),
                if (module.subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    module.subtitle!,
                    style: QuestTypography.osBodySmall.copyWith(
                      fontSize: 12,
                      color: QuestColors.textDim(context),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: QuestSpacing.sm),
          SizedBox(
            height: isJourney ? 118 : 186,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: QuestSpacing.lg),
              itemCount:
                  isJourney ? module.journeys.length : module.items.length,
              separatorBuilder: (_, __) =>
                  const SizedBox(width: QuestSpacing.sm),
              itemBuilder: (context, index) => isJourney
                  ? _JourneyCard(journey: module.journeys[index])
                  : _QuestCard(quest: module.items[index]),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuestCard extends StatelessWidget {
  const _QuestCard({required this.quest});

  final DiscoveryQuestCard quest;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.pushNamed(
        RouteNames.questDetails,
        pathParameters: {'id': quest.id},
      ),
      child: Container(
        width: 248,
        padding: const EdgeInsets.all(QuestSpacing.md),
        decoration: BoxDecoration(
          color: QuestColors.cardBg(context),
          borderRadius: BorderRadius.circular(QuestSpacing.radiusCard),
          border: Border.all(color: QuestColors.osTextPrimary, width: 2),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Mechanics live here, as small labels, rather than as sections
            // on Home. A player never has to learn the taxonomy to use the
            // app — they just see that this one is hidden, or ends soon.
            if (quest.badges.isNotEmpty)
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [
                  for (final badge in quest.badges.take(3))
                    _Badge(label: badge),
                ],
              ),
            const SizedBox(height: QuestSpacing.sm),
            Text(
              quest.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: QuestTypography.osLabelLarge.copyWith(
                fontSize: 15,
                color: QuestColors.text(context),
              ),
            ),
            const SizedBox(height: 4),
            Expanded(
              child: Text(
                quest.description,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: QuestTypography.osBodySmall.copyWith(
                  fontSize: 12,
                  height: 1.4,
                  color: QuestColors.textDim(context),
                ),
              ),
            ),
            const SizedBox(height: QuestSpacing.sm),
            Row(
              children: [
                Text(
                  '${quest.xpReward} XP',
                  style: QuestTypography.osLabelSmall.copyWith(
                    fontSize: 11,
                    color: QuestColors.osPrimary,
                  ),
                ),
                const Spacer(),
                if (quest.destination != null)
                  Flexible(
                    child: Text(
                      quest.destination!.city.isEmpty
                          ? quest.destination!.placeName
                          : quest.destination!.city,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: QuestTypography.osBodySmall.copyWith(
                        fontSize: 11,
                        color: QuestColors.textDim(context),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _JourneyCard extends StatelessWidget {
  const _JourneyCard({required this.journey});

  final JourneyProgress journey;

  @override
  Widget build(BuildContext context) {
    final fraction = journey.totalQuests == 0
        ? 0.0
        : journey.completedQuests / journey.totalQuests;
    return Container(
      width: 248,
      padding: const EdgeInsets.all(QuestSpacing.md),
      decoration: BoxDecoration(
        color: QuestColors.cardBg(context),
        borderRadius: BorderRadius.circular(QuestSpacing.radiusCard),
        border: Border.all(color: QuestColors.osTextPrimary, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            journey.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: QuestTypography.osLabelLarge.copyWith(
              fontSize: 15,
              color: QuestColors.text(context),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${journey.completedQuests} / ${journey.totalQuests}',
            style: QuestTypography.osBodySmall.copyWith(
              fontSize: 12,
              color: QuestColors.textDim(context),
            ),
          ),
          const Spacer(),
          ClipRRect(
            borderRadius: BorderRadius.circular(QuestSpacing.radiusSegment),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 10,
              backgroundColor: QuestColors.osSurface,
              valueColor: const AlwaysStoppedAnimation(QuestColors.osSuccess),
            ),
          ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: QuestColors.osSurface,
        borderRadius: BorderRadius.circular(QuestSpacing.radiusBadge),
        border: Border.all(color: QuestColors.osTextPrimary, width: 1.5),
      ),
      child: Text(
        label,
        style: QuestTypography.osLabelSmall.copyWith(
          fontSize: 9,
          letterSpacing: 0.6,
          color: QuestColors.osTextPrimary,
        ),
      ),
    );
  }
}
