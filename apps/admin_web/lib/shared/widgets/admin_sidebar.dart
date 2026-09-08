import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/backend/app_backend.dart';

import '../../core/providers/admin_counts_provider.dart';
import '../../core/router/admin_route_names.dart';
import '../../core/theme/bsheel_design.dart';

/// "Port" sidebar — flush white column with a single hairline rule on
/// the right, small tracked caps for section heads, and a solid black
/// pill for the active link (inversion is the only emphasis). The
/// integer route indices are kept compatible with the previous
/// implementation.
class AdminSidebar extends ConsumerWidget {
  final bool inDrawer;

  const AdminSidebar({super.key, this.inDrawer = false});

  static const double _width = 256;

  // Sections are built per-render so the moderation badges can carry
  // live counts from `adminCountsProvider`. Static order, dynamic
  // values.
  List<_NavSection> _buildSections(AdminCounts c) => [
        const _NavSection('Overview', [
          _NavItem('Dashboard', 0),
        ]),
        _NavSection('Moderation', [
          _NavItem(
            'Pending',
            1,
            badge: c.pending > 0 ? _fmt(c.pending) : null,
          ),
          const _NavItem('History', 2),
          _NavItem(
            'Appeals',
            9,
            badge: c.appeals > 0 ? _fmt(c.appeals) : null,
          ),
          _NavItem(
            'Reports',
            10,
            badge: c.reports > 0 ? _fmt(c.reports) : null,
          ),
        ]),
        const _NavSection('Content', [
          _NavItem('Quests', 4),
          _NavItem('Quest of Day', 17),
          _NavItem('Injection', 11),
          _NavItem('Feed', 3),
        ]),
        const _NavSection('Community', [
          _NavItem('Users', 5),
          _NavItem('Announcements', 7),
          _NavItem('Auto Rules', 8),
          _NavItem('XP Manager', 6),
        ]),
        const _NavSection('Web', [
          _NavItem('Signups', 13),
          _NavItem('Suggestions', 14),
        ]),
        const _NavSection('System', [
          _NavItem('Settings', 12),
        ]),
      ];

  /// Compact badge: 99+ for anything over 99 so the pill stays tidy.
  static String _fmt(int n) => n > 99 ? '99+' : '$n';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentIndex = _currentIndex(context);
    final counts =
        ref.watch(adminCountsProvider).valueOrNull ?? const AdminCounts.zero();
    final sections = _buildSections(counts);

