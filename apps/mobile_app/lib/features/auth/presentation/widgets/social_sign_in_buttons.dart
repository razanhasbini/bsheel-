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

class SocialSignInButtons extends ConsumerStatefulWidget {
  const SocialSignInButtons({super.key});

  @override
  ConsumerState<SocialSignInButtons> createState() =>
      _SocialSignInButtonsState();
}

class _SocialSignInButtonsState extends ConsumerState<SocialSignInButtons> {
  bool _appleLoading = false;
  bool _googleLoading = false;

  bool get _anyLoading => _appleLoading || _googleLoading;

  Future<void> _signInWithApple() async {
    if (!await _confirmAge()) return;
    setState(() => _appleLoading = true);
    try {
      final response = await ref.read(authRepositoryProvider).signInWithApple();
      _trackLogin(response.user);
      // Router redirect handles navigation to complete-profile or home
    } catch (e) {
      AppLogger.error('[SocialAuth] Apple sign in failed', e);
      if (mounted) _showError(e);
    } finally {
      if (mounted) setState(() => _appleLoading = false);
    }
  }

  Future<void> _signInWithGoogle() async {
    if (!await _confirmAge()) return;
    setState(() => _googleLoading = true);
    try {
      final response =
          await ref.read(authRepositoryProvider).signInWithGoogle();
      _trackLogin(response.user);
      // Router redirect handles navigation to complete-profile or home
    } catch (e) {
      AppLogger.error('[SocialAuth] Google sign in failed', e);
      if (mounted) _showError(e);
    } finally {
      if (mounted) setState(() => _googleLoading = false);
    }
  }

  /// Migration 0142: signup email path has an in-form age checkbox. OAuth
  /// can't pass metadata at sign-in time, so we confirm 13+ in a one-shot
  /// modal BEFORE launching the OAuth web view. If the user says no, the
  /// flow aborts before any account is created.
  Future<bool> _confirmAge() async {
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
    if (confirmed != true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You must be 13 or older to sign in.')),
      );
    }
    return confirmed == true;
  }

  void _trackLogin(AuthUser? user) {
    if (user != null) {
      ref.read(analyticsProvider).identify(user.id,
          username: user.userMetadata['username'] as String?);
      ref.read(analyticsProvider).track('login');
    }
  }

  void _showError(Object e) {
    final msg = e.toString();
    if (msg.contains('cancelled') || msg.contains('canceled')) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(mapAuthError(msg))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final enabled = ref.watch(socialLoginEnabledProvider);
    if (!enabled) return const SizedBox.shrink();

    // The login frame sets a 15pt rhythm and gives the rule 2 of extra
    // margin on each side; the buttons are the frame's outlined white
    // control, which `ArcadeButton.ghost` draws.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 17),
        const _OrRule(),
        const SizedBox(height: 17),
        ArcadeButton(
          label: 'CONTINUE WITH APPLE',
          icon: Icons.apple,
          variant: ArcadeButtonVariant.ghost,
          isLoading: _appleLoading,
          onTap: _anyLoading ? null : _signInWithApple,
        ),
        const SizedBox(height: 15),
        ArcadeButton(
          label: 'CONTINUE WITH GOOGLE',
          icon: Icons.g_mobiledata,
          variant: ArcadeButtonVariant.ghost,
          isLoading: _googleLoading,
          onTap: _anyLoading ? null : _signInWithGoogle,
        ),
      ],
    );
  }
}

/// A 2px lavender rule either side of a mono OR, 12 apart.
class _OrRule extends StatelessWidget {
  const _OrRule();

  @override
  Widget build(BuildContext context) {
    // #C7C0E0 — the lavender the design rules with.
    const rule = QuestColors.textSecondary;
    return Row(
      children: [
        const Expanded(
            child: SizedBox(height: 2, child: ColoredBox(color: rule))),
        const SizedBox(width: 12),
        Text('OR', style: authMonoLabel()),
        const SizedBox(width: 12),
        const Expanded(
            child: SizedBox(height: 2, child: ColoredBox(color: rule))),
      ],
    );
  }
}
