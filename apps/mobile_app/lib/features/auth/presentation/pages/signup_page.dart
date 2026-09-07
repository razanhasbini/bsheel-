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
import '../widgets/social_sign_in_buttons.dart';
import '../../../../l10n/app_localizations.dart';

class SignupPage extends ConsumerStatefulWidget {
  const SignupPage({super.key});

  @override
  ConsumerState<SignupPage> createState() => _SignupPageState();
}

// H9 (2026-05-17): block screenshots while a password is being typed.
class _SignupPageState extends ConsumerState<SignupPage> with SecureScreenMixin {
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _usernameFocus = FocusNode();
  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();

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
  void dispose() {
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _usernameFocus.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
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

      // With email confirmations enabled, Supabase deliberately does NOT
      // error when the email is already registered (anti-enumeration) —
      // it returns a fake user whose `identities` list is empty. Without
      // this check the user would be told "check your email" and wait for
      // a confirmation that never arrives.
      final identities = response.user?.identities;
      if (response.session == null &&
          identities != null &&
          identities.isEmpty) {
        setState(() => _emailError =
            'That email is already registered. Log in instead — or use '
            'FORGOT PASSWORD if you don\'t remember your password.');
        return;
      }

      ref.read(analyticsProvider).signup();
      if (response.session == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('Account created — check your email to confirm, then log in.'),
          ),
        );
        if (!mounted) return;
        context.goNamed(RouteNames.login);
      }
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
                  l.createAccount,
                  style: QuestTypography.displayLarge.copyWith(
                    color: ink,
                    fontSize: 32,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Join the quest. Start leveling up.',
                  style: QuestTypography.bodyMedium.copyWith(
                    color: ink.withAlpha(QuestColors.alphaInkMuted),
                  ),
                ),
                const SizedBox(height: 28),
                ArcadeCard(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ArcadeTextField(
                        controller: _usernameController,
                        focusNode: _usernameFocus,
                        label: l.username,
                        hint: l.chooseUsername,
                        prefixIcon: Icons.person_outline_rounded,
                        textInputAction: TextInputAction.next,
                        autocorrect: false,
                        errorText: _usernameError,
                        onSubmitted: (_) => _emailFocus.requestFocus(),
                      ),
                      const SizedBox(height: 14),
                      ArcadeTextField(
                        controller: _emailController,
                        focusNode: _emailFocus,
                        label: l.email,
                        hint: l.enterEmail,
                        keyboardType: TextInputType.emailAddress,
                        prefixIcon: Icons.alternate_email_rounded,
                        textInputAction: TextInputAction.next,
                        autocorrect: false,
                        autofillHints: const [AutofillHints.email],
                        errorText: _emailError,
                        onSubmitted: (_) => _passwordFocus.requestFocus(),
                      ),
                      const SizedBox(height: 14),
                      ArcadeTextField(
                        controller: _passwordController,
                        focusNode: _passwordFocus,
                        label: l.password,
                        hint: l.createPassword,
                        obscureText: true,
                        prefixIcon: Icons.lock_outline_rounded,
                        textInputAction: TextInputAction.done,
                        autofillHints: const [AutofillHints.newPassword],
                        helper:
                            'Min $passwordMinLength chars, mixed case + a number.',
                        errorText: _passwordError,
                        onSubmitted: (_) => _signup(),
                      ),
                      const SizedBox(height: 18),
                      // Low/Info (2026-05-17): age confirmation checkbox.
                      // Required true before submission; persisted to
                      // profiles.age_verified via signup metadata.
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Checkbox(
                            value: _ageConfirmed,
                            onChanged: (v) => setState(() {
                              _ageConfirmed = v ?? false;
                              if (_ageConfirmed) _ageError = null;
                            }),
                          ),
                          Expanded(
                            child: GestureDetector(
                              onTap: () => setState(() {
                                _ageConfirmed = !_ageConfirmed;
                                if (_ageConfirmed) _ageError = null;
                              }),
                              child: Padding(
                                padding: const EdgeInsets.only(top: 12),
                                child: Text(
                                  'I confirm I am 13 years or older.',
                                  style: QuestTypography.bodyMedium.copyWith(
                                    color: ink,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (_ageError != null)
                        Padding(
                          padding: const EdgeInsets.only(left: 12, top: 4),
                          child: Text(
                            _ageError!,
                            style: QuestTypography.bodySmall.copyWith(
                              color: QuestColors.softRed,
                            ),
                          ),
                        ),
                      const SizedBox(height: 12),
                      ArcadeButton(
                        label: _isLoading ? l.loading : l.createAccount,
                        icon: _isLoading ? null : Icons.bolt_rounded,
                        isLoading: _isLoading,
                        size: ArcadeButtonSize.large,
                        onTap: _isLoading ? null : _signup,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                const SocialSignInButtons(),
                const SizedBox(height: 20),
                Center(
                  child: GestureDetector(
                    onTap: () => context.goNamed(RouteNames.login),
                    behavior: HitTestBehavior.opaque,
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text.rich(
                        TextSpan(
                          text: '${l.alreadyHaveAccount} ',
                          style: QuestTypography.bodyMedium.copyWith(
                            color: ink.withAlpha(QuestColors.alphaInkMuted),
                          ),
                          children: [
                            TextSpan(
                              text: l.login,
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
    );
  }
}
