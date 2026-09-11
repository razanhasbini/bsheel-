import 'package:app_core/app_core.dart';
import 'package:app_models/app_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../core/providers/analytics_providers.dart';
import '../../core/providers/session_providers.dart';
import 'widgets/completion_chart.dart';
import 'widgets/stat_tile.dart';

/// The partner dashboard (#50).
///
/// One scrolling page rather than a tab shell, because the question a
/// business opens this to answer — "is Bsheel bringing people here" — is
/// answered by reading down: what happened, when, at which quest, at which
/// place, who came, and what they posted.
///
/// Every section loads and fails independently. A page-level error state
/// would let one endpoint blank the other five.
class DashboardPage extends ConsumerStatefulWidget {
  const DashboardPage({super.key, this.requestedBusinessId});

  /// From `?business=<id>`, appended by the mobile app's card. Validated
  /// against membership by [activeBusinessProvider] — never trusted.
  final String? requestedBusinessId;

  @override
  ConsumerState<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends ConsumerState<DashboardPage> {
  @override
  void initState() {
    super.initState();
    if (widget.requestedBusinessId != null) {
      // After the frame: setting provider state during initState throws.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(selectedBusinessIdProvider.notifier).state =
            widget.requestedBusinessId;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final businesses = ref.watch(myBusinessesProvider);
    final business = ref.watch(activeBusinessProvider);

    return Scaffold(
      backgroundColor: QuestColors.bg(context),
      body: SafeArea(
        child: businesses.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          // The router leaves a failed membership read to this page, because
          // "could not ask" is recoverable and "not a member" is not.
          error: (error, _) => Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: ArcadeCard(
                  child: SectionError(
                    message: 'Could not load your business account.',
                    onRetry: () => ref.invalidate(myBusinessesProvider),
                  ),
                ),
              ),
            ),
          ),
          data: (rows) => business == null
              ? const SizedBox.shrink()
              : _Dashboard(business: business, all: rows),
        ),
      ),
    );
  }
}

class _Dashboard extends ConsumerWidget {
  const _Dashboard({required this.business, required this.all});

  final BusinessSummary business;
  final List<BusinessSummary> all;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1100),
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            _Header(business: business, all: all),
            const SizedBox(height: 24),

            // A suspended account reads nothing, and the API refuses every
            // analytics route. Saying so here beats six failed sections.
            if (business.isSuspended)
              ArcadeCard(
                child: Text(
                  'This account is suspended, so its analytics are closed. '
                  'Your claimed places are kept.',
                  style: QuestTypography.osBodyMedium,
                ),
              )
            else if (!business.analyticsSubscribed)
              ArcadeCard(
                child: Text(
                  'Analytics is not part of this account yet. Talk to Bsheel '
                  'to switch it on.',
                  style: QuestTypography.osBodyMedium,
                ),
              )
            else ...[
              _SummarySection(businessId: business.id),
              const SizedBox(height: 28),
              _DailySection(businessId: business.id),
              const SizedBox(height: 28),
              _QuestSection(businessId: business.id),
              const SizedBox(height: 28),
              _PlaceSection(businessId: business.id),
              const SizedBox(height: 28),
              _OriginsSection(businessId: business.id),
              const SizedBox(height: 28),
              _ProofSection(businessId: business.id),
              const SizedBox(height: 48),
            ],
          ],
        ),
      ),
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header({required this.business, required this.all});

  final BusinessSummary business;
  final List<BusinessSummary> all;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('BSHEEL FOR BUSINESS',
                  style: QuestTypography.osLabelSmall
                      .copyWith(color: QuestColors.textDim(context))),
              const SizedBox(height: 4),
              Text(business.name, style: QuestTypography.osHeadlineMedium),
              const SizedBox(height: 4),
              Text(
                business.isOwner ? 'Owner' : 'Manager',
                style: QuestTypography.osBodySmall
                    .copyWith(color: QuestColors.textDim(context)),
              ),
            ],
          ),
        ),
        // Only shown to someone who belongs to more than one; a switcher
        // with a single entry is furniture.
        if (all.length > 1)
          DropdownButton<String>(
            value: business.id,
            underline: const SizedBox.shrink(),
            items: [
              for (final option in all)
                DropdownMenuItem(value: option.id, child: Text(option.name)),
            ],
            onChanged: (id) =>
                ref.read(selectedBusinessIdProvider.notifier).state = id,
          ),
        const SizedBox(width: 12),
        ArcadeButton(
          label: 'SIGN OUT',
          variant: ArcadeButtonVariant.ghost,
          size: ArcadeButtonSize.small,
          expand: false,
          onTap: () async {
            await ref.read(authRepositoryProvider).signOut();
            ref.read(sessionProvider.notifier).state = null;
          },
        ),
      ],
    );
  }
}

