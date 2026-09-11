import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/backend/app_backend.dart';
import '../../core/providers/admin_counts_provider.dart';
import '../../core/providers/admin_role_provider.dart';
import '../../core/router/admin_route_access.dart';
import '../../core/router/admin_route_names.dart';
import '../../core/theme/bsheel_design.dart';
import 'bsheel_widgets.dart';

/// Arcade Pop sidebar — a 230px ink panel holding the destinations the
/// signed-in admin's role can actually use, ordered by how often a
/// moderator touches them.
///
/// A moderator sees fourteen of the nineteen rows. The six in
/// [AdminRouteAccess.superAdminOnly] are dropped, because every read
/// behind them is `@Roles('super_admin')` and a moderator following the
/// link only got as far as a 403. The router refuses those paths as well,
/// so this row filter is presentation and not the access control.
///
/// The active row is a violet fill with a 2px cream border and a white
/// label. Badge counts appear on Moderation, Unclear, Appeals and Reports
/// only: the queues that represent work waiting on a person. A badge is
/// coral when its row is inactive and gold when it is active, so it stays
/// legible against the violet fill.
class AdminSidebar extends ConsumerWidget {
  final bool inDrawer;

  const AdminSidebar({super.key, this.inDrawer = false});

  static const double width = BsheelLayout.sidebarWidth;

  /// Route order per the spec. Badges are resolved at build time.
  static const List<_Destination> _destinations = [
    _Destination('DASHBOARD', AdminRouteNames.dashboard, '/'),
    _Destination(
      'MODERATION',
      AdminRouteNames.pendingSubmissions,
      '/moderation',
      badge: _Badge.pending,
    ),
    _Destination(
      'APPEALS',
      AdminRouteNames.appeals,
      '/appeals',
      badge: _Badge.appeals,
    ),
    _Destination(
      'UNCLEAR',
      AdminRouteNames.unclearQueue,
      '/moderation/unclear',
      badge: _Badge.unclear,
    ),
    _Destination(
      'HISTORY',
      AdminRouteNames.submissionHistory,
      '/moderation/history',
    ),
    _Destination('FEED', AdminRouteNames.feedManagement, '/feed'),
    _Destination('QUESTS', AdminRouteNames.questManagement, '/quests'),
    _Destination('AUTHORING', AdminRouteNames.questAuthoring, '/authoring'),
    _Destination('QUEST OF THE DAY', AdminRouteNames.questOfTheDay, '/qotd'),
    _Destination('CAMPAIGNS', AdminRouteNames.questCampaigns, '/campaigns'),
    _Destination('DESTINATIONS', AdminRouteNames.mapPlaces, '/destinations'),
    _Destination('USERS', AdminRouteNames.users, '/users'),
    _Destination('XP', AdminRouteNames.xpManagement, '/xp'),
    _Destination(
      'ANNOUNCEMENTS',
      AdminRouteNames.announcements,
      '/announcements',
    ),
    _Destination(
      'AUTO NOTIFICATIONS',
      AdminRouteNames.autoNotifications,
      '/auto-notifications',
    ),
    _Destination(
      'REPORTS',
      AdminRouteNames.reports,
      '/reports',
      badge: _Badge.reports,
    ),
    _Destination('INJECTION', AdminRouteNames.injection, '/injection'),
    _Destination('WEB SIGNUPS', AdminRouteNames.webSignups, '/web-signups'),
    _Destination(
      'QUEST SUGGESTIONS',
      AdminRouteNames.webQuestSuggestions,
      '/web-quest-suggestions',
    ),
    _Destination(
      'DELETION REQUESTS',
      AdminRouteNames.deletionRequests,
      '/deletion-requests',
    ),
    _Destination('SETTINGS', AdminRouteNames.settings, '/settings'),
  ];

