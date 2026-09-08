import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/backend/app_backend.dart';
import '../../../../core/router/admin_route_names.dart';
import '../../../../core/theme/bsheel_design.dart';
import '../../../../shared/widgets/bsheel_widgets.dart';

/// Public landing page for the Nest backend's one-time email-confirmation URL.
///
/// The raw token is accepted only from the URL, validated for the backend's
/// base64url format, sent once to the API, and never logged or rendered.
///
/// Four states, all drawn inside one 620px page frame on cream:
///
/// * **awaiting** — reached with an address but no token, i.e. straight after
///   sign-up. Jade tick badge, "CHECK YOUR EMAIL", and a resend that is
///   rate-limited to one send a minute.
/// * **loading** — a token is being exchanged with the API.
/// * **confirmed** — the exchange succeeded.
/// * **error** — no token, a malformed token, or a token the API rejected.
///   The message never names the token or why it failed.
class ConfirmEmailPage extends StatefulWidget {
  const ConfirmEmailPage({super.key, required this.token, this.email});

  final String? token;

  /// The address the confirmation was sent to, when the URL carries one.
  /// Only used to draw the "check your email" state and to target a resend —
  /// it is never used to confirm anything.
  final String? email;

  @override
  State<ConfirmEmailPage> createState() => _ConfirmEmailPageState();
}

class _ConfirmEmailPageState extends State<ConfirmEmailPage> {
  /// One resend a minute.
  static const int _resendCooldownSeconds = 60;

  bool _loading = true;
  bool _confirmed = false;
  String? _error;

  Timer? _cooldownTimer;
  int _cooldownRemaining = 0;
  bool _resending = false;
  bool _mailAppFailed = false;

  /// Landed with an address but no token — nothing to exchange yet.
  bool get _awaiting => widget.token == null && widget.email != null;

  @override
  void initState() {
    super.initState();
    if (_awaiting) {
      _loading = false;
      return;
    }
    Future.microtask(_confirm);
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    super.dispose();
  }