    return SizedBox(
      width: inDrawer ? null : _width,
      child: Container(
        decoration: BoxDecoration(
          color: BsheelColors.bg,
          border: inDrawer
              ? null
              : const Border(
                  right: BorderSide(
                    color: BsheelColors.line,
                    width: BsheelBorders.thin,
                  ),
                ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Brand row
            Container(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              decoration: const BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: BsheelColors.line,
                    width: BsheelBorders.thin,
                  ),
                ),
              ),
              child: Row(
                children: [
                  // Brand mark — small inverted square.
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: BsheelColors.ink,
                      borderRadius: BorderRadius.circular(BsheelRadii.sm),
                    ),
                    alignment: Alignment.center,
                    child: const Text(
                      'B',
                      style: TextStyle(
                        fontFamily: BsheelFonts.body,
                        fontWeight: FontWeight.w400,
                        fontSize: 15,
                        color: BsheelColors.pureWhite,
                        height: 1,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Bsheel',
                          style: BsheelType.displaySm.copyWith(
                            fontSize: 20,
                            height: 1,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'ADMIN · V1.0',
                          style: BsheelType.labelSm.copyWith(
                            fontSize: 9,
                            letterSpacing: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (inDrawer)
                    IconButton(
                      icon: const Icon(Icons.close, color: BsheelColors.ink),
                      onPressed: () => Navigator.of(context).pop(),
                      tooltip: 'Close',
                    ),
                ],
              ),
            ),

            // Nav
            Expanded(
              child: ListView(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                children: [
                  for (final section in sections) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 18, 12, 8),
                      child: Text(
                        section.title.toUpperCase(),
                        style: BsheelType.labelSm.copyWith(
                          fontSize: 9.5,
                          letterSpacing: 1.4,
                        ),
                      ),
                    ),
                    for (final item in section.items)
                      _NavLink(
                        item: item,
                        active: currentIndex == item.index,
                        onTap: () {
                          if (inDrawer) Navigator.of(context).pop();
                          _onTap(context, item.index);
                        },
                      ),
                  ],
                  const SizedBox(height: 12),
                ],
              ),
            ),

            // Footer (avatar + sign-out) — live from adminMetaProvider.
            const _AdminFooter(),
          ],
        ),
      ),
    );
  }

  int _currentIndex(BuildContext context) {
    final loc = GoRouterState.of(context).matchedLocation;
    if (loc.startsWith('/moderation/history')) return 2;
    // Reviewing a single submission is part of the Pending queue flow, so
    // the Pending item stays highlighted (the dedicated "Review" nav item
    // was removed — it duplicated "Pending").
    if (loc.startsWith('/moderation')) return 1;
    if (loc.startsWith('/feed')) return 3;
    if (loc.startsWith('/quests')) return 4;
    if (loc.startsWith('/users')) return 5;
    if (loc.startsWith('/xp')) return 6;
    if (loc.startsWith('/announcements')) return 7;
    if (loc.startsWith('/auto-notifications')) return 8;
    if (loc.startsWith('/appeals')) return 9;
    if (loc.startsWith('/reports')) return 10;
    if (loc.startsWith('/injection')) return 11;
    if (loc.startsWith('/web-signups')) return 13;
    if (loc.startsWith('/web-quest-suggestions')) return 14;
    if (loc.startsWith('/settings')) return 12;
    return 0;
  }

  void _onTap(BuildContext context, int index) {
    switch (index) {
      case 0:
        context.goNamed(AdminRouteNames.dashboard);
      case 1:
        context.goNamed(AdminRouteNames.pendingSubmissions);
      case 2:
        context.goNamed(AdminRouteNames.submissionHistory);
      case 3:
        context.goNamed(AdminRouteNames.feedManagement);
      case 4:
        context.goNamed(AdminRouteNames.questManagement);
      case 5:
        context.goNamed(AdminRouteNames.users);
      case 6:
        context.goNamed(AdminRouteNames.xpManagement);
      case 7:
        context.goNamed(AdminRouteNames.announcements);
      case 8:
        context.goNamed(AdminRouteNames.autoNotifications);
      case 9:
        context.goNamed(AdminRouteNames.appeals);
      case 10:
        context.goNamed(AdminRouteNames.reports);
      case 11:
        context.goNamed(AdminRouteNames.injection);
      case 12:
        context.goNamed(AdminRouteNames.settings);
      case 13:
        context.goNamed(AdminRouteNames.webSignups);
      case 14:
        context.goNamed(AdminRouteNames.webQuestSuggestions);
      case 17:
        context.goNamed(AdminRouteNames.questOfTheDay);
    }
  }
}

/// Footer — avatar + name + role, live from [adminMetaProvider].
/// On loading/error falls back to "Admin · ADMIN" so the sidebar layout
/// stays stable while the lookup is in flight.
class _AdminFooter extends ConsumerWidget {
  const _AdminFooter();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final meta = ref.watch(adminMetaProvider).valueOrNull;
    final name = meta?.displayName ?? 'Admin';
    final role = meta?.roleLabel ?? 'ADMIN';
    final initial = name.isNotEmpty ? name[0].toUpperCase() : 'A';

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(
            color: BsheelColors.line,
            width: BsheelBorders.thin,
          ),
        ),
      ),
      child: Row(
        children: [
          _Avatar(
            avatarUrl: meta?.avatarUrl,
            initial: initial,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  overflow: TextOverflow.ellipsis,
                  style: BsheelType.bodyMdBold.copyWith(fontSize: 13),
                ),
                Text(
                  role,
                  overflow: TextOverflow.ellipsis,
                  style: BsheelType.labelSm.copyWith(
                    fontSize: 9,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
          ),
          _LogoutButton(),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.avatarUrl, required this.initial});
  final String? avatarUrl;
  final String initial;

  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      width: 32,
      height: 32,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: BsheelColors.ink,
      ),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: const TextStyle(
          fontFamily: BsheelFonts.body,
          fontWeight: FontWeight.w400,
          color: BsheelColors.pureWhite,
          fontSize: 13,
        ),
      ),
    );

    if (avatarUrl == null || avatarUrl!.isEmpty) return fallback;

    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: BsheelColors.line,
          width: BsheelBorders.thin,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Image.network(
        avatarUrl!,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => fallback,
      ),
    );
  }
}

