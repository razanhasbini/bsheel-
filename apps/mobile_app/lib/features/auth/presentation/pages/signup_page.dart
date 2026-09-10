import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:app_core/app_core.dart';
import 'package:app_repositories/app_repositories.dart' show AuthException;
import 'package:shared_ui/shared_ui.dart';

import '../../../../core/router/route_names.dart';
import '../../../../core/providers/auth_repository_provider.dart';
import '../../../../core/security/secure_screen.dart';
import '../../../../core/services/analytics_service.dart';
import '../auth_error_mapper.dart';
import '../login_credentials.dart';
import '../password_policy.dart';
import '../widgets/auth_field.dart';
import '../../../../l10n/app_localizations.dart';

/// Create account, drawn from `export/mobile/17-signup.jpg`.
///
/// A 46pt back button, `CREATE ACCOUNT` in Syne 800/36, three labelled
/// fields on a 14pt rhythm — username with a jade validity tick and a helper
/// line, email, password with a four-segment strength meter — then the jade
/// positive button and a centred legal line with violet links.
///
/// There is no card, no subtitle, no social block and no "already have an
/// account" footer; the frame has none of them, and the back button already
/// returns to login.
class SignupPage extends ConsumerStatefulWidget {
  const SignupPage({super.key});

  @override
  ConsumerState<SignupPage> createState() => _SignupPageState();
}

