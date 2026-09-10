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

/// Which shelves can reach past what they are showing, and from which pool.
///
/// Not every shelf should: CONTINUE_JOURNEY is the player's own progress and
/// HIDDEN_DISCOVERED is what they personally found, so "give me another" is
/// meaningless for both.
const _generateChannels = <String, String>{
  'WORTH_THE_TRIP': 'WORTH_THE_TRIP',
  'TRENDING': 'TRENDING',
  'LIMITED_TIME': 'LIMITED_TIME',
  'NEAR_YOU': 'COUNTRY',
  'EXPLORE_COUNTRY': 'COUNTRY',
};

class _Shelf extends ConsumerStatefulWidget {
  const _Shelf({required this.module});

  final DiscoveryModule module;

  @override
  ConsumerState<_Shelf> createState() => _ShelfState();
}

class _ShelfState extends ConsumerState<_Shelf> {
  /// Cards GENERATE has pulled in, appended after the curated ones.
  final List<DiscoveryQuestCard> _extra = [];
  bool _generating = false;
  bool _exhausted = false;

  /// Set once the player picks a country, which replaces the shelf entirely.
  String? _pickedCode;
  String? _pickedName;
  List<DiscoveryQuestCard>? _picked;

  List<DiscoveryQuestCard> get _items =>
      [...(_picked ?? widget.module.items), ..._extra];

  String get _title => _pickedName == null
      ? widget.module.title
      : 'EXPLORE ${_pickedName!.toUpperCase()}';

  Future<void> _generate() async {
    setState(() => _generating = true);
    try {
      final card = await AppBackend.repositories.discovery.generate(
        channel: _generateChannels[widget.module.type]!,
        countryCode: _pickedCode,
        // Everything already on screen, so this reaches further instead of
        // reshuffling — on a small catalogue that difference is the feature.
        exclude: _items.map((i) => i.id).toList(),
      );
      if (!mounted) return;
      setState(() {
        if (card == null) {
          _exhausted = true;
        } else {
          _extra.add(card);
        }
      });
    } catch (_) {
      if (mounted) setState(() => _exhausted = true);
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<void> _pickCountry() async {
    final countries = await AppBackend.repositories.discovery.countries();
    if (!mounted) return;
    final chosen = await showModalBottomSheet<DiscoveryCountry>(
      context: context,
      backgroundColor: QuestColors.cardBg(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
            top: Radius.circular(QuestSpacing.radiusSheet)),
      ),
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.all(QuestSpacing.lg),
              child: Text(
                'EXPLORE SOMEWHERE ELSE',
                style: QuestTypography.osLabelLarge.copyWith(
                  color: QuestColors.text(context),
                ),
              ),
            ),
            for (final c in countries)
              ListTile(
                title: Text(c.name,
                    style: TextStyle(color: QuestColors.text(context))),
                trailing: Text('${c.questCount}',
                    style: TextStyle(color: QuestColors.textDim(context))),
                onTap: () => Navigator.of(context).pop(c),
              ),
          ],
        ),
      ),
    );
    if (chosen == null || !mounted) return;

    final quests = await AppBackend.repositories.discovery
        .byCountry(chosen.code, limit: 5);
    if (!mounted) return;
    setState(() {
      _pickedCode = chosen.code;
      _pickedName = chosen.name;
      _picked = quests;
      // A new country is a new pool, so anything generated for the old one
      // no longer belongs on this shelf.
      _extra.clear();
      _exhausted = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final module = widget.module;
    final isJourney = module.journeys.isNotEmpty;
    final canGenerate = _generateChannels.containsKey(module.type);
    final canPickCountry =
        module.type == 'EXPLORE_COUNTRY' || module.type == 'NEAR_YOU';

    return Padding(
      padding: const EdgeInsets.only(top: QuestSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: QuestSpacing.lg),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Tapping the title is the country picker on an EXPLORE
                      // shelf: the heading already names a place, so it is
                      // the obvious thing to press to change it.
                      GestureDetector(
                        onTap: canPickCountry ? _pickCountry : null,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                _title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: QuestTypography.osLabelLarge.copyWith(
                                  color: QuestColors.text(context),
                                ),
                              ),
                            ),
                            if (canPickCountry)
                              const Icon(Icons.expand_more_rounded,
                                  size: 18, color: QuestColors.osPrimary),
                          ],
                        ),
                      ),
                      if (module.subtitle != null && _pickedName == null) ...[
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
                if (canGenerate && !isJourney)
                  _GenerateButton(
                    busy: _generating,
                    exhausted: _exhausted,
                    onTap: _generating || _exhausted ? null : _generate,
                  ),
              ],
            ),
          ),
          const SizedBox(height: QuestSpacing.sm),
          SizedBox(
            height: isJourney ? 118 : 186,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: QuestSpacing.lg),
              itemCount: isJourney ? module.journeys.length : _items.length,
              separatorBuilder: (_, __) =>
                  const SizedBox(width: QuestSpacing.sm),
              itemBuilder: (context, index) => isJourney
                  ? _JourneyCard(journey: module.journeys[index])
                  : _QuestCard(quest: _items[index]),
            ),
          ),
        ],
      ),
    );
  }
}

/// Reaches into the wider pool behind a shelf.
class _GenerateButton extends StatelessWidget {
  const _GenerateButton({
    required this.busy,
    required this.exhausted,
    required this.onTap,
  });

  final bool busy;
  final bool exhausted;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: exhausted ? QuestColors.osSurface : QuestColors.osPrimary,
          borderRadius: BorderRadius.circular(QuestSpacing.radiusBadge),
          border: Border.all(color: QuestColors.osTextPrimary, width: 2),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (busy)
              SizedBox(
                width: 11,
                height: 11,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: QuestColors.onAccent(QuestColors.osPrimary),
                ),
              )
            else
              Icon(
                exhausted ? Icons.done_rounded : Icons.casino_rounded,
                size: 13,
                color: exhausted
                    ? QuestColors.osTextMuted
                    : QuestColors.onAccent(QuestColors.osPrimary),
              ),
            const SizedBox(width: 5),
            Text(
              // "That is all of them" is a better answer than a button that
              // keeps returning the same card.
              exhausted ? "THAT'S ALL" : 'GENERATE',
              style: QuestTypography.osLabelSmall.copyWith(
                fontSize: 10,
                letterSpacing: 0.8,
                color: exhausted
                    ? QuestColors.osTextMuted
                    : QuestColors.onAccent(QuestColors.osPrimary),
              ),
            ),
          ],
        ),
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
