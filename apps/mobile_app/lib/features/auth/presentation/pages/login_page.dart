import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:app_core/app_core.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../../core/router/route_names.dart';
import '../../../../core/providers/auth_repository_provider.dart';
import '../../../../core/providers/auth_session_provider.dart';
import '../../../../core/security/secure_screen.dart';
import '../../../../core/services/analytics_service.dart';
import '../auth_error_mapper.dart';
import '../login_credentials.dart';
import '../widgets/social_sign_in_buttons.dart';
import '../../../../l10n/app_localizations.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

// H9 (2026-05-17): block screenshots while a password is on screen.
class _LoginPageState extends ConsumerState<LoginPage> with SecureScreenMixin {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();

  bool _isLoading = false;
  String? _emailError;
  String? _passwordError;

  /// Set when login failed because the email is unconfirmed, so the UI
  /// can offer a one-tap "resend confirmation email" action.
  bool _offerResendConfirmation = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final identifier = _emailController.text.trim();
    final password = _passwordController.text;
    final emailErr = LoginCredentials.validateIdentifier(identifier);
    final passwordErr = password.isEmpty
        ? AppLocalizations.of(context)!.pleaseEnterPassword
        : null;

    setState(() {
      _emailError = emailErr;
      _passwordError = passwordErr;
    });
    if (emailErr != null || passwordErr != null) return;

    setState(() {
      _isLoading = true;
      _offerResendConfirmation = false;
    });
    final email = LoginCredentials.normalizeIdentifier(identifier);
    try {
      await ref.read(authRepositoryProvider).signInWithEmail(email, password);
      final user = ref.read(authSessionProvider);
      if (user != null) {
        ref.read(analyticsProvider).identify(
              user.id,
              username: user.userMetadata['username'] as String?,
            );
        ref.read(analyticsProvider).track('login');
      }
    } catch (e) {
      AppLogger.error('[Login] Login failed', e);
      if (mounted) {
        final raw = e.toString().toLowerCase();
        setState(() {
          _passwordError = mapAuthError(e.toString());
          _offerResendConfirmation = raw.contains('email_not_confirmed') ||
              raw.contains('email not confirmed');
        });
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _resendConfirmation() async {
    final email = LoginCredentials.normalizeIdentifier(_emailController.text);
    if (LoginCredentials.validateIdentifier(email) != null) return;
    setState(() => _offerResendConfirmation = false);
    try {
      await ref.read(authRepositoryProvider).resendSignupConfirmation(email);
    } catch (e) {
      // Deliberately swallowed into the same message — revealing whether
      // the resend "worked" per-address would enable email enumeration.
      AppLogger.error('[Login] Resend confirmation failed', e);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(const SnackBar(
        content: Text(
            'If that address has an unconfirmed account, a new confirmation '
            'email is on its way.'),
      ));
  }

  @override
  Widget build(BuildContext context) {
    final ink = QuestColors.text(context);
    final l = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: QuestColors.bg(context),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 32, 20, 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Pure-typographic wordmark. FittedBox auto-scales the
                  // glyphs so the name always renders on a single line —
                  // small iPhones (SE-class) get a smaller cap height,
                  // Pro Max widths get more presence — without any text
                  // ever wrapping or the screen having to reflow.
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.center,
                    child: Text(
                      'BSHEEL',
                      maxLines: 1,
                      style: QuestTypography.displayLarge.copyWith(
                        color: ink,
                        fontSize: 44,
                        letterSpacing: 2.5,
                        height: 1,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // ── Auth card ─────────────────────────────────────
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
                          textInputAction: TextInputAction.next,
                          prefixIcon: Icons.alternate_email_rounded,
                          errorText: _emailError,
                          autocorrect: false,
                          autofillHints: const [AutofillHints.username],
                          onSubmitted: (_) => _passwordFocus.requestFocus(),
                        ),
                        const SizedBox(height: 14),
                        ArcadeTextField(
                          controller: _passwordController,
                          focusNode: _passwordFocus,
                          label: l.password,
                          hint: l.enterPassword,
                          obscureText: true,
                          textInputAction: TextInputAction.done,
                          prefixIcon: Icons.lock_outline_rounded,
                          errorText: _passwordError,
                          autofillHints: const [AutofillHints.password],
                          onSubmitted: (_) => _login(),
                        ),
                        // Offered only after a login attempt failed with
                        // "email not confirmed" — one tap re-sends the
                        // signup confirmation email.
                        if (_offerResendConfirmation) ...[
                          const SizedBox(height: 10),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: GestureDetector(
                              onTap: _resendConfirmation,
                              behavior: HitTestBehavior.opaque,
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 4),
                                child: Text(
                                  'RESEND CONFIRMATION EMAIL',
                                  style: QuestTypography.labelSmall.copyWith(
                                    color: QuestColors.osPrimary,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 10),
                        Align(
                          alignment: Alignment.centerRight,
                          child: GestureDetector(
                            onTap: () =>
                                context.pushNamed(RouteNames.forgotPassword),
                            behavior: HitTestBehavior.opaque,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Text(
                                l.forgotPassword,
                                style: QuestTypography.bodySmall.copyWith(
                                  color: QuestColors.osPrimary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        ArcadeButton(
                          // No icon in the render, and the sheet's button is
                          // 56pt (medium), not 60. The variant is left at the
                          // default primary, which is violet with white text.
                          label: _isLoading ? l.loading : l.login,
                          isLoading: _isLoading,
                          onTap: _isLoading ? null : _login,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),

                  // SocialSignInButtons renders its own 'OR' divider
                  // internally (only when social login is enabled).
                  const SocialSignInButtons(),
                  const SizedBox(height: 20),

                  // ── Sign-up link ──────────────────────────────────
                  Center(
                    child: GestureDetector(
                      onTap: () => context.goNamed(RouteNames.signup),
                      behavior: HitTestBehavior.opaque,
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text.rich(
                          TextSpan(
                            style: QuestTypography.bodyMedium.copyWith(
                              color: ink.withAlpha(QuestColors.alphaInkMuted),
                            ),
                            children: [
                              TextSpan(text: '${l.noAccountYet} '),
                              TextSpan(
                                text: '${l.signup} →',
                                style: const TextStyle(
                                  color: QuestColors.osPrimary,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
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
