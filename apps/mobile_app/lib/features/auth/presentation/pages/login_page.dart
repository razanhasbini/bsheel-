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
import '../widgets/auth_field.dart';
import '../widgets/social_sign_in_buttons.dart';
import '../../../../l10n/app_localizations.dart';

/// Log in, drawn from `export/mobile/16-login.jpg`.
///
/// Cream ground, 22 of side padding, everything vertically centred with a
/// 15pt rhythm: `LOG IN` in Syne 800/42, two labelled fields, a right-aligned
/// FORGOT PASSWORD?, the violet primary, an OR rule, the social buttons, and
/// a centred sign-up line.
///
/// There is no card behind the fields and no wordmark above the title — both
/// were inventions of the previous pass. The fields carry no shadow and no
/// prefix icons.
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
    final l = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: QuestColors.bg(context),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Center(
                child: Padding(
                  // 22 of side padding, 24 top and bottom.
                  padding: const EdgeInsets.fromLTRB(22, 24, 22, 24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          l.login.toUpperCase(),
                          style: QuestTypography.osDisplayLarge.copyWith(
                            fontSize: 42,
                            height: 0.95,
                            // -0.04em at 42px.
                            letterSpacing: -1.68,
                          ),
                        ),
                        const SizedBox(height: 15),
                        AuthField(
                          controller: _emailController,
                          focusNode: _emailFocus,
                          label: l.email,
                          hint: l.enterEmail,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          errorText: _emailError,
                          autocorrect: false,
                          autofillHints: const [AutofillHints.username],
                          onSubmitted: (_) => _passwordFocus.requestFocus(),
                        ),
                        const SizedBox(height: 15),
                        AuthField(
                          controller: _passwordController,
                          focusNode: _passwordFocus,
                          label: l.password,
                          hint: l.enterPassword,
                          obscureText: true,
                          textInputAction: TextInputAction.done,
                          errorText: _passwordError,
                          autocorrect: false,
                          autofillHints: const [AutofillHints.password],
                          onSubmitted: (_) => _login(),
                        ),
                        // Offered only after a login attempt failed with
                        // "email not confirmed" — one tap re-sends the
                        // signup confirmation email.
                        // No 15 either side of these: `_MonoLink` is a 45pt
                        // box around a 15pt label, which is exactly the
                        // frame's 15 + label + 15. Padding it as well would
                        // push the primary button 29 down the screen.
                        if (_offerResendConfirmation)
                          _MonoLink(
                            label: 'RESEND CONFIRMATION EMAIL',
                            alignment: Alignment.centerLeft,
                            onTap: _resendConfirmation,
                          ),
                        _MonoLink(
                          label: l.forgotPassword,
                          alignment: Alignment.centerRight,
                          onTap: () =>
                              context.pushNamed(RouteNames.forgotPassword),
                        ),
                        ArcadeButton(
                          // The frame's primary: violet ground, white label,
                          // 56pt, r14, 5px shadow. No icon.
                          label: _isLoading ? l.loading : l.login,
                          isLoading: _isLoading,
                          onTap: _isLoading ? null : _login,
                        ),
                        // SocialSignInButtons renders the OR rule itself
                        // (and nothing at all when social login is off).
                        const SocialSignInButtons(),
                        // 6 + the 44pt box's 22 of half-height puts the
                        // line's baseline where the frame's 15 + 4 margin
                        // does, without the hit target moving it.
                        const SizedBox(height: 6),
                        _SignUpLine(
                          prompt: l.noAccountYet,
                          action: l.signup,
                          onTap: () => context.goNamed(RouteNames.signup),
                        ),
                      ],
                    ),
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

/// A mono link — FORGOT PASSWORD? and the resend-confirmation action.
///
/// The paint is an 11px label. The box is 45 tall, which clears the 44pt
/// floor *and* stands in for the frame's 15 gap + 15pt label + 15 gap, so
/// the label lands on the same baseline it does in the frame.
class _MonoLink extends StatelessWidget {
  const _MonoLink({
    required this.label,
    required this.alignment,
    required this.onTap,
  });

  final String label;
  final AlignmentGeometry alignment;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 45),
        child: Align(
          alignment: alignment,
          child: Text(
            label.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: authMonoLabel(fontSize: 11, letterSpacingEm: 0.08)
                .copyWith(color: QuestColors.osPrimary),
          ),
        ),
      ),
    );
  }
}

/// "No account yet?  SIGN UP" — 14px sentence plus a Syne 700 violet action,
/// 7 apart, centred, with one 44pt hit box around both.
class _SignUpLine extends StatelessWidget {
  const _SignUpLine({
    required this.prompt,
    required this.action,
    required this.onTap,
  });

  final String prompt;
  final String action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: ConstrainedBox(
        constraints:
            const BoxConstraints(minHeight: QuestSpacing.minTouchTarget),
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  prompt,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: QuestTypography.osBodyMedium.copyWith(
                    color: QuestColors.osTextSecondary,
                  ),
                ),
              ),
              const SizedBox(width: 7),
              Text(
                action.toUpperCase(),
                maxLines: 1,
                style: QuestTypography.osHeadlineSmall.copyWith(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  fontVariations: const [FontVariation('wght', 700)],
                  letterSpacing: 0,
                  color: QuestColors.osPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
