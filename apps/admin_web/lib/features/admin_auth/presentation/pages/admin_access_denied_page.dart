import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers/repository_providers.dart';
import '../../../../core/theme/bsheel_design.dart';
import '../../../../shared/widgets/bsheel_widgets.dart';

class AdminAccessDeniedPage extends ConsumerWidget {
  const AdminAccessDeniedPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: BsheelColors.bg,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: BsheelCard(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: BsheelColors.paper,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: BsheelColors.line,
                        width: BsheelBorders.thin,
                      ),
                    ),
                    child: const Icon(
                      Icons.lock_outline,
                      color: BsheelColors.hot,
                      size: 26,
                    ),
                  ),
                  const SizedBox(height: 24),
                  const BsheelEyebrow('Restricted'),
                  const SizedBox(height: 8),
                  const BsheelDisplay(
                    'No {entry.}',
                    baseStyle: BsheelType.displayLg,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    "Your account is signed in but isn't on the admins table. "
                    'Ask a super admin to add your user in Supabase.',
                    textAlign: TextAlign.center,
                    style: BsheelType.bodyMd
                        .copyWith(color: BsheelColors.inkSoft),
                  ),
                  const SizedBox(height: 24),
                  BsheelButton.primary(
                    label: 'SIGN OUT',
                    icon: Icons.logout,
                    onPressed: () =>
                        ref.read(authRepositoryProvider).signOut(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
