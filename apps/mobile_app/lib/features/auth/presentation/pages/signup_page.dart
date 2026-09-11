import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:app_core/app_core.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../../core/router/route_names.dart';
import '../../../../core/providers/auth_repository_provider.dart';
import '../../../../core/security/secure_screen.dart';
import '../../../../core/services/analytics_service.dart';
import '../auth_error_mapper.dart';
import '../login_credentials.dart';
import '../password_policy.dart';
import '../widgets/auth_field.dart';
import '../widgets/social_sign_in_buttons.dart';
import '../../../../l10n/app_localizations.dart';

/// Create account — phone first.
///
/// A 46pt back button, `CREATE ACCOUNT` in Syne 800/36, then two fields on
/// the 14pt rhythm: phone number (starred) and email (not), the age
/// checkbox, the jade positive button, Apple/Google, and the legal line.
///
/// The number is the account. It is the credential CAMARA verifies and the
/// device identifier location quests are checked against, so it is the only
/// required field; the email is a contact and recovery address the user may
/// skip. That distinction is carried by the asterisk on the label — the
/// screen does not explain itself in prose.
class SignupPage extends ConsumerStatefulWidget {
  const SignupPage({super.key});

  @override
  ConsumerState<SignupPage> createState() => _SignupPageState();
}