class _SummarySection extends ConsumerWidget {
  const _SummarySection({required this.businessId});

  final String businessId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(analyticsSummaryProvider(businessId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeading(
          title: 'Impact',
          subtitle: 'Approved proof only. Pending and rejected submissions '
              'are counted separately and never as completions.',
        ),
        summary.when(
          loading: () => const LinearProgressIndicator(),
          error: (_, __) => SectionError(
            onRetry: () => ref.invalidate(analyticsSummaryProvider(businessId)),
          ),
          data: (data) => !data.hasActivity
              ? const EmptyNote(
                  text: 'Nothing has happened at your places yet. This fills '
                      'in as people complete quests there.',
                )
              : Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    SizedBox(
                      width: 200,
                      child: StatTile(
                        label: 'Completed quests',
                        value: '${data.completions}',
                      ),
                    ),
                    SizedBox(
                      width: 200,
                      child: StatTile(
                        label: 'Visitors',
                        value: '${data.visitors}',
                        note: 'People, not completions',
                      ),
                    ),
                    SizedBox(
                      width: 200,
                      child: StatTile(
                        label: 'Awaiting review',
                        value: '${data.awaitingReview}',
                        note: data.awaitingReview > 0
                            ? 'Not yet counted as completed'
                            : null,
                      ),
                    ),
                    SizedBox(
                      width: 200,
                      child: StatTile(
                        label: 'Community posts',
                        value: '${data.publicProof}',
                        note: 'Published to the feed',
                      ),
                    ),
                    SizedBox(
                      width: 200,
                      child: StatTile(
                        label: 'Saved your places',
                        value: '${data.saves}',
                        note: 'Interest, not a visit',
                      ),
                    ),
                    SizedBox(
                      width: 200,
                      child: StatTile(
                        label: 'XP awarded',
                        value: '${data.xpAwarded}',
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _DailySection extends ConsumerWidget {
  const _DailySection({required this.businessId});

  final String businessId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final daily = ref.watch(dailyProvider(businessId));
    final window = ref.watch(dailyWindowProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: SectionHeading(
                title: 'Completions over time',
                subtitle: 'Every day in the window, including the quiet ones.',
              ),
            ),
            // Plain buttons rather than a segmented control: ArcadeSegments
            // is a progress meter, not a picker.
            for (final days in const [7, 30, 90]) ...[
              ArcadeButton(
                label: '${days}D',
                variant: days == window
                    ? ArcadeButtonVariant.primary
                    : ArcadeButtonVariant.ghost,
                size: ArcadeButtonSize.small,
                expand: false,
                onTap: () =>
                    ref.read(dailyWindowProvider.notifier).state = days,
              ),
              const SizedBox(width: 6),
            ],
          ],
        ),
        ArcadeCard(
          child: daily.when(
            loading: () => const SizedBox(
                height: 90, child: Center(child: LinearProgressIndicator())),
            error: (_, __) => SectionError(
              onRetry: () => ref.invalidate(dailyProvider(businessId)),
            ),
            data: (points) => points.isEmpty
                ? const EmptyNote(text: 'No days to show.')
                : CompletionChart(points: points),
          ),
        ),
      ],
    );
  }
}

class _QuestSection extends ConsumerWidget {
  const _QuestSection({required this.businessId});

