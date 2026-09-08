import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/backend/app_backend.dart';
import '../../../../core/router/admin_route_names.dart';
import '../../../../core/theme/bsheel_design.dart';
import '../../../../shared/widgets/bsheel_widgets.dart';

/// Public landing page for the Nest backend's one-time email-confirmation URL.
///
/// The raw token is accepted only from the URL, validated for the backend's
/// base64url format, sent once to the API, and never logged or rendered.
class ConfirmEmailPage extends StatefulWidget {
  const ConfirmEmailPage({super.key, required this.token});

  final String? token;

  @override
  State<ConfirmEmailPage> createState() => _ConfirmEmailPageState();
}

class _ConfirmEmailPageState extends State<ConfirmEmailPage> {
  bool _loading = true;
  bool _confirmed = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    Future.microtask(_confirm);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BsheelColors.bg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: BsheelCard(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const BsheelEyebrow('Account confirmation'),
                    const SizedBox(height: 18),
                    Icon(
                      _confirmed
                          ? Icons.check_circle_outline
                          : _error != null
                              ? Icons.error_outline
                              : Icons.mark_email_read_outlined,
                      size: 44,
                      color: _confirmed
                          ? BsheelColors.onCream(BsheelColors.success)
                          : _error != null
                              ? BsheelColors.onCream(BsheelColors.danger)
                              : BsheelColors.ink,
                    ),
                    const SizedBox(height: 18),
                    Text(
                      _loading
                          ? 'Confirming your email…'
                          : _confirmed
                              ? 'Email confirmed.'
                              : 'Could not confirm email.',
                      style: BsheelType.displayLg,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _loading
                          ? 'Keep this page open for a moment.'
                          : _confirmed
                              ? 'Your account is ready. Return to Bsheel and log in.'
                              : _error!,
                      style: BsheelType.bodyLg.copyWith(
                        color: BsheelColors.inkSoft,
                      ),
                    ),
                    const SizedBox(height: 26),
                    if (_loading)
                      const LinearProgressIndicator(color: BsheelColors.ink)
                    else if (_confirmed)
                      BsheelButton.primary(
                        label: 'Go to login',
                        icon: Icons.login,
                        onPressed: () => context.go(AdminRoutePaths.login),
                      )
                    else
                      Row(
                        children: [
                          Expanded(
                            child: BsheelButton.ghost(
                              label: 'Go to login',
                              onPressed: () =>
                                  context.go(AdminRoutePaths.login),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: BsheelButton.primary(
                              label: 'Try again',
                              onPressed: _confirm,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