// H9 (2026-05-17): block screenshots while a password is being typed.
class _SignupPageState extends ConsumerState<SignupPage>
    with SecureScreenMixin {
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _usernameFocus = FocusNode();
  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();
  final _termsTap = TapGestureRecognizer();
  final _privacyTap = TapGestureRecognizer();

  bool _isLoading = false;
  // Low/Info (2026-05-17): age confirmation. Required true before submit
  // so we have a contemporaneous record that the user attested to being
  // 13+. Stored as profiles.age_verified via the signup metadata.
  bool _ageConfirmed = false;
  String? _usernameError;
  String? _emailError;
  String? _passwordError;
  String? _ageError;

  @override
  void initState() {
    super.initState();
    _termsTap.onTap = () => context.pushNamed(RouteNames.terms);
    _privacyTap.onTap = () => context.pushNamed(RouteNames.privacyPolicy);
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _usernameFocus.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    _termsTap.dispose();
    _privacyTap.dispose();
    super.dispose();
  }

  String? _validateUsername(String v) {
    final l = AppLocalizations.of(context)!;
    if (v.isEmpty) return l.usernameRequired;
    if (v.length < 3 || v.length > 30) return l.usernameLengthError;
    if (!RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(v)) {
      return l.usernameFormatError;
    }
    return null;
  }

  String? _validateEmail(String v) {
    final l = AppLocalizations.of(context)!;
    if (v.isEmpty) return l.emailRequired;
    if (!emailPattern.hasMatch(v)) return l.emailInvalid;
    return null;
  }

  Future<void> _signup() async {
    final username = _usernameController.text.trim();
    // Lower-case the email so `Foo@Bar.com` and `foo@bar.com` don't
    // resolve to two separate Supabase auth accounts.
    final email = _emailController.text.trim().toLowerCase();
    final password = _passwordController.text;

    setState(() {
      _usernameError = _validateUsername(username);
      _emailError = _validateEmail(email);
      _passwordError = validatePassword(
        password,
        username: username,
        emailLocalPart: email.contains('@') ? email.split('@').first : email,
      );
      _ageError = _ageConfirmed ? null : 'You must be 13 or older to sign up.';
    });
    if (_usernameError != null ||
        _emailError != null ||
        _passwordError != null ||
        _ageError != null) {
      return;
    }

    setState(() => _isLoading = true);
    try {
      final response = await ref.read(authRepositoryProvider).signUpWithEmail(
        email,
        password,
        data: {
          'username': username,
          'display_name': username,
          // Low/Info (2026-05-17): mirror the checkbox value into
          // raw_user_meta_data so the handle_new_user trigger can copy
          // it onto profiles.age_verified.
          'age_verified': true,
        },
      );
      if (!mounted) return;

      ref.read(analyticsProvider).signup();
      if (response.session == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Account created — check your email to confirm, then log in.'),
          ),
        );
        if (!mounted) return;
        context.goNamed(RouteNames.login);
      }
    } on AuthException catch (e) {
      if (!mounted) return;
      // The API distinguishes which value collided so the message
      // lands on the field the user has to change.
      setState(() {
        switch (e.code) {
          case 'EMAIL_TAKEN':
            _emailError = 'That email is already registered. Log in '
                'instead — or use FORGOT PASSWORD.';
          case 'USERNAME_TAKEN':
            _usernameError = 'That username is already taken.';
          default:
            _emailError = mapAuthError(e.toString());
        }
      });
    } catch (e) {
      AppLogger.error('[Signup] Signup failed', e);
      if (!mounted) return;
      final friendly = mapAuthError(e.toString());
      // Route the error to the right field when we can tell, otherwise
      // surface it as a snackbar so we don't mislead the user into
      // editing the password when the real problem was e.g. a duplicate
      // email or rate limit.
      final lower = friendly.toLowerCase();
      if (lower.contains('password') &&
          (lower.contains('weak') || lower.contains('characters'))) {
        setState(() => _passwordError = friendly);
      } else if (lower.contains('email')) {
        setState(() => _emailError = friendly);
      } else if (lower.contains('username') ||
          lower.contains('already taken')) {
        // "username or email is already taken" — most likely username here.
        setState(() => _usernameError = friendly);
      } else {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(content: Text(friendly)));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// The frame's username field carries a jade tick once the handle is
  /// legal. It is a live signal, so it tracks the controller rather than
  /// the last submit.
  bool get _usernameLooksValid {
    final v = _usernameController.text.trim();
    return v.length >= 3 &&
        v.length <= 30 &&
        RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(v);
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
                        controller: _usernameController,
                        focusNode: _usernameFocus,
                        label: l.username,
                        hint: l.chooseUsername,
                        textInputAction: TextInputAction.next,
                        autocorrect: false,
                        errorText: _usernameError,
                        helperText: 'Letters, numbers, and underscores only.',
                        trailing:
                            _usernameLooksValid ? const AuthFieldTick() : null,
                        onChanged: (_) => setState(() {}),
                        onSubmitted: (_) => _emailFocus.requestFocus(),
                      ),
                      const SizedBox(height: 14),
                      AuthField(
                        controller: _emailController,
                        focusNode: _emailFocus,
                        label: l.email,
                        hint: l.enterEmail,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        autocorrect: false,
                        autofillHints: const [AutofillHints.email],
                        errorText: _emailError,
                        onSubmitted: (_) => _passwordFocus.requestFocus(),
                      ),
                      const SizedBox(height: 14),
                      AuthField(
                        controller: _passwordController,
                        focusNode: _passwordFocus,
                        label: l.password,
                        hint: l.createPassword,
                        obscureText: true,
                        textInputAction: TextInputAction.done,
                        autofillHints: const [AutofillHints.newPassword],
                        errorText: _passwordError,
                        onChanged: (_) => setState(() {}),
                        onSubmitted: (_) => _signup(),
                      ),
                      const SizedBox(height: 6),
                      _StrengthMeter(
                        filled: passwordStrength(_passwordController.text),
                      ),
                      const SizedBox(height: 14),
                      // Low/Info (2026-05-17): age confirmation. Not in the
                      // frame, but it is the contemporaneous 13+ record that
                      // `profiles.age_verified` is written from — it cannot
                      // be dropped for fidelity.
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
                        // The frame's positive: jade ground, ink label,
                        // 56pt, r14, 5px shadow.
                        label: _isLoading ? l.loading : l.signup,
                        isLoading: _isLoading,
                        variant: ArcadeButtonVariant.positive,
                        onTap: _isLoading ? null : _signup,
                      ),
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
          )),
        ),
      ),
    );
  }
}

// ── Strength meter ───────────────────────────────────────────────────────────

/// Four segments, 4 apart: 8 of content inside a 2px ink stroke at r4, jade
/// when earned and warm surface when not.
class _StrengthMeter extends StatelessWidget {
  const _StrengthMeter({required this.filled});

  final int filled;

  static const _segments = 4;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < _segments; i++) ...[
          if (i > 0) const SizedBox(width: 4),
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              height: 12,
              decoration: BoxDecoration(
                color:
                    i < filled ? QuestColors.osSuccess : QuestColors.osSurface,
                borderRadius: BorderRadius.circular(QuestSpacing.radiusSegment),
                border: Border.all(
                  color: QuestColors.osTextPrimary,
                  width: 2,
                ),
              ),
            ),
          ),
        ],
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
          TextSpan(
            text: 'Terms of Service',
            style: link,
            recognizer: termsTap,
          ),
          const TextSpan(text: ' and '),
          TextSpan(
            text: 'Privacy Policy',
            style: link,
            recognizer: privacyTap,
          ),
          const TextSpan(text: '.'),
        ],
      ),
      textAlign: TextAlign.center,
    );
  }
}