  final String businessId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final quests = ref.watch(questPerformanceProvider(businessId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeading(
          title: 'Which quests pull people in',
          subtitle: 'Started counts everyone who took the quest, including '
              'those who never submitted — that is what makes the rate mean '
              'something.',
        ),
        quests.when(
          loading: () => const LinearProgressIndicator(),
          error: (_, __) => SectionError(
            onRetry: () => ref.invalidate(questPerformanceProvider(businessId)),
          ),
          data: (rows) => rows.isEmpty
              ? const EmptyNote(
                  text: 'No quests are offered at your places yet.')
              : ArcadeCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      for (final (index, row) in rows.indexed)
                        _QuestRow(row: row, isFirst: index == 0),
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}

class _QuestRow extends StatelessWidget {
  const _QuestRow({required this.row, required this.isFirst});

  final BusinessQuestPerformance row;
  final bool isFirst;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        border: isFirst
            ? null
            : Border(top: BorderSide(color: QuestColors.borderC(context))),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(row.title,
                    style: QuestTypography.osBodyMedium,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
                Text(row.placeName,
                    style: QuestTypography.osBodySmall
                        .copyWith(color: QuestColors.textDim(context))),
              ],
            ),
          ),
          _Figure(label: 'started', value: '${row.starts}'),
          _Figure(label: 'completed', value: '${row.completions}'),
          _Figure(
            label: 'rate',
            // Null, not 0%: nobody has started, so there is no rate — and
            // 0% would sort this quest last as if it had been tried and
            // failed.
            value: row.completionRate == null
                ? '—'
                : '${(row.completionRate! * 100).round()}%',
          ),
        ],
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({required this.label, required this.value});

  final String label, value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(value, style: QuestTypography.osBodyMedium),
          Text(label,
              style: QuestTypography.osLabelSmall
                  .copyWith(color: QuestColors.textDim(context))),
        ],
      ),
    );
  }
}

class _PlaceSection extends ConsumerWidget {
  const _PlaceSection({required this.businessId});

