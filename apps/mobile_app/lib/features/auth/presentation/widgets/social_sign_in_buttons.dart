import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app_repositories/app_repositories.dart' show AuthUser;
import 'package:app_core/app_core.dart';
import 'package:shared_ui/shared_ui.dart';
import '../../../../core/providers/app_config_provider.dart';
import '../../../../core/providers/auth_repository_provider.dart';
import '../../../../core/services/analytics_service.dart';
import '../auth_error_mapper.dart';
import 'auth_field.dart';
import 'phone_number_prompt.dart';

/// Migration 0142: the email signup path has an in-form age checkbox. OAuth
/// and phone sign-in can't pass metadata at sign-in time, so we confirm 13+
/// in a one-shot modal BEFORE launching the operator/OAuth web view. If the
/// user says no, the flow aborts before any account is created.
Future<bool> confirmAgeGate(BuildContext context) async {
  final confirmed = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: const Text('AGE CHECK',
          style: TextStyle(fontWeight: FontWeight.w800)),
      content: const Text(
        'Bsheel is for users aged 13 and older. Do you confirm you are 13 '
        'or older?',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text("I'M UNDER 13"),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('YES, 13+'),
        ),
      ],
    ),
  );
  if (confirmed != true && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('You must be 13 or older to sign in.')),
    );
  }
  return confirmed == true;
}

void _showAuthError(BuildContext context, Object e) {
  final msg = e.toString();
  if (msg.contains('cancelled') || msg.contains('canceled')) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(mapAuthError(msg))),
  );
}

void _trackLogin(WidgetRef ref, AuthUser? user) {
  if (user == null) return;
  ref
      .read(analyticsProvider)
      .identify(user.id, username: user.userMetadata['username'] as String?);
  ref.read(analyticsProvider).track('login');
}

/// CAMARA Number Verification, standing on its own so the signup page can
/// lead with it.
///
/// This is the primary way into Bsheel: no password, no code to type — the
/// carrier confirms the number over the cellular connection. It is also the
/// only path that produces a complete account in one step, because every
/// account needs a verified number regardless of how it was created (that
/// number is the device identifier location-based quest submissions are
/// checked against). Accounts made any other way are sent to the
/// verify-phone gate immediately afterwards.
class PhoneAuthButton extends ConsumerStatefulWidget {
  const PhoneAuthButton({
    super.key,
    required this.label,
    this.variant = ArcadeButtonVariant.ghost,
    this.enabled = true,
  });

  final String label;
  final ArcadeButtonVariant variant;

  /// False while a sibling auth button is mid-flight, so two web views
  /// can't be launched at once.
  final bool enabled;

  @override
  ConsumerState<PhoneAuthButton> createState() => _PhoneAuthButtonState();
}

class _PhoneAuthButtonState extends ConsumerState<PhoneAuthButton> {
  bool _loading = false;

