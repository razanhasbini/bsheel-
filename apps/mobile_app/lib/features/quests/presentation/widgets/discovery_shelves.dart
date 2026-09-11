import 'package:app_core/app_core.dart';
import 'package:app_models/app_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_ui/shared_ui.dart';

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
  // Its own pool rather than the general one: what this shelf offers is the
  // OPENING step of a chain, and handing back step 3 of something unstarted
  // would be an invitation the eligibility gate refuses.
  'MULTI_STAGE': 'MULTI_STAGE',
};

class _Shelf extends ConsumerStatefulWidget {
  const _Shelf({required this.module});

  final DiscoveryModule module;

  @override
  ConsumerState<_Shelf> createState() => _ShelfState();
}

class _ShelfState extends ConsumerState<_Shelf> {
  /// Cards GENERATE has pulled in, kept on the shelf after being shown.
  final List<DiscoveryQuestCard> _extra = [];

  /// Everything generated this session, including cards dismissed without
  /// being kept — otherwise the next press can re-offer one already seen.
  final Set<String> _seen = {};
  bool _generating = false;

  /// Set once the player picks a country, which replaces the shelf entirely.
  String? _pickedCode;
  String? _pickedName;
  List<DiscoveryQuestCard>? _picked;

  List<DiscoveryQuestCard> get _items =>
      [...(_picked ?? widget.module.items), ..._extra];

  String get _title => _pickedName == null
      ? widget.module.title
      : 'EXPLORE ${_pickedName!.toUpperCase()}';

  /// Offers a few generated quests, rather than quietly appending a card.
  ///
  /// Pressing GENERATE is an ask — "show me something else" — so the answer
  /// arrives as one, and as a CHOICE. One card is a verdict; three is the
  /// same shape as the roll, which is the mechanic players already know.
  /// Sliding a sixth card onto the end of a horizontal list put it
  /// off-screen, which read as the button having done nothing.
  Future<void> _generate() async {
    setState(() => _generating = true);
    try {
      final result = await AppBackend.repositories.discovery.generate(
        channel: _generateChannels[widget.module.type]!,
        countryCode: _pickedCode,
        // Everything offered so far, so each press reaches further rather
        // than reshuffling the same handful.
        exclude: [..._items.map((i) => i.id), ..._seen],
      );
      if (!mounted) return;
      setState(() => _generating = false);
      if (result.isEmpty) {
        await _showExhausted();
        return;
      }
      _seen.addAll(result.quests.map((q) => q.id));
      await _present(result);
    } catch (_) {
      if (mounted) setState(() => _generating = false);
    }
  }

  /// Shows the choice, and what the player wants next: take one, or reroll.
  Future<void> _present(GeneratedQuests result) async {
    if (!mounted) return;
    final action = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _GeneratedSheet(result: result, shelfTitle: _title),
    );
    if (!mounted) return;
    if (action == 'again') {
      await _generate();
    } else if (action != null && action.startsWith('open:')) {
      final id = action.substring(5);
      // Kept on the shelf too, so it can be found again after looking at
      // the detail page.
      setState(() => _extra.addAll(result.quests.where((q) => q.id == id)));
      if (mounted) {
        context.pushNamed(RouteNames.questDetails, pathParameters: {'id': id});
      }
    } else {
      setState(() => _extra.addAll(result.quests));
    }
  }

  Future<void> _showExhausted() async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: QuestColors.cardBg(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
            top: Radius.circular(QuestSpacing.radiusSheet)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(
            QuestSpacing.lg, QuestSpacing.lg, QuestSpacing.lg, QuestSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "THAT'S EVERYTHING HERE",
              style: QuestTypography.osLabelLarge
                  .copyWith(color: QuestColors.text(context)),
            ),
            const SizedBox(height: 8),
            Text(
              // Names the shelf that ran out and offers a next step, because
              // "no more" on its own is just a wall.
              'You have seen every quest in ${_title.toLowerCase()} for now. '
              'Try another country, or roll for something you can do today.',
              style: QuestTypography.osBodySmall.copyWith(
                fontSize: 13,
                height: 1.5,
                color: QuestColors.textDim(context),
              ),
            ),
          ],
        ),
      ),
    );
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
      _seen.clear();
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
                    onTap: _generating ? null : _generate,
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
  const _GenerateButton({required this.busy, required this.onTap});

  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: QuestColors.osPrimary,
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
              Icon(Icons.casino_rounded,
                  size: 13, color: QuestColors.onAccent(QuestColors.osPrimary)),
            const SizedBox(width: 5),
            Text(
              'GENERATE',
              style: QuestTypography.osLabelSmall.copyWith(
                fontSize: 10,
                letterSpacing: 0.8,
                color: QuestColors.onAccent(QuestColors.osPrimary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The generated quests, presented as a choice rather than filed away.
class _GeneratedSheet extends StatelessWidget {
  const _GeneratedSheet({required this.result, required this.shelfTitle});

  final GeneratedQuests result;
  final String shelfTitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(QuestSpacing.md),
      padding: const EdgeInsets.all(QuestSpacing.lg),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.82,
      ),
      decoration: BoxDecoration(
        color: QuestColors.cardBg(context),
        borderRadius: BorderRadius.circular(QuestSpacing.radiusSheet),
        border: Border.all(color: QuestColors.osTextPrimary, width: 2),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'FROM $shelfTitle',
            style: QuestTypography.osLabelSmall.copyWith(
              fontSize: 10,
              letterSpacing: 1,
              color: QuestColors.textDim(context),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'PICK ONE',
            style: QuestTypography.osDisplayLarge.copyWith(
              fontSize: 24,
              letterSpacing: -0.6,
              color: QuestColors.text(context),
            ),
          ),
          const SizedBox(height: 10),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: result.quests.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) => _Option(quest: result.quests[i]),
            ),
          ),
          const SizedBox(height: QuestSpacing.md),
          ArcadeButton(
            label: 'REROLL',
            variant: ArcadeButtonVariant.ghost,
            onTap: () => Navigator.of(context).pop('again'),
          ),
          const SizedBox(height: 6),
          Center(
            child: Text(
              // Honest about depth, so the button never has to be a dead end.
              '${result.remaining} more in this shelf',
              style: QuestTypography.osBodySmall.copyWith(
                fontSize: 11,
                color: QuestColors.textDim(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Option extends StatelessWidget {
  const _Option({required this.quest});

  final DiscoveryQuestCard quest;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).pop('open:${quest.id}'),
      child: Container(
        padding: const EdgeInsets.all(QuestSpacing.md),
        decoration: BoxDecoration(
          color: QuestColors.bg(context),
          borderRadius: BorderRadius.circular(QuestSpacing.radiusControl),
          border: Border.all(color: QuestColors.osTextPrimary, width: 2),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (quest.badges.isNotEmpty)
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [
                  for (final b in quest.badges.take(3)) _Badge(label: b)
                ],
              ),
            const SizedBox(height: 6),
            Text(
              quest.title,
              style: QuestTypography.osLabelLarge.copyWith(
                fontSize: 15,
                color: QuestColors.text(context),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              quest.description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: QuestTypography.osBodySmall.copyWith(
                fontSize: 12,
                height: 1.4,
                color: QuestColors.textDim(context),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Text('${quest.xpReward} XP',
                    style: QuestTypography.osLabelSmall
                        .copyWith(fontSize: 11, color: QuestColors.osPrimary)),
                const Spacer(),
                if (quest.destination != null)
                  Flexible(
                    child: Text(
                      quest.destination!.placeName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: QuestTypography.osBodySmall.copyWith(
                          fontSize: 11, color: QuestColors.textDim(context)),
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