  final String businessId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final places = ref.watch(placePerformanceProvider(businessId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeading(title: 'Your places'),
        places.when(
          loading: () => const LinearProgressIndicator(),
          error: (_, __) => SectionError(
            onRetry: () => ref.invalidate(placePerformanceProvider(businessId)),
          ),
          data: (rows) => rows.isEmpty
              ? const EmptyNote(
                  text: 'No places are claimed for this business yet. Bsheel '
                      'links them for you.',
                )
              : Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final row in rows)
                      SizedBox(
                        width: 260,
                        child: ArcadeCard(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(row.name,
                                  style: QuestTypography.osBodyMedium,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                              Text(
                                row.city.isEmpty
                                    ? row.countryCode
                                    : '${row.city} · ${row.countryCode}',
                                style: QuestTypography.osBodySmall.copyWith(
                                    color: QuestColors.textDim(context)),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                  '${row.completions} completed · '
                                  '${row.visitors} visitors',
                                  style: QuestTypography.osBodySmall),
                              Text('${row.quests} quests · ${row.saves} saves',
                                  style: QuestTypography.osBodySmall.copyWith(
                                      color: QuestColors.textDim(context))),
                              // An unpublished place reports nothing at all,
                              // which otherwise reads as a broken dashboard.
                              if (!row.isPublished) ...[
                                const SizedBox(height: 8),
                                Text(
                                    'Not published — it shows no activity '
                                    'until it is on the map',
                                    style: QuestTypography.osBodySmall
                                        .copyWith(color: QuestColors.osRed)),
                              ],
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _OriginsSection extends ConsumerWidget {
  const _OriginsSection({required this.businessId});

  final String businessId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final origins = ref.watch(visitorOriginsProvider(businessId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeading(
          title: 'Where visitors come from',
          subtitle: 'Only visitors who told us their country and agreed to '
              'its use. Countries with too few visitors to stay anonymous '
              'are counted but not named.',
        ),
        origins.when(
          loading: () => const LinearProgressIndicator(),
          error: (_, __) => SectionError(
            onRetry: () => ref.invalidate(visitorOriginsProvider(businessId)),
          ),
          data: (data) => ArcadeCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (data.visitors == 0)
                  const EmptyNote(text: 'No visitors yet.')
                else if (data.nothingDisclosed)
                  // The honest empty state. Saying "no data" would read as
                  // "nobody came", which is the opposite of true.
                  EmptyNote(
                    text: 'None of your ${data.visitors} visitors have shared '
                        'a country yet, so there is nothing to break down.',
                  )
                else ...[
                  for (final bucket in data.countries) ...[
                    _OriginRow(bucket: bucket),
                    const SizedBox(height: 8),
                  ],
                  if (data.suppressedCountries > 0)
                    Text(
                      '${data.suppressedCountries} more '
                      '${data.suppressedCountries == 1 ? 'country' : 'countries'} '
                      '(${data.suppressedVisitors} visitors) had too few '
                      'people to name without identifying them.',
                      style: QuestTypography.osBodySmall
                          .copyWith(color: QuestColors.textDim(context)),
                    ),
                  const SizedBox(height: 10),
                  // The denominator, stated. A share of the disclosed
                  // population is not a share of the visitors, and reading
                  // one as the other is how a tenth of the traffic becomes
                  // "all of it".
                  Text(
                    'Based on ${data.disclosed} of ${data.visitors} visitors. '
                    '${data.undisclosed} have not shared a country.',
                    style: QuestTypography.osBodySmall
                        .copyWith(color: QuestColors.textDim(context)),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _OriginRow extends StatelessWidget {
  const _OriginRow({required this.bucket});

  final BusinessOriginBucket bucket;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 40,
          child: Text(bucket.countryCode, style: QuestTypography.osBodyMedium),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: bucket.shareOfDisclosed.clamp(0.0, 1.0),
              minHeight: 8,
              backgroundColor: QuestColors.borderC(context),
              valueColor:
                  const AlwaysStoppedAnimation<Color>(QuestColors.osAccent),
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 92,
          child: Text(
            '${bucket.visitors} · ${(bucket.shareOfDisclosed * 100).round()}%',
            textAlign: TextAlign.right,
            style: QuestTypography.osBodySmall,
          ),
        ),
      ],
    );
  }
}

class _ProofSection extends ConsumerWidget {
  const _ProofSection({required this.businessId});

  final String businessId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final proof = ref.watch(publicProofProvider(businessId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeading(
          title: 'What people posted',
          subtitle: 'Proof its author published to the Bsheel feed. Private '
              'proof is never shown here.',
        ),
        proof.when(
          loading: () => const LinearProgressIndicator(),
          error: (_, __) => SectionError(
            onRetry: () => ref.invalidate(publicProofProvider(businessId)),
          ),
          data: (page) => page.items.isEmpty
              ? const EmptyNote(
                  text: 'Nobody has published proof from your places yet.')
              : Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final item in page.items) _ProofTile(item: item),
                  ],
                ),
        ),
      ],
    );
  }
}

class _ProofTile extends StatelessWidget {
  const _ProofTile({required this.item});

  final BusinessPublicProof item;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 200,
      child: ArcadeCard(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: item.isVideo || item.mediaUrl.isEmpty
                    // No inline video player here: a wall of autoplaying
                    // clips is a worse way to review content than a marked
                    // placeholder, and the feed is where they are watched.
                    ? Container(
                        color: QuestColors.surfaceBg(context),
                        child: Center(
                          child: Icon(
                            item.isVideo
                                ? Icons.play_circle_outline
                                : Icons.image_not_supported_outlined,
                            color: QuestColors.textDim(context),
                          ),
                        ),
                      )
                    : Image.network(
                        item.mediaUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (context, _, __) => Container(
                          color: QuestColors.surfaceBg(context),
                          child: Center(
                            child: Icon(Icons.broken_image_outlined,
                                color: QuestColors.textDim(context)),
                          ),
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 8),
            Text('@${item.username}',
                style: QuestTypography.osBodySmall, maxLines: 1),
            Text(item.questTitle,
                style: QuestTypography.osBodySmall
                    .copyWith(color: QuestColors.textDim(context)),
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}
