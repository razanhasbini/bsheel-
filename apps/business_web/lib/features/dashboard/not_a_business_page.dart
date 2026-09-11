import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../core/providers/session_providers.dart';

/// Where a signed-in user who is not a business member lands.
///
/// Deliberately a page rather than a bounce back to login. Their
/// credentials are valid, so bouncing would loop them through a form that
/// keeps accepting them and keeps refusing to show anything, with nothing
/// explaining why. Nothing here leaks whether any particular business
/// exists — the API answers a non-member with a 404 for exactly that
/// reason.
class NotABusinessPage extends ConsumerWidget {
  const NotABusinessPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: QuestColors.bg(context),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ArcadeCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('NO DASHBOARD ON THIS ACCOUNT',
                      style: QuestTypography.osLabelSmall
                          .copyWith(color: QuestColors.textDim(context))),
                  const SizedBox(height: 8),
                  Text(
                      'You are signed in, but this account is not a member '
                      'of a Bsheel business.',
                      style: QuestTypography.osBodyMedium),
                  const SizedBox(height: 8),
                  Text(
                    'If your business already exists, an owner can add you '
                    'from their dashboard. Otherwise talk to Bsheel about '
                    'setting one up.',
                    style: QuestTypography.osBodySmall
                        .copyWith(color: QuestColors.textDim(context)),
                  ),
                  const SizedBox(height: 20),
                  ArcadeButton(
                    label: 'SIGN OUT',
                    variant: ArcadeButtonVariant.secondary,
                    onTap: () async {
                      await ref.read(authRepositoryProvider).signOut();
                      ref.read(sessionProvider.notifier).state = null;
                    },
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
