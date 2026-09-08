import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers/repository_providers.dart';
import '../../../../core/theme/bsheel_design.dart';
import '../../../../shared/widgets/bsheel_widgets.dart';

/// Shown when a signed-in account has no admin role. Renders outside the
/// shell, so it owns its own [Scaffold] and draws the same 620px page frame
/// as the login screen — with the refusal carried by a coral callout.
class AdminAccessDeniedPage extends ConsumerWidget {
  const AdminAccessDeniedPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: BsheelColors.bg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 32, 32, 40),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 620),
              padding: const EdgeInsets.all(36),
              decoration: BoxDecoration(
                color: BsheelColors.bg,
                borderRadius: BorderRadius.circular(BsheelRadii.lg),
                border: const Border.fromBorderSide(BsheelBorders.inkSide),
                boxShadow: BsheelShadows.frame,
              ),
              child: Center(
                child: SizedBox(
                  width: 330,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text('BSHEEL ADMIN', style: BsheelType.displayLg),
                      const SizedBox(height: 2),
                      const BsheelLabel('Restricted area'),
                      const SizedBox(height: 16),
                      const BsheelCallout.danger('You are not authorized.'),
                      const SizedBox(height: 16),
                      Text(
                        'This account does not have dashboard access. '
                        'Ask a super admin to grant you an admin role.',
                        style: BsheelType.bodyMd.copyWith(
                          color: BsheelColors.inkSoft,
                        ),
                      ),
                      const SizedBox(height: 18),
                      BsheelButton.ghost(
                        label: 'SIGN OUT',
                        icon: Icons.logout,
                        expand: true,
                        height: 48,
                        onPressed: () =>
                            ref.read(authRepositoryProvider).signOut(),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
