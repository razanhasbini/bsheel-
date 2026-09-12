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
/// 15pt rhythm: `LOG IN` in Syne 800/42, then **LOG IN WITH PHONE NUMBER**
/// as the violet primary, an OR USE EMAIL rule, the EMAIL and PASSWORD
/// fields with a right-aligned FORGOT PASSWORD?, the LOG IN button, an OR
/// rule, LOG IN WITH APPLE / GOOGLE, and a centred sign-up line.
///
/// Phone leads because a CAMARA-verified number is the one credential no
/// account can be without — it is the device identifier every location-based
/// submission is checked against. Email and password are the optional extra,
/// and the page is ordered to say so.
///
/// Phone is the PRIMARY action and sits at the top, above Apple and Google.
/// The email/password form is below them, behind a disclosure, because it is
/// the path fewest accounts can even use: a phone account has no password,
/// and its credential is the carrier check rather than anything typed. A
/// form asking for an email first told most arrivals to produce something
/// they never set.
///
/// The form is not removed — accounts made with email before phone existed
/// still sign in with it, and so do the seeded test accounts — it is
/// demoted. One tap opens it, and it stays open once opened.
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

  /// The email/password form starts closed and never closes again.
  ///
  /// Opened on demand rather than shown by default, because the page's job
  /// is to get somebody signed in by the means they actually have — and for
  /// most accounts that is the carrier check above. Once opened it stays
  /// open: collapsing a form somebody is typing into would lose the typing.
  bool _emailFormOpen = false;
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
                        // Phone first, and on its own: the carrier check is
                        // the credential every account has.
                        const PhoneAuthButton(
                          label: 'LOG IN WITH PHONE',
                          variant: ArcadeButtonVariant.primary,
                        ),
                        // Apple and Google next. `includePhone: false` —
                        // the button above is the phone path, and two of
                        // them on one page is a choice nobody can make.
                        const SocialSignInButtons(
                          labelPrefix: 'LOG IN WITH',
                          includePhone: false,
                        ),
                        const SizedBox(height: 6),
                        if (!_emailFormOpen)
                          _MonoLink(
                            label: 'LOG IN WITH EMAIL INSTEAD',
                            alignment: Alignment.center,
                            onTap: () =>
                                setState(() => _emailFormOpen = true),
                          ),
                        if (_emailFormOpen) ...[
                        const SizedBox(height: 9),
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
                          // Ghost, not the frame's primary: the violet
                          // button on this page is the phone one at the top,
                          // and two primaries would say they are equals.
                          label: _isLoading ? l.loading : l.login,
                          variant: ArcadeButtonVariant.ghost,
                          isLoading: _isLoading,
                          onTap: _isLoading ? null : _login,
                        ),
                        ],
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
