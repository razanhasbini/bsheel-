import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers/admin_counts_provider.dart';
import '../../core/router/admin_route_names.dart';
import '../../core/theme/bsheel_design.dart';

/// "Port" topbar — flush white bar with a single hairline rule below,
/// small tracked caps crumbs ("— DASHBOARD · TODAY 14:32"), quiet
/// pill search on a #F7F7F7 surface, and two circular icon buttons
/// (the primary "+" is inverted solid black). On mobile the hamburger
/// replaces the search.
class AdminTopbar extends ConsumerWidget implements PreferredSizeWidget {
  final bool showHamburger;

  const AdminTopbar({super.key, required this.showHamburger});

  String _crumbHere(BuildContext context) {
    final loc = GoRouterState.of(context).matchedLocation;
    if (loc.startsWith('/moderation/history')) return 'Submission History';
    if (loc.startsWith('/moderation/review')) return 'Review';
    if (loc.startsWith('/moderation')) return 'Pending';
    if (loc.startsWith('/feed')) return 'Feed';
    if (loc.startsWith('/quests')) return 'Quests';
    if (loc.startsWith('/users')) return 'Users';
    if (loc.startsWith('/xp')) return 'XP Manager';
    if (loc.startsWith('/announcements')) return 'Announcements';
    if (loc.startsWith('/auto-notifications')) return 'Auto Rules';
    if (loc.startsWith('/appeals')) return 'Appeals';
    if (loc.startsWith('/reports')) return 'Reports';
    if (loc.startsWith('/injection')) return 'Injection';
    if (loc.startsWith('/web-signups')) return 'Signups';
    if (loc.startsWith('/web-quest-suggestions')) return 'Suggestions';
    if (loc.startsWith('/settings')) return 'Settings';
    return 'Dashboard';
  }

  String _shortNow() {
    final now = DateTime.now();
    final hh = now.hour.toString().padLeft(2, '0');
    final mm = now.minute.toString().padLeft(2, '0');
    return 'TODAY · $hh:$mm';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isMobile = MediaQuery.of(context).size.width < 860;
    final counts =
        ref.watch(adminCountsProvider).valueOrNull ?? const AdminCounts.zero();
    final pendingTotal = counts.pending + counts.appeals + counts.reports;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      decoration: const BoxDecoration(
        color: BsheelColors.bg,
        border: Border(
          bottom: BorderSide(
            color: BsheelColors.line,
            width: BsheelBorders.thin,
          ),
        ),
      ),
      child: Row(
        children: [
          if (showHamburger)
            Builder(
              builder: (context) => Padding(
                padding: const EdgeInsets.only(right: 10),
                child: _IconBtn(
                  icon: Icons.menu_rounded,
                  onTap: () => Scaffold.of(context).openDrawer(),
                ),
              ),
            ),
          // Crumbs — em-dash prefix is part of the eyebrow look.
          Flexible(
            child: Text(
              '— ${_crumbHere(context).toUpperCase()}  ·  ${_shortNow()}',
              style: BsheelType.labelMd.copyWith(
                color: BsheelColors.ink,
                fontSize: 11,
                letterSpacing: 1.2,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (!isMobile) ...[
            const SizedBox(width: 14),
            const Spacer(),
            // Search — quiet surface pill.
            Container(
              width: 280,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: BsheelColors.surface,
                borderRadius: BorderRadius.circular(BsheelRadii.full),
                border: Border.all(
                  color: BsheelColors.line,
                  width: BsheelBorders.thin,
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.search_rounded,
                    size: 16,
                    color: BsheelColors.inkMuted,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      // Submitting jumps to the Users page with the query
                      // applied to its search filter (`/users?q=...`).
                      onSubmitted: (value) {
                        final query = value.trim();
                        if (query.isEmpty) return;
                        context.goNamed(
                          AdminRouteNames.users,
                          queryParameters: {'q': query},
                        );
                      },
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        hintText: 'Search users…',
                        hintStyle: BsheelType.bodyMd.copyWith(
                          color: BsheelColors.inkMuted,
                          fontSize: 13,
                        ),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                        filled: false,
                      ),
                      style: BsheelType.bodyMd.copyWith(fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(width: 10),
          // Bell → most-urgent queue (pending submissions first, falling
          // back to appeals / reports). Hides when there's nothing to do.
          if (pendingTotal > 0)
            _IconBtn(
              icon: Icons.notifications_none_rounded,
              badge: pendingTotal > 99 ? '99+' : '$pendingTotal',
              onTap: () {
                if (counts.pending > 0) {
                  context.goNamed(AdminRouteNames.pendingSubmissions);
                } else if (counts.appeals > 0) {
                  context.goNamed(AdminRouteNames.appeals);
                } else {
                  context.goNamed(AdminRouteNames.reports);
                }
              },
            ),
          if (pendingTotal > 0) const SizedBox(width: 8),
          // Quest creation lives inside Quest Management's dialog, so this
          // is honestly labelled as a shortcut to that page.
          Tooltip(
            message: 'Quest management',
            child: _IconBtn(
              icon: Icons.add_rounded,
              color: BsheelColors.ink,
              fg: BsheelColors.pureWhite,
              onTap: () => context.goNamed(AdminRouteNames.questManagement),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(64);
}

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final Color fg;
  final VoidCallback? onTap;
  final String? badge;

  const _IconBtn({
    required this.icon,
    this.color = BsheelColors.bg,
    this.fg = BsheelColors.ink,
    this.onTap,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    // Solid (inverted) buttons carry no visible outline; quiet ones get
    // the hairline.
    final quiet = color == BsheelColors.bg;
    final btn = Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: quiet
            ? Border.all(
                color: BsheelColors.line,
                width: BsheelBorders.thin,
              )
            : null,
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: 16, color: fg),
    );

    return MouseRegion(
      cursor: onTap == null ? MouseCursor.defer : SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: badge == null
            ? btn
            : Stack(
                clipBehavior: Clip.none,
                children: [
                  btn,
                  Positioned(
                    top: -4,
                    right: -4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: BsheelColors.ink,
                        borderRadius: BorderRadius.circular(BsheelRadii.full),
                        border: Border.all(
                          color: BsheelColors.pureWhite,
                          width: BsheelBorders.thin,
                        ),
                      ),
                      child: Text(
                        badge!,
                        style: const TextStyle(
                          fontFamily: BsheelFonts.body,
                          fontWeight: FontWeight.w400,
                          fontSize: 9,
                          letterSpacing: 0.3,
                          color: BsheelColors.pureWhite,
                          height: 1.2,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
