import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app_core/app_core.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../../core/providers/auth_repository_provider.dart';
import '../../../../core/services/sign_out_service.dart';
import '../auth_error_mapper.dart';
import '../widgets/phone_number_prompt.dart';

/// Mandatory gate shown once a user is signed in but has no CAMARA-verified
/// phone number on file. Reachable from any sign-up path (password,
/// Google, Apple, or phone itself — an account created via phone already
/// has one and never lands here). The verified number is what location-
/// based quest submissions use to identify the device with CAMARA, so
/// every account needs one before reaching the rest of the app.
///
/// Router-enforced and unconditional: route_guards.dart redirects here
/// whenever phoneVerifiedProvider is false, and away again the instant
/// linkPhone() succeeds (it re-issues a token carrying phoneVerified: true,
/// which flips the gate). There is deliberately no switch that disables
/// this — see migration 0031.
class VerifyPhonePage extends ConsumerStatefulWidget {
  const VerifyPhonePage({super.key});

  @override
  ConsumerState<VerifyPhonePage> createState() => _VerifyPhonePageState();
}

class _VerifyPhonePageState extends ConsumerState<VerifyPhonePage> {
  bool _loading = false;
  String? _error;

  Future<void> _verify() async {
    final phoneNumber = await promptForPhoneNumber(
      context,
      title: 'Verify your number',
    );
    if (phoneNumber == null || !mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider).linkPhone(phoneNumber);
      // Router redirect handles navigation once phoneVerifiedProvider flips.
    } catch (e) {
      AppLogger.error('[VerifyPhone] Phone verification failed', e);
      if (mounted) setState(() => _error = mapAuthError(e.toString()));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ink = QuestColors.text(context);

    return Scaffold(
      backgroundColor: QuestColors.bg(context),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 24, 22, 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(Icons.phone_iphone, size: 48, color: ink),
                  const SizedBox(height: 18),
                  Text(
                    'VERIFY YOUR PHONE',
                    style: QuestTypography.osDisplayLarge.copyWith(
                      fontSize: 32,
                      height: 0.95,
                      letterSpacing: -1.28,
                      color: ink,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Bsheel confirms location-based quests through your '
                    'network, not GPS alone. That needs a phone number '
                    'verified with your carrier — one tap, no code to type.',
                    style: QuestTypography.osBodyMedium.copyWith(
                      color: QuestColors.osTextSecondary,
                    ),
                  ),
                  const SizedBox(height: 28),
                  if (_error != null) ...[
                    Text(
                      _error!,
                      style: QuestTypography.osBodyMedium
                          .copyWith(color: QuestColors.osRedText),
                    ),
                    const SizedBox(height: 12),
                  ],
                  ArcadeButton(
                    label: 'VERIFY PHONE NUMBER',
                    icon: Icons.phone_iphone,
                    isLoading: _loading,
                    onTap: _loading ? null : _verify,
                  ),
                  const SizedBox(height: 18),
                  TextButton(
                    onPressed: _loading ? null : () => signOutAndCleanup(ref),
                    child: Text(
                      'SIGN OUT',
                      style: QuestTypography.osBodyMedium.copyWith(
                        color: QuestColors.osTextSecondary,
                      ),
                    ),
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
