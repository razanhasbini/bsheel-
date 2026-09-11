import 'package:app_core/app_core.dart';
import 'package:app_models/app_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/backend/backend_config.dart';
import '../../../../core/providers/business_provider.dart';

/// #14's "link to the dashboard on their account".
///
/// The whole of what being a business changes in the consumer app. Everything
/// else — quests, feed, leaderboard, streaks — is identical, which is what
/// the issue asked for ("the entire app stays the same except their
/// profile").
///
/// Renders nothing at all for the overwhelming majority of users, and
/// nothing when viewing somebody else's profile: a business account is not
/// public information here, and #81's public business profile is a separate
/// surface with its own rules.
class BusinessCard extends ConsumerWidget {
  const BusinessCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final businesses = ref.watch(myBusinessesProvider);
    // While loading or on failure this is simply absent. A business card is
    // an addition to someone's profile; it must never be able to replace it
    // with a spinner or an error.
    final rows = businesses.value ?? const <BusinessSummary>[];
    if (rows.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final business in rows) ...[
          _BusinessTile(business: business),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _BusinessTile extends StatelessWidget {
  const _BusinessTile({required this.business});

  final BusinessSummary business;

  Future<void> _openDashboard(BuildContext context) async {
    final base = BackendConfig.dashboardUri;
    if (base == null) return;
    // The dashboard resolves the business from the session, but naming it in
    // the URL means an owner of two lands on the right one.
    final target = base.replace(
      queryParameters: {...base.queryParameters, 'business': business.id},
    );
    final opened =
        await launchUrl(target, mode: LaunchMode.externalApplication);
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the dashboard')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasLink = BackendConfig.dashboardUri != null;

    return ArcadeCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Gold for the role, coral for a suspension: colour carries
              // the meaning, matching the status pills used elsewhere.
              ArcadeStatusPill(
                label: business.isOwner ? 'BUSINESS OWNER' : 'BUSINESS MANAGER',
                tint: QuestColors.osAccent,
                compact: true,
              ),
              const Spacer(),
              if (business.isSuspended)
                const ArcadeStatusPill(
                  label: 'SUSPENDED',
                  tint: QuestColors.osRed,
                  compact: true,
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(business.name,
              style: QuestTypography.osHeadlineSmall,
              maxLines: 2,
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 4),
          Text(
            _placesLabel(business),
            style: QuestTypography.osBodySmall
                .copyWith(color: QuestColors.textDim(context)),
          ),
          const SizedBox(height: 12),

          // The three refusals are spelled out rather than collapsed into a
          // disabled button, because each one has a different fix and only
          // the owner can act on any of them.
          if (business.isSuspended)
            const _Notice(
              icon: Icons.pause_circle_outline,
              text: 'This account is suspended, so the dashboard is closed. '
                  'Your claimed places are kept.',
            )
          else if (!business.analyticsSubscribed)
            const _Notice(
              icon: Icons.lock_outline,
              text: 'Analytics is not part of this account yet. '
                  'Talk to Bsheel to switch it on.',
            )
          else if (!hasLink)
            const _Notice(
              icon: Icons.info_outline,
              text: 'This build was not told where the dashboard lives, '
                  'so there is no link to open.',
            )
          else
            ArcadeButton(
              label: 'OPEN DASHBOARD',
              onTap: () => _openDashboard(context),
            ),
        ],
      ),
    );
  }

  String _placesLabel(BusinessSummary business) {
    if (business.places.isEmpty) {
      // Distinct from "no activity": nothing has been claimed for them yet,
      // and no amount of waiting will change that on its own.
      return 'No places claimed yet';
    }
    final unpublished =
        business.places.where((place) => !place.isPublished).length;
    final count = business.places.length;
    final noun = count == 1 ? 'place' : 'places';
    if (unpublished == 0) return '$count $noun on the map';
    // An unpublished place reports no activity at all, which otherwise looks
    // like a bug rather than a place that is not live yet.
    return '$count $noun · $unpublished not published yet';
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: QuestColors.textDim(context)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: QuestTypography.osBodySmall
                .copyWith(color: QuestColors.textDim(context)),
          ),
        ),
      ],
    );
  }
}