class _SignupPageState extends ConsumerState<SignupPage>
    with SecureScreenMixin {
  final _phoneController = TextEditingController(text: '+');
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  final _phoneFocus = FocusNode();
  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();
  final _confirmFocus = FocusNode();
  final _termsTap = TapGestureRecognizer();
  final _privacyTap = TapGestureRecognizer();

  bool _isLoading = false;
  // Low/Info (2026-05-17): age confirmation. Required true before submit so
  // we have a contemporaneous record that the user attested to being 13+.
  bool _ageConfirmed = false;
  String? _phoneError;
  String? _emailError;
  String? _passwordError;
  String? _confirmError;
  String? _ageError;

  @override
  void initState() {
    super.initState();
    _termsTap.onTap = () => context.pushNamed(RouteNames.terms);
    _privacyTap.onTap = () => context.pushNamed(RouteNames.privacyPolicy);
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    _phoneFocus.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    _confirmFocus.dispose();
    _termsTap.dispose();
    _privacyTap.dispose();
    super.dispose();
  }

  Future<void> _createAccount() async {
    // Strip the spaces and dashes people naturally type; anything left that
    // breaks E.164 is a real mistake worth surfacing.
    final phone = _phoneController.text.replaceAll(RegExp(r'[\s\-()]'), '');
    final email = _emailController.text.trim().toLowerCase();
    final password = _passwordController.text;

    setState(() {
      _phoneError = e164Pattern.hasMatch(phone)
          ? null
          : 'Use international format, e.g. +96170123456';
      _emailError = email.isEmpty || emailPattern.hasMatch(email)
          ? null
          : 'That email does not look right';
      // The same policy the reset-password form applies. The number gets the
      // account in; the password is what gets it back after a new handset,
      // so it is not optional and it is not exempt from the rules.
      _passwordError = password.isEmpty
          ? 'Password is required'
          : validatePassword(
              password,
              emailLocalPart: email.isEmpty ? null : email.split('@').first,
            );
      _confirmError = _confirmController.text == password
          ? null
          : 'Those two do not match.';
      _ageError = _ageConfirmed ? null : 'You must be 13 or older to sign up.';
    });
    if (_phoneError != null ||
        _emailError != null ||
        _passwordError != null ||
        _confirmError != null ||
        _ageError != null) {
      return;
    }

    setState(() => _isLoading = true);
    try {
      final response =
          await ref.read(authRepositoryProvider).signInWithPhone(phone,
              email: email.isEmpty ? null : email,
              password: password,
              // The form's own checkbox, validated above — so a phone signup
              // never gets asked a second time after landing.
              ageVerified: _ageConfirmed);
      if (!mounted) return;
      ref.read(analyticsProvider).signup();
      final user = response.user;
      if (user != null) {
        ref.read(analyticsProvider).identify(
              user.id,
              username: user.userMetadata['username'] as String?,
            );
      }
      // Router redirect handles navigation once the session lands.
    } catch (e) {
      AppLogger.error('[Signup] Phone signup failed', e);
      if (!mounted) return;
      final friendly = mapAuthError(e.toString());
      // The number is the only thing the user can act on here, so a
      // verification failure belongs on that field rather than in a
      // transient snackbar.
      if (friendly.toLowerCase().contains('verif') ||
          friendly.toLowerCase().contains('number')) {
        setState(() => _phoneError = friendly);
      } else {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(content: Text(friendly)));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: QuestColors.bg(context),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(22, 14, 22, 6),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: ArcadeBackButton(
                        onTap: () => context.canPop()
                            ? context.pop()
                            : context.goNamed(RouteNames.login),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(22, 8, 22, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          l.createAccount.toUpperCase(),
                          style: QuestTypography.osDisplayLarge.copyWith(
                            fontSize: 36,
                            height: 0.95,
                            // -0.04em at 36px.
                            letterSpacing: -1.44,
                          ),
                        ),
                        const SizedBox(height: 14),
                        AuthField(
                          controller: _phoneController,
                          focusNode: _phoneFocus,
                          label: 'PHONE NUMBER',
                          hint: '+96170123456',
                          required: true,
                          keyboardType: TextInputType.phone,
                          textInputAction: TextInputAction.next,
                          autocorrect: false,
                          autofillHints: const [AutofillHints.telephoneNumber],
                          errorText: _phoneError,
                          onChanged: (_) {
                            if (_phoneError != null) {
                              setState(() => _phoneError = null);
                            }
                          },
                          onSubmitted: (_) => _emailFocus.requestFocus(),
                        ),
                        const SizedBox(height: 14),
                        AuthField(
                          controller: _emailController,
                          focusNode: _emailFocus,
                          label: 'EMAIL',
                          hint: l.enterEmail,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.done,
                          autocorrect: false,
                          autofillHints: const [AutofillHints.email],
                          errorText: _emailError,
                          onSubmitted: (_) => _passwordFocus.requestFocus(),
                        ),
                        const SizedBox(height: 14),
                        AuthField(
                          controller: _passwordController,
                          focusNode: _passwordFocus,
                          label: 'PASSWORD',
                          hint: 'At least $passwordMinLength characters',
                          required: true,
                          obscureText: true,
                          textInputAction: TextInputAction.next,
                          autocorrect: false,
                          autofillHints: const [AutofillHints.newPassword],
                          errorText: _passwordError,
                          onChanged: (_) =>
                              setState(() => _passwordError = null),
                          onSubmitted: (_) => _confirmFocus.requestFocus(),
                        ),
                        const SizedBox(height: 8),
                        _StrengthMeter(password: _passwordController.text),
                        const SizedBox(height: 14),
                        AuthField(
                          controller: _confirmController,
                          focusNode: _confirmFocus,
                          label: 'CONFIRM PASSWORD',
                          hint: 'Type it again',
                          required: true,
                          obscureText: true,
                          textInputAction: TextInputAction.done,
                          autocorrect: false,
                          autofillHints: const [AutofillHints.newPassword],
                          errorText: _confirmError,
                          onChanged: (_) =>
                              setState(() => _confirmError = null),
                          onSubmitted: (_) => _createAccount(),
                        ),
                        const SizedBox(height: 14),
                        _AgeConfirm(
                          value: _ageConfirmed,
                          errorText: _ageError,
                          onChanged: (v) => setState(() {
                            _ageConfirmed = v;
                            if (v) _ageError = null;
                          }),
                        ),
                        const SizedBox(height: 14),
                        ArcadeButton(
                          label: _isLoading ? l.loading : l.signup,
                          isLoading: _isLoading,
                          variant: ArcadeButtonVariant.positive,
                          onTap: _isLoading ? null : _createAccount,
                        ),
                        // Apple / Google. The phone button is not repeated
                        // here — the form above is the phone path.
                        const SocialSignInButtons(includePhone: false),
                        const SizedBox(height: 14),
                        _LegalLine(
                          termsTap: _termsTap,
                          privacyTap: _privacyTap,
                        ),
                      ],
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

// ── Password strength ────────────────────────────────────────────────────────

/// Four segments that fill as the password gets stronger.
///
/// Presentation only: [validatePassword] is the gate, and a full meter is
/// not a promise that the form will accept the password. It exists so the
/// rules are visible while typing instead of arriving as a rejection after
/// the button is pressed.
class _StrengthMeter extends StatelessWidget {
  const _StrengthMeter({required this.password});

  final String password;

  static const _labels = ['', 'WEAK', 'FAIR', 'GOOD', 'STRONG'];

  @override
  Widget build(BuildContext context) {
    final score = passwordStrength(password);
    final colour = switch (score) {
      0 || 1 => QuestColors.osRed,
      2 => QuestColors.osAccent,
      3 => QuestColors.osCool,
      _ => QuestColors.osSuccess,
    };
    return Row(
      children: [
        for (var i = 0; i < 4; i++) ...[
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              height: 5,
              decoration: BoxDecoration(
                color: i < score
                    ? colour
                    : QuestColors.textDim(context).withAlpha(46),
                borderRadius: BorderRadius.circular(QuestSpacing.radiusFull),
              ),
            ),
          ),
          if (i < 3) const SizedBox(width: 5),
        ],
        const SizedBox(width: 10),
        SizedBox(
          width: 56,
          child: Text(
            _labels[score],
            textAlign: TextAlign.right,
            style: authMonoLabel(fontSize: 10, letterSpacingEm: 0.08)
                .copyWith(color: score == 0 ? Colors.transparent : colour),
          ),
        ),
      ],
    );
  }
}

// ── Age confirmation ─────────────────────────────────────────────────────────

class _AgeConfirm extends StatelessWidget {
  const _AgeConfirm({
    required this.value,
    required this.errorText,
    required this.onChanged,
  });

  final bool value;
  final String? errorText;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () => onChanged(!value),
          behavior: HitTestBehavior.opaque,
          child: ConstrainedBox(
            constraints:
                const BoxConstraints(minHeight: QuestSpacing.minTouchTarget),
            child: Row(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: value
                        ? QuestColors.osSuccess
                        : QuestColors.cardBg(context),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: errorText != null
                          ? QuestColors.osRed
                          : QuestColors.osTextPrimary,
                      width: 2,
                    ),
                  ),
                  child: value
                      ? Icon(
                          Icons.check_rounded,
                          size: 14,
                          // Jade ground: ink, never white.
                          color: QuestColors.onAccent(QuestColors.osSuccess),
                        )
                      : null,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'I confirm I am 13 years or older.',
                    style: QuestTypography.osBodySmall.copyWith(
                      fontSize: 12,
                      height: 1.55,
                      color: QuestColors.osTextSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (errorText != null)
          Text(
            errorText!,
            style: QuestTypography.osBodySmall.copyWith(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              fontVariations: const [FontVariation('wght', 600)],
              color: QuestColors.onCream(QuestColors.osRed),
            ),
          ),
      ],
    );
  }
}

// ── Legal line ───────────────────────────────────────────────────────────────

class _LegalLine extends StatelessWidget {
  const _LegalLine({required this.termsTap, required this.privacyTap});

  final GestureRecognizer termsTap;
  final GestureRecognizer privacyTap;

  @override
  Widget build(BuildContext context) {
    final base = QuestTypography.osBodySmall.copyWith(
      fontSize: 12,
      height: 1.55,
      color: QuestColors.osTextSecondary,
    );
    final link = base.copyWith(color: QuestColors.osPrimary);

    return Text.rich(
      TextSpan(
        style: base,
        children: [
          const TextSpan(text: 'By signing up you agree to the '),
          TextSpan(text: 'Terms of Service', style: link, recognizer: termsTap),
          const TextSpan(text: ' and '),
          TextSpan(text: 'Privacy Policy', style: link, recognizer: privacyTap),
          const TextSpan(text: '.'),
        ],
      ),
      textAlign: TextAlign.center,
    );
  }
}