  Future<void> _signInWithPhone() async {
    if (!await confirmAgeGate(context)) return;
    if (!mounted) return;
    // V1 verifies a specific claim, so we have to ask what the claim is
    // before the redirect. Backing out of this dialog is a cancel, not a
    // failure — no account is created and nothing is reported as an error.
    final phoneNumber = await promptForPhoneNumber(
      context,
      title: 'Continue with phone',
    );
    if (phoneNumber == null || !mounted) return;
    setState(() => _loading = true);
    try {
      final response =
          await ref.read(authRepositoryProvider).signInWithPhone(phoneNumber);
      _trackLogin(ref, response.user);
      // Router redirect handles navigation to complete-profile or home.
    } catch (e) {
      AppLogger.error('[PhoneAuth] Phone sign in failed', e);
      if (mounted) _showAuthError(context, e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ArcadeButton(
      label: widget.label,
      icon: Icons.phone_iphone,
      variant: widget.variant,
      isLoading: _loading,
      onTap: (!widget.enabled || _loading) ? null : _signInWithPhone,
    );
  }
}

class SocialSignInButtons extends ConsumerStatefulWidget {
  const SocialSignInButtons({super.key, this.includePhone = true});

  /// The signup page hoists the phone button to the top of the page as the
  /// primary call to action and renders this block for Apple/Google only.
  /// The login page keeps all three together.
  final bool includePhone;

  @override
  ConsumerState<SocialSignInButtons> createState() =>
      _SocialSignInButtonsState();
}

class _SocialSignInButtonsState extends ConsumerState<SocialSignInButtons> {
  bool _appleLoading = false;
  bool _googleLoading = false;

  bool get _anyLoading => _appleLoading || _googleLoading;

  Future<void> _signInWithApple() async {
    if (!await confirmAgeGate(context)) return;
    setState(() => _appleLoading = true);
    try {
      final response = await ref.read(authRepositoryProvider).signInWithApple();
      _trackLogin(ref, response.user);
      // Router redirect handles navigation to complete-profile or home
    } catch (e) {
      AppLogger.error('[SocialAuth] Apple sign in failed', e);
      if (mounted) _showAuthError(context, e);
    } finally {
      if (mounted) setState(() => _appleLoading = false);
    }
  }

  Future<void> _signInWithGoogle() async {
    if (!await confirmAgeGate(context)) return;
    setState(() => _googleLoading = true);
    try {
      final response =
          await ref.read(authRepositoryProvider).signInWithGoogle();
      _trackLogin(ref, response.user);
      // Router redirect handles navigation to complete-profile or home
    } catch (e) {
      AppLogger.error('[SocialAuth] Google sign in failed', e);
      if (mounted) _showAuthError(context, e);
    } finally {
      if (mounted) setState(() => _googleLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Apple and Google sit behind a kill switch; phone sign-in never does,
    // because an account without a verified number cannot complete a
    // location-based quest. When social is off and the phone button has
    // been hoisted elsewhere, this block has nothing left to draw — return
    // an empty box rather than a stray OR rule.
    final socialEnabled = ref.watch(socialLoginEnabledProvider);
    if (!socialEnabled && !widget.includePhone) return const SizedBox.shrink();

    // The login frame sets a 15pt rhythm and gives the rule 2 of extra
    // margin on each side; the buttons are the frame's outlined white
    // control, which `ArcadeButton.ghost` draws.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 17),
        const OrRule(),
        const SizedBox(height: 17),
        if (socialEnabled) ...[
          // Apple is hidden in the browser rather than shown broken: the web
          // flow needs a Services ID and registered redirect that this app
          // does not have, so the button could only ever fail. On iOS and
          // Android it uses the native sheet and needs none of that.
          if (!kIsWeb) ...[
            ArcadeButton(
              label: 'CONTINUE WITH APPLE',
              icon: Icons.apple,
              variant: ArcadeButtonVariant.ghost,
              isLoading: _appleLoading,
              onTap: _anyLoading ? null : _signInWithApple,
            ),
            const SizedBox(height: 15),
          ],
          ArcadeButton(
            label: 'CONTINUE WITH GOOGLE',
            icon: Icons.g_mobiledata,
            variant: ArcadeButtonVariant.ghost,
            isLoading: _googleLoading,
            onTap: _anyLoading ? null : _signInWithGoogle,
          ),
        ],
        if (widget.includePhone) ...[
          if (socialEnabled) const SizedBox(height: 15),
          PhoneAuthButton(
            label: 'CONTINUE WITH PHONE NUMBER',
            enabled: !_anyLoading,
          ),
        ],
      ],
    );
  }
}

/// A 2px lavender rule either side of a mono label, 12 apart.
class OrRule extends StatelessWidget {
  const OrRule({super.key, this.label = 'OR'});

  final String label;

  @override
  Widget build(BuildContext context) {
    // #C7C0E0 — the lavender the design rules with.
    const rule = QuestColors.textSecondary;
    return Row(
      children: [
        const Expanded(
            child: SizedBox(height: 2, child: ColoredBox(color: rule))),
        const SizedBox(width: 12),
        Text(label, style: authMonoLabel()),
        const SizedBox(width: 12),
        const Expanded(
            child: SizedBox(height: 2, child: ColoredBox(color: rule))),
      ],
    );
  }
}