class _NavSection {
  final String title;
  final List<_NavItem> items;
  const _NavSection(this.title, this.items);
}

class _NavItem {
  final String label;
  final int index;
  final String? badge;
  const _NavItem(this.label, this.index, {this.badge});
}

class _NavLink extends StatefulWidget {
  final _NavItem item;
  final bool active;
  final VoidCallback onTap;

  const _NavLink({
    required this.item,
    required this.active,
    required this.onTap,
  });

  @override
  State<_NavLink> createState() => _NavLinkState();
}

class _NavLinkState extends State<_NavLink> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.active;
    final fg = active
        ? BsheelColors.pureWhite
        : (_hover ? BsheelColors.ink : BsheelColors.inkSoft);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 110),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: active
                  ? BsheelColors.ink
                  : (_hover ? BsheelColors.surface : Colors.transparent),
              borderRadius: BorderRadius.circular(BsheelRadii.full),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.item.label,
                    style: BsheelType.bodyMd.copyWith(
                      color: fg,
                      fontWeight: FontWeight.w400,
                      height: 1.2,
                    ),
                  ),
                ),
                if (widget.item.badge != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color:
                          active ? BsheelColors.pureWhite : Colors.transparent,
                      borderRadius: BorderRadius.circular(BsheelRadii.full),
                      border: Border.all(
                        color:
                            active ? BsheelColors.pureWhite : BsheelColors.line,
                        width: BsheelBorders.thin,
                      ),
                    ),
                    child: Text(
                      widget.item.badge!,
                      style: BsheelType.labelSm.copyWith(
                        fontSize: 9.5,
                        letterSpacing: 0.5,
                        color: active ? BsheelColors.ink : BsheelColors.hot,
                        height: 1.2,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LogoutButton extends StatelessWidget {
  Future<void> _signOut(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: BsheelColors.paper,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(BsheelRadii.xl),
          side: const BorderSide(
            color: BsheelColors.line,
            width: BsheelBorders.thin,
          ),
        ),
        title: RichText(
          text: const TextSpan(
            style: BsheelType.displaySm,
            children: [
              TextSpan(text: 'Sign '),
              TextSpan(
                text: 'out?',
                style: TextStyle(fontStyle: FontStyle.italic),
              ),
            ],
          ),
        ),
        content: Text(
          "You'll need to log back in to access the admin panel.",
          style: BsheelType.bodyMd.copyWith(color: BsheelColors.inkSoft),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'CANCEL',
              style: BsheelType.labelMd.copyWith(color: BsheelColors.inkMuted),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'SIGN OUT',
              style: BsheelType.labelMd.copyWith(color: BsheelColors.hot),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await AppBackend.repositories.auth.signOut();
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Sign out',
      child: InkWell(
        onTap: () => _signOut(context),
        customBorder: const CircleBorder(),
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: BsheelColors.bg,
            shape: BoxShape.circle,
            border: Border.all(
              color: BsheelColors.line,
              width: BsheelBorders.thin,
            ),
          ),
          alignment: Alignment.center,
          child: const Icon(
            Icons.logout_rounded,
            size: 13,
            color: BsheelColors.ink,
          ),
        ),
      ),
    );
  }
}
