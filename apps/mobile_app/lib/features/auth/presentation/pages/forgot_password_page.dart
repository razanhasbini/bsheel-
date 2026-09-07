import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:app_core/app_core.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../../core/providers/auth_repository_provider.dart';
import '../../../../core/router/route_names.dart';
import '../login_credentials.dart';
import '../widgets/auth_success_card.dart';
import '../../../../l10n/app_localizations.dart';

class ForgotPasswordPage extends ConsumerStatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  ConsumerState<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends ConsumerState<ForgotPasswordPage> {
  final _emailController = TextEditingController();
  final _emailFocus = FocusNode();
  bool _isLoading = false;
  bool _sent = false;
  String? _emailError;

  @override
  void dispose() {
    _emailController.dispose();
    _emailFocus.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final email = _emailController.text.trim();
    final l = AppLocalizations.of(context)!;
    String? err;
    if (email.isEmpty) {
      err = l.emailRequired;
    } else if (!emailPattern.hasMatch(email)) {
      err = l.emailInvalid;
    }
    setState(() => _emailError = err);
    if (err != null) return;

    setState(() => _isLoading = true);
    try {
      await ref.read(authRepositoryProvider).resetPassword(email);
      if (mounted) setState(() => _sent = true);
    } catch (e) {
      AppLogger.error('[ForgotPassword] Reset email request failed', e);
      // Always show success to avoid email enumeration
      if (mounted) setState(() => _sent = true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
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
                  onTap: () => context.canPop()
                      ? context.pop()
                      : context.goNamed(RouteNames.login),
                ),
                const SizedBox(height: 28),
                Text(
                  l.resetPassword,
                  style: QuestTypography.displayLarge.copyWith(
                    color: ink,
                    fontSize: 32,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  "Enter your email and we'll send a reset link.",
                  style: QuestTypography.bodyMedium.copyWith(
                    color: ink.withAlpha(QuestColors.alphaInkMuted),
                  ),
                ),
                const SizedBox(height: 28),
                if (_sent) ...[
                  const AuthSuccessCard(
                    title: 'EMAIL SENT',
                    message:
                        'Check your inbox for a password reset link. It may take a minute.',
                  ),
                  const SizedBox(height: 24),
                  ArcadeButton(
                    label: l.backToLogin,
                    icon: Icons.arrow_back_rounded,
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
                          controller: _emailController,
                          focusNode: _emailFocus,
                          label: l.email,
                          hint: l.enterEmail,
                          keyboardType: TextInputType.emailAddress,
                          prefixIcon: Icons.alternate_email_rounded,
                          textInputAction: TextInputAction.done,
                          autocorrect: false,
                          autofillHints: const [AutofillHints.email],
                          errorText: _emailError,
                          onSubmitted: (_) => _send(),
                        ),
                        const SizedBox(height: 18),
                        ArcadeButton(
                          label: _isLoading ? AppLocalizations.of(context)!.sending : AppLocalizations.of(context)!.sendResetLink,
                          icon: _isLoading ? null : Icons.send_rounded,
                          isLoading: _isLoading,
                          size: ArcadeButtonSize.large,
                          onTap: _isLoading ? null : _send,
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
