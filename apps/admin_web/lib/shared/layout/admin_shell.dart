import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/admin_counts_provider.dart';
import '../../core/providers/admin_role_provider.dart';
import '../../core/theme/admin_layout_constants.dart';
import '../../core/theme/bsheel_design.dart';
import '../../features/admin_auth/presentation/pages/admin_access_denied_page.dart';
import '../widgets/admin_sidebar.dart';
import '../widgets/bsheel_widgets.dart';

/// Arcade Pop shell — the ink sidebar on the left, the page on the right.
///
/// The page owns its own header bar (`BsheelPageHeader`), because the
/// title, meta line and actions differ per route and the design draws
/// them as part of the page rather than as a shared topbar. Below the
/// tablet breakpoint the sidebar becomes a drawer and the page header
/// grows a hamburger on its left.
class AdminShell extends ConsumerWidget {
  final Widget child;

  const AdminShell({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gate = ref.watch(isAdminUserProvider);
    // Hold the sidebar-counts realtime channel open for the life of the
    // shell, so the badges move as submissions and reports land.
    ref.watch(adminCountsRealtimeProvider);

    return gate.when(
      data: (isAdmin) {
        if (!isAdmin) return const AdminAccessDeniedPage();

        final isDesktop = MediaQuery.of(context).size.width >=
            AdminLayoutConstants.tabletBreakpoint;

        if (isDesktop) {
          return Scaffold(
            backgroundColor: BsheelColors.bg,
            body: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const AdminSidebar(),
                Expanded(child: child),
              ],
            ),
          );
        }

        return Scaffold(
          backgroundColor: BsheelColors.bg,
          drawer: const Drawer(
            backgroundColor: BsheelColors.inkPanel,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            shape: RoundedRectangleBorder(),
            child: SafeArea(child: AdminSidebar(inDrawer: true)),
          ),
          body: SafeArea(child: child),
        );
      },
      loading: () => const Scaffold(
        backgroundColor: BsheelColors.bg,
        body: Center(
          child: SizedBox(
            width: 26,
            height: 26,
            child: CircularProgressIndicator(
              color: BsheelColors.primary,
              strokeWidth: 2.5,
            ),
          ),
        ),
      ),
      error: (_, __) => const AdminAccessDeniedPage(),
    );
  }
}

/// The standard page body: a header bar, then a scrolling content area on
/// the cream ground. Pages that need a custom split (the moderation queue
/// rail, the users detail rail) build their own Column instead.
class AdminPage extends StatelessWidget {
  final String title;
  final String? meta;
  final Color? metaColor;
  final List<Widget> actions;

  /// Rendered directly under the header, outside the scroll area — used
  /// for a filter-chip row that should stay put while the body scrolls.
  final Widget? subheader;

  final Widget child;

  /// Set false when [child] manages its own scrolling (a ListView, or a
  /// table with its own viewport).
  final bool scrollable;

  final EdgeInsetsGeometry padding;

  const AdminPage({
    super.key,
    required this.title,
    required this.child,
    this.meta,
    this.metaColor,
    this.actions = const [],
    this.subheader,
    this.scrollable = true,
    this.padding = BsheelLayout.pagePadding,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BsheelPageHeader(
          title: title,
          meta: meta,
          metaColor: metaColor,
          actions: actions,
        ),
        if (subheader != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 14, 24, 0),
            child: subheader,
          ),
        Expanded(
          child: Builder(
            builder: (context) {
              // With a chip row above it the body starts 14px down, not
              // 20 — the chips already carry the gap, and the design puts
              // the table 14px under them.
              final resolved = subheader == null
                  ? padding
                  : padding.resolve(Directionality.of(context)).copyWith(
                        top: 14,
                      );
              return scrollable
                  ? SingleChildScrollView(padding: resolved, child: child)
                  : Padding(padding: resolved, child: child);
            },
          ),
        ),
      ],
    );
  }
}

/// A 640px-wide content pane centred on the cream ground — the shape the
/// design uses for every page that isn't a full-width work surface.
class AdminPane extends StatelessWidget {
  final String title;
  final String? meta;
  final Color? metaColor;
  final List<Widget> actions;
  final Widget child;
  final double maxWidth;

  const AdminPane({
    super.key,
    required this.title,
    required this.child,
    this.meta,
    this.metaColor,
    this.actions = const [],
    this.maxWidth = BsheelLayout.paneMaxWidth,
  });

  @override
  Widget build(BuildContext context) {
    return AdminPage(
      title: title,
      meta: meta,
      metaColor: metaColor,
      actions: actions,
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [child],
          ),
        ),
      ),
    );
  }
}