  /// Longest matching prefix wins, so `/moderation/history` highlights
  /// HISTORY rather than MODERATION. Reviewing one submission is part of
  /// the queue flow, so it keeps MODERATION lit.
  static String _activePath(String location) {
    if (location.startsWith('/moderation/history')) {
      return '/moderation/history';
    }
    if (location.startsWith('/moderation')) return '/moderation';
    var best = '/';
    for (final d in _destinations) {
      if (d.path == '/') continue;
      if (location.startsWith(d.path) && d.path.length > best.length) {
        best = d.path;
      }
    }
    return best;
  }

  static String _fmt(int n) => n > 99 ? '99+' : '$n';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = _activePath(GoRouterState.of(context).matchedLocation);
    // The role the router already resolved before it let this shell
    // mount, so reading it here costs nothing and cannot disagree.
    final role = ref.watch(adminRoleEnumProvider).valueOrNull;
    final counts =
        ref.watch(adminCountsProvider).valueOrNull ?? const AdminCounts.zero();

    String? badgeFor(_Badge? badge) {
      final value = switch (badge) {
        _Badge.pending => counts.pending,
        _Badge.appeals => counts.appeals,
        _Badge.reports => counts.reports,
        _Badge.unclear => counts.unclear,
        null => 0,
      };
      return value > 0 ? _fmt(value) : null;
    }

    return SizedBox(
      width: inDrawer ? null : width,
      child: Container(
        color: BsheelColors.inkPanel,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Brand
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
              child: Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'BSHEEL',
                          style: TextStyle(
                            fontFamily: BsheelFonts.display,
                            fontWeight: FontWeight.w800,
                            // Variable font: drive the wght axis explicitly.
                            fontVariations: [FontVariation('wght', 800)],
                            fontSize: 21,
                            height: 1.1,
                            letterSpacing: -0.63,
                            color: BsheelColors.inkPanelTextStrong,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'ADMIN CONSOLE',
                          style: TextStyle(
                            fontFamily: BsheelFonts.mono,
                            fontWeight: FontWeight.w700,
                            // Variable font: drive the wght axis explicitly.
                            fontVariations: [FontVariation('wght', 700)],
                            fontSize: 9,
                            height: 1.3,
                            letterSpacing: 1.44,
                            color: BsheelColors.accent,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (inDrawer)
                    IconButton(
                      icon: const Icon(
                        Icons.close_rounded,
                        color: BsheelColors.inkPanelTextStrong,
                        size: 20,
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                      tooltip: 'Close',
                    ),
                ],
              ),
            ),

            // Destinations
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(10, 6, 10, 14),
                children: [
                  for (final d in _destinations)
                    if (AdminRouteAccess.allows(d.path, role))
                      _NavRow(
                        label: d.label,
                        badge: badgeFor(d.badge),
                        active: d.path == active,
                        onTap: () {
                          if (inDrawer) Navigator.of(context).pop();
                          context.goNamed(d.name);
                        },
                      ),
                ],
              ),
            ),

            const _SidebarFooter(),
          ],
        ),
      ),
    );
  }
}

enum _Badge { pending, appeals, reports, unclear }

class _Destination {
  final String label;
  final String name;
  final String path;
  final _Badge? badge;

  const _Destination(this.label, this.name, this.path, {this.badge});
}

class _NavRow extends StatefulWidget {
  final String label;
  final String? badge;
  final bool active;
  final VoidCallback onTap;

  const _NavRow({
    required this.label,
    required this.badge,
    required this.active,
    required this.onTap,
  });

  @override
  State<_NavRow> createState() => _NavRowState();
}

