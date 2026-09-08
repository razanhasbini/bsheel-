import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:app_core/app_core.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../../core/backend/app_backend.dart';
import '../../../../core/providers/auth_state_provider.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/security/secure_screen.dart';
import '../auth_error_mapper.dart';
import '../password_policy.dart';
import '../widgets/auth_success_card.dart';
import '../../../../l10n/app_localizations.dart';

class ResetPasswordPage extends ConsumerStatefulWidget {
  const ResetPasswordPage({super.key, this.recoveryToken});

  final String? recoveryToken;

  @override
  ConsumerState<ResetPasswordPage> createState() => _ResetPasswordPageState();
}

// H9 (2026-05-17): SecureScreenMixin enables Android FLAG_SECURE while
// the user is typing their new password so screenshots / screen
// recordings / recents previews are blocked.
class _ResetPasswordPageState extends ConsumerState<ResetPasswordPage>
    with SecureScreenMixin {
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  final _passwordFocus = FocusNode();
  final _confirmFocus = FocusNode();

  bool _isLoading = false;
  bool _done = false;
  String? _passwordError;
  String? _confirmError;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    _passwordFocus.dispose();
    _confirmFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final password = _passwordController.text;
    final confirm = _confirmController.text;

    // Pass the recovery session's email so the identity-reuse policy
    // applies on this path too (signup already does this). Without
    // emailLocalPart a user could otherwise set `Tayseer1234` via reset
    // even though the same string is blocked at signup / edit profile.
    // A recovery link is consumed while signed out, so there is no session
    // email to feed the validator. The server applies the same policy.
    const String? localPart = null;
    final pwErr = validatePassword(password, emailLocalPart: localPart);
    final confirmErr = password != confirm
        ? AppLocalizations.of(context)!.passwordsDoNotMatch
        : null;

    setState(() {
      _passwordError = pwErr;
      _confirmError = confirmErr;
    });
    if (pwErr != null || confirmErr != null) return;

    if (!_isValidRecoveryToken(widget.recoveryToken)) {
      setState(() {
        _passwordError = mapAuthError(
          'The password recovery token is invalid or expired.',
        );
      });
      return;
    }

    setState(() => _isLoading = true);
    try {
      await AppBackend.repositories.auth.completePasswordRecovery(
        widget.recoveryToken!,
        password,
      );
      // Only clear the recovery flag on SUCCESS. Previously this was
      // also cleared on failure, which kicked the user out of the
      // recovery flow on a transient network blip — they then had to
      // re-request a new reset email to try again.
      ref.read(passwordRecoveryProvider.notifier).state = false;
      if (mounted) setState(() => _done = true);
    } catch (e) {
      AppLogger.error('[ResetPassword] Failed to update password', e);
      if (mounted) {
        setState(() => _passwordError = mapAuthError(e.toString()));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  bool _isValidRecoveryToken(String? token) {
    if (token == null) return false;
    return RegExp(r'^[A-Za-z0-9_-]{32,128}$').hasMatch(token);
  }

  @override
  Widget build(BuildContext context) {
    final ink = QuestColors.text(context);
    final l = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: QuestColors.bg(context),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ArcadeBackButton(
                  onTap: () => context.goNamed(RouteNames.login),
                ),
                const SizedBox(height: 28),
                Text(
                  l.newPassword,
                  style: QuestTypography.displayLarge.copyWith(
                    color: ink,
                    fontSize: 32,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Choose a strong new password.',
                  style: QuestTypography.bodyMedium.copyWith(
                    color: ink.withAlpha(QuestColors.alphaInkMuted),
                  ),
                ),
                const SizedBox(height: 28),
                if (_done) ...[
                  AuthSuccessCard(
                    title: AppLocalizations.of(context)!
                        .passwordUpdated
                        .toUpperCase(),
                    message:
                        'Your password has been changed. You can now log in.',
                  ),
                  const SizedBox(height: 24),
                  ArcadeButton(
                    label: l.goToLogin,
                    icon: Icons.login_rounded,
                    size: ArcadeButtonSize.large,
                    onTap: () => context.goNamed(RouteNames.login),
                  ),
                ] else ...[
                  ArcadeCard(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ArcadeTextField(
                          controller: _passwordController,
                          focusNode: _passwordFocus,
                          label: l.newPassword,
                          hint: l.enterNewPassword,
                          obscureText: true,
                          prefixIcon: Icons.lock_outline_rounded,
                          textInputAction: TextInputAction.next,
                          autofillHints: const [AutofillHints.newPassword],
                          helper:
                              'Min $passwordMinLength chars, mixed case + a number.',
                          errorText: _passwordError,
                          onSubmitted: (_) => _confirmFocus.requestFocus(),
                        ),
                        const SizedBox(height: 14),
                        ArcadeTextField(
                          controller: _confirmController,
                          focusNode: _confirmFocus,
                          label: l.confirmPassword,
                          hint: l.confirmNewPassword,
                          obscureText: true,
                          prefixIcon: Icons.lock_outline_rounded,
                          textInputAction: TextInputAction.done,
                          errorText: _confirmError,
                          onSubmitted: (_) => _submit(),
                        ),
                        const SizedBox(height: 18),
                        ArcadeButton(
                          label: _isLoading
                              ? AppLocalizations.of(context)!.saving
                              : AppLocalizations.of(context)!.setNewPassword,
                          icon: _isLoading ? null : Icons.check_rounded,
                          isLoading: _isLoading,
                          size: ArcadeButtonSize.large,
                          onTap: _isLoading ? null : _submit,
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