  Future<void> _confirm() async {
    if (!_isValidToken(widget.token)) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'This confirmation link is invalid or has expired.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await AppBackend.repositories.auth
          .completeEmailConfirmation(widget.token!);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _confirmed = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'This confirmation link is invalid or has expired.';
      });
    }
  }

  bool _isValidToken(String? token) {
    if (token == null) return false;
    return RegExp(r'^[A-Za-z0-9_-]{32,128}$').hasMatch(token);
  }

  Future<void> _resend() async {
    final email = widget.email;
    if (email == null || _cooldownRemaining > 0 || _resending) return;
    setState(() {
      _resending = true;
      _error = null;
    });
    try {
      await AppBackend.repositories.auth.resendSignupConfirmation(email);
      if (!mounted) return;
      setState(_startCooldown);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'We could not send another link just now.');
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  /// Called from inside a `setState`, so it only mutates.
  void _startCooldown() {
    _cooldownTimer?.cancel();
    _cooldownRemaining = _resendCooldownSeconds;
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => _cooldownRemaining -= 1);
      if (_cooldownRemaining <= 0) timer.cancel();
    });
  }

  String get _cooldownLabel {
    final minutes = _cooldownRemaining ~/ 60;
    final seconds = (_cooldownRemaining % 60).toString().padLeft(2, '0');
    return 'RESEND AVAILABLE IN $minutes:$seconds';
  }

  Future<void> _openMailApp() async {
    var launched = false;
    try {
      launched = await launchUrl(Uri.parse('mailto:'));
    } on Exception catch (_) {
      launched = false;
    }
    if (!launched && mounted) {
      setState(() => _mailAppFailed = true);
    }
  }

  void _goToLogin() => context.go(AdminRoutePaths.login);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BsheelColors.bg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 32, 32, 40),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 620),
              padding: const EdgeInsets.all(36),
              decoration: BoxDecoration(
                color: BsheelColors.bg,
                borderRadius: BorderRadius.circular(BsheelRadii.lg),
                border: const Border.fromBorderSide(BsheelBorders.inkSide),
                boxShadow: BsheelShadows.frame,
              ),
              child: Center(
                child: SizedBox(
                  width: 380,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: _panel(),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _panel() {
    if (_awaiting) return _awaitingPanel();
    if (_loading) return _loadingPanel();
    if (_confirmed) return _confirmedPanel();
    return _errorPanel();
  }

  // ── States ────────────────────────────────────────────────────────

  List<Widget> _awaitingPanel() {
    return [
      const _Badge(ground: BsheelColors.success, icon: Icons.check_rounded),
      const SizedBox(height: 16),
      const Text(
        'CHECK YOUR EMAIL',
        textAlign: TextAlign.center,
        style: BsheelType.displayLg,
      ),
      const SizedBox(height: 16),
      Text.rich(
        TextSpan(
          children: [
            const TextSpan(text: 'We sent a confirmation link to '),
            TextSpan(text: widget.email!, style: BsheelType.monoLg),
            const TextSpan(text: '. The link expires in 30 minutes.'),
          ],
        ),
        textAlign: TextAlign.center,
        style: BsheelType.bodyMd.copyWith(color: BsheelColors.inkSoft),
      ),
      if (_error != null) ...[
        const SizedBox(height: 16),
        BsheelCallout.danger(_error!),
      ],
      const SizedBox(height: 18),
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          BsheelButton.primary(
            label: 'OPEN MAIL APP',
            height: 48,
            onPressed: _openMailApp,
          ),
          const SizedBox(width: 9),
          BsheelButton.ghost(
            label: 'RESEND',
            height: 48,
            loading: _resending,
            onPressed: _cooldownRemaining > 0 ? null : _resend,
          ),
        ],
      ),
      if (_cooldownRemaining > 0) ...[
        const SizedBox(height: 16),
        Text(
          _cooldownLabel,
          style: BsheelType.labelMd.copyWith(color: BsheelColors.inkMuted),
        ),
      ],
      if (_mailAppFailed) ...[
        const SizedBox(height: 16),
        const BsheelLabel(
          'Open your inbox manually',
          color: BsheelColors.inkMuted,
        ),
      ],
      const SizedBox(height: 16),
      BsheelLink('Go to login', onTap: _goToLogin),
    ];
  }

  List<Widget> _loadingPanel() {
    return [
      const _Badge(
        ground: BsheelColors.surface,
        icon: Icons.mark_email_read_outlined,
      ),
      const SizedBox(height: 16),
      const Text(
        'Confirming your email…',
        textAlign: TextAlign.center,
        style: BsheelType.displayLg,
      ),
      const SizedBox(height: 16),
      Text(
        'Keep this page open for a moment.',
        textAlign: TextAlign.center,
        style: BsheelType.bodyMd.copyWith(color: BsheelColors.inkSoft),
      ),
      const SizedBox(height: 22),
      const SizedBox(
        width: 200,
        child: LinearProgressIndicator(color: BsheelColors.ink),
      ),
    ];
  }

  List<Widget> _confirmedPanel() {
    return [
      const _Badge(ground: BsheelColors.success, icon: Icons.check_rounded),
      const SizedBox(height: 16),
      const Text(
        'Email confirmed.',
        textAlign: TextAlign.center,
        style: BsheelType.displayLg,
      ),
      const SizedBox(height: 16),
      Text(
        'Your account is ready. Return to Bsheel and log in.',
        textAlign: TextAlign.center,
        style: BsheelType.bodyMd.copyWith(color: BsheelColors.inkSoft),
      ),
      const SizedBox(height: 18),
      BsheelButton.primary(
        label: 'GO TO LOGIN',
        height: 48,
        onPressed: _goToLogin,
      ),
    ];
  }

  List<Widget> _errorPanel() {
    return [
      const _Badge(
        ground: BsheelColors.danger,
        icon: Icons.priority_high_rounded,
      ),
      const SizedBox(height: 16),
      const Text(
        'Could not confirm email.',
        textAlign: TextAlign.center,
        style: BsheelType.displayLg,
      ),
      const SizedBox(height: 16),
      BsheelCallout.danger(_error!),
      const SizedBox(height: 18),
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          BsheelButton.primary(
            label: 'TRY AGAIN',
            height: 48,
            onPressed: _confirm,
          ),
          const SizedBox(width: 9),
          BsheelButton.ghost(
            label: 'GO TO LOGIN',
            height: 48,
            onPressed: _goToLogin,
          ),
        ],
      ),
    ];
  }
}

/// The 60px circular status badge the design draws above every title.
class _Badge extends StatelessWidget {
  const _Badge({required this.ground, required this.icon});

  final Color ground;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 60,
      height: 60,
      decoration: BoxDecoration(
        color: ground,
        shape: BoxShape.circle,
        border: const Border.fromBorderSide(BsheelBorders.inkSide),
        boxShadow: BsheelShadows.md,
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: 28, color: BsheelColors.onAccent(ground)),
    );
  }
}
