import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app_repositories/app_repositories.dart' show AuthUser;
import 'package:app_core/app_core.dart';
import '../../../../core/providers/app_config_provider.dart';
import '../../../../core/providers/auth_repository_provider.dart';
import '../../../../core/services/analytics_service.dart';
import '../auth_error_mapper.dart';

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

    return Column(
      children: [
        Row(
          children: [
            const Expanded(child: Divider(color: QuestColors.osBorder)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: QuestSpacing.md),
              child: Text(
                'OR',
                style: QuestTypography.bodySmall
                    .copyWith(color: QuestColors.osTextMuted),
              ),
            ),
            const Expanded(child: Divider(color: QuestColors.osBorder)),
          ],
        ),
        const SizedBox(height: QuestSpacing.lg),
        _SocialButton(
          onPressed: _anyLoading ? null : _signInWithApple,
          isLoading: _appleLoading,
          icon: Icons.apple,
          label: 'CONTINUE WITH APPLE',
        ),
        const SizedBox(height: QuestSpacing.md),
        _SocialButton(
          onPressed: _anyLoading ? null : _signInWithGoogle,
          isLoading: _googleLoading,
          icon: Icons.g_mobiledata,
          label: 'CONTINUE WITH GOOGLE',
          iconSize: 28,
        ),
      ],
    );
  }
}

class _SocialButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final bool isLoading;
  final IconData icon;
  final String label;
  final double iconSize;

  const _SocialButton({
    required this.onPressed,
    required this.isLoading,
    required this.icon,
    required this.label,
    this.iconSize = 22,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          backgroundColor: QuestColors.osCard,
          side: const BorderSide(
            color: QuestColors.osBorderStrong,
            width: QuestSpacing.cardBorderWidth,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(QuestSpacing.radiusMd),
          ),
        ),
        child: isLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: QuestColors.osTextPrimary,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, color: QuestColors.osTextPrimary, size: iconSize),
                  const SizedBox(width: QuestSpacing.sm),
                  Text(
                    label,
                    style: QuestTypography.labelSmall
                        .copyWith(color: QuestColors.osTextPrimary),
                  ),
                ],
              ),
      ),
    );
  }
}