class _NavRowState extends State<_NavRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.active;

    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 110),
            constraints: const BoxConstraints(
              minHeight: BsheelLayout.minTarget,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
            decoration: BoxDecoration(
              color: active
                  ? BsheelColors.primary
                  : (_hover ? BsheelColors.inkPanelBorder : Colors.transparent),
              borderRadius: BorderRadius.circular(BsheelRadii.sm),
              border: Border.all(
                color: active
                    ? BsheelColors.inkPanelTextStrong
                    : Colors.transparent,
                width: BsheelBorders.thick,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.label,
                    style: TextStyle(
                      fontFamily: BsheelFonts.mono,
                      fontWeight: FontWeight.w700,
                      // Variable font: drive the wght axis explicitly.
                      fontVariations: const [FontVariation('wght', 700)],
                      fontSize: 10,
                      height: 1.3,
                      letterSpacing: 0.9,
                      color: active
                          ? BsheelColors.pureWhite
                          : (_hover
                              ? BsheelColors.inkPanelTextStrong
                              : BsheelColors.inkPanelText),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (widget.badge != null) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      // Gold on the violet fill, coral everywhere else.
                      color: active ? BsheelColors.accent : BsheelColors.danger,
                      borderRadius: BorderRadius.circular(BsheelRadii.full),
                      border: const Border.fromBorderSide(
                        BsheelBorders.inkSide,
                      ),
                    ),
                    child: Text(
                      widget.badge!,
                      style: const TextStyle(
                        fontFamily: BsheelFonts.mono,
                        fontWeight: FontWeight.w700,
                        // Variable font: drive the wght axis explicitly.
                        fontVariations: [FontVariation('wght', 700)],
                        fontSize: 9,
                        height: 1.3,
                        color: BsheelColors.ink,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Signed-in moderator and their role, with sign-out.
class _SidebarFooter extends ConsumerWidget {
  const _SidebarFooter();

  Future<void> _signOut(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => BsheelDialog(
        title: 'Sign out?',
        content: Text(
          "You'll need to log back in to reach the admin console.",
          style: BsheelType.bodySm.copyWith(color: BsheelColors.inkSoft),
        ),
        actions: [
          BsheelButton.ghost(
            label: 'Cancel',
            small: true,
            onPressed: () => Navigator.pop(ctx, false),
          ),
          BsheelButton.coral(
            label: 'Sign out',
            small: true,
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await AppBackend.repositories.auth.signOut();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final meta = ref.watch(adminMetaProvider).valueOrNull;
    final name = meta?.displayName ?? 'Admin';
    final role = meta?.roleLabel ?? 'ADMIN';

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 16),
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(
            color: BsheelColors.inkPanelBorder,
            width: BsheelBorders.thick,
          ),
        ),
      ),
      child: Row(
        children: [
          _FooterAvatar(url: meta?.avatarUrl, name: name),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  overflow: TextOverflow.ellipsis,
                  style: BsheelType.titleSm.copyWith(
                    color: BsheelColors.inkPanelTextStrong,
                  ),
                ),
                Text(
                  role,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: BsheelFonts.mono,
                    fontWeight: FontWeight.w700,
                    // Variable font: drive the wght axis explicitly.
                    fontVariations: [FontVariation('wght', 700)],
                    fontSize: 9,
                    height: 1.4,
                    letterSpacing: 0.9,
                    color: BsheelColors.inkPanelText,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(
              Icons.logout_rounded,
              size: 17,
              color: BsheelColors.inkPanelText,
            ),
            tooltip: 'Sign out',
            onPressed: () => _signOut(context),
          ),
        ],
      ),
    );
  }
}

/// 30px rounded-square avatar with a cream outline, per the design.
class _FooterAvatar extends StatelessWidget {
  final String? url;
  final String name;

  const _FooterAvatar({required this.url, required this.name});

  @override
  Widget build(BuildContext context) {
    final initial = name.isNotEmpty ? name[0].toUpperCase() : 'A';
    final fallback = Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        color: BsheelColors.danger,
        borderRadius: BorderRadius.circular(BsheelRadii.sm),
        border: Border.all(
          color: BsheelColors.inkPanelTextStrong,
          width: BsheelBorders.thick,
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: BsheelType.titleSm.copyWith(
          color: BsheelColors.ink,
          fontSize: 13,
        ),
      ),
    );

    if (url == null || url!.isEmpty) return fallback;

    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(BsheelRadii.sm),
        border: Border.all(
          color: BsheelColors.inkPanelTextStrong,
          width: BsheelBorders.thick,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Image.network(
        url!,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => fallback,
      ),
    );
  }
}
