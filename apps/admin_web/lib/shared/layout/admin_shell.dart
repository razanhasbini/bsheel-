import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/admin_counts_provider.dart';
import '../../core/providers/admin_role_provider.dart';
import '../../core/theme/admin_layout_constants.dart';
import '../../core/theme/bsheel_design.dart';
import '../../features/admin_auth/presentation/pages/admin_access_denied_page.dart';
import '../widgets/admin_sidebar.dart';
import '../widgets/admin_topbar.dart';

/// "Port" shell — flush white page split by hairline rules: a fixed
/// sidebar column with a 1px rule on its right, a topbar with a 1px
/// rule below, then the content scroll area. No floating cards, no
/// shadows.
class AdminShell extends ConsumerWidget {
  final Widget child;

  const AdminShell({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gate = ref.watch(isAdminUserProvider);
    // Subscribe to the sidebar-counts realtime channel for the lifetime
    // of the shell, so badge numbers update as submissions/reports land.
    ref.watch(adminCountsRealtimeProvider);

    return gate.when(
      data: (isAdmin) {
        if (!isAdmin) return const AdminAccessDeniedPage();

        final width = MediaQuery.of(context).size.width;
        final isDesktop = width >= AdminLayoutConstants.tabletBreakpoint;

        if (isDesktop) {
          return Scaffold(
            backgroundColor: BsheelColors.bg,
            body: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const AdminSidebar(),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const AdminTopbar(showHamburger: false),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                          child: child,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }

        return Scaffold(
          backgroundColor: BsheelColors.bg,
          drawer: const _AdminDrawer(),
          body: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const AdminTopbar(showHamburger: true),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                    child: child,
                  ),
                ),
              ],
            ),
          ),
        );
      },
      loading: () => const Scaffold(
        backgroundColor: BsheelColors.bg,
        body: Center(
          child: CircularProgressIndicator(
            color: BsheelColors.ink,
            strokeWidth: 1.5,
          ),
        ),
      ),
      error: (e, _) => const AdminAccessDeniedPage(),
    );
  }
}

class _AdminDrawer extends StatelessWidget {
  const _AdminDrawer();

  @override
  Widget build(BuildContext context) {
    return const Drawer(
      backgroundColor: BsheelColors.bg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: Border(
        right: BorderSide(
          color: BsheelColors.line,
          width: BsheelBorders.thin,
        ),
      ),
      child: SafeArea(
        child: AdminSidebar(inDrawer: true),
      ),
    );
  }
}
