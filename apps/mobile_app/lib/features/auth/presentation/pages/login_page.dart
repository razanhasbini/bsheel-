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
import '../pending_auth_error.dart';
import '../widgets/auth_field.dart';
import '../widgets/social_sign_in_buttons.dart';
import '../../../../l10n/app_localizations.dart';

/// Log in, drawn from `export/mobile/16-login.jpg`.
///
/// Cream ground, 22 of side padding, everything vertically centred with a
/// 15pt rhythm: `LOG IN` in Syne 800/42, EMAIL and PASSWORD fields, a
/// right-aligned FORGOT PASSWORD?, the violet primary, an OR rule, then
/// LOG IN WITH APPLE / GOOGLE / PHONE NUMBER, and a centred sign-up line.
///
/// Email + password on top, not phone + password: a phone account's
/// credential is the carrier check, which is the phone button below — the
/// password form is for the accounts that have one, and those are keyed by
/// email.
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

  /// True once the pending-error dialog for this failure has been raised,
  /// so a rebuild does not stack a second copy on top of the first.
  bool _showingPendingError = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  /// Raises the failure the phone-sign-in callback parked on its way here.
  ///
  /// It has to be shown from this page rather than from the callback route:
  /// that route navigates away in the same frame it discovers the error, so
  /// anything it shows is attached to a widget being disposed and never
  /// appears — a refused number used to bounce back to this screen in total
  /// silence, which reads as the button doing nothing.
  ///
  /// A dialog rather than a snackbar, because a sign-in that did not happen
  /// is not something to glance at and miss.
  void _raisePendingError(String code) {
    if (_showingPendingError) return;
    _showingPendingError = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: QuestColors.cardBg(context),
          title: Text(
            'SIGN-IN FAILED',
            style: QuestTypography.osHeadlineSmall.copyWith(
              color: QuestColors.text(context),
            ),
          ),
          content: Text(
            mapAuthError(code),
            style: QuestTypography.osBodyMedium.copyWith(
              color: QuestColors.textDim(context),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(
                'OK',
                style: QuestTypography.osHeadlineSmall.copyWith(
                  fontSize: 14,
                  color: QuestColors.osPrimary,
                ),
              ),
            ),
          ],
        ),
      );
      if (!mounted) return;
      _showingPendingError = false;
      // Cleared only after it has been seen and dismissed. Clearing on
      // display would lose the message to any rebuild that raced it.
      ref.read(pendingAuthErrorProvider.notifier).state = null;
    });
  }

  Future<void> _login() async {
    final email = LoginCredentials.normalizeIdentifier(_emailController.text);
    final password = _passwordController.text;
    final emailErr = LoginCredentials.validateIdentifier(_emailController.text);
    final passwordErr = password.isEmpty
        ? AppLocalizations.of(context)!.pleaseEnterPassword
        : null;

    setState(() {
      _emailError = emailErr;
      _passwordError = passwordErr;
    });
    if (emailErr != null || passwordErr != null) return;

    setState(() => _isLoading = true);
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
        // INVALID_CREDENTIALS is deliberately one message for "no such
        // account" and "wrong password" alike — the server will not say
        // which, so neither does the form.
        setState(() => _passwordError = mapAuthError(e.toString()));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    // A failure the phone-sign-in callback route parked for us on its way
    // here, because it could not show one itself.
    final parked = ref.watch(pendingAuthErrorProvider);
    if (parked != null) _raisePendingError(parked);

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
                          autofillHints: const [AutofillHints.email],
                          onChanged: (_) {
                            if (_emailError != null) {
                              setState(() => _emailError = null);
                            }
                          },
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
                        // No 15 either side: `_MonoLink` is a 45pt box
                        // around a 15pt label, which is exactly the frame's
                        // 15 + label + 15. Padding it as well would push the
                        // primary button 29 down the screen.
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
                        // (and only the phone button when social login is
                        // off — that one never hides).
                        const SocialSignInButtons(labelPrefix: 'LOG IN WITH'),
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
