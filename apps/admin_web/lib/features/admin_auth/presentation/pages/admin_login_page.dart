import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:app_repositories/app_repositories.dart'
    show ApiException, AuthException;

import '../../../../core/providers/repository_providers.dart';
import '../../../../core/router/admin_route_names.dart';
import '../../../../core/theme/bsheel_design.dart';
import '../../../../shared/widgets/bsheel_widgets.dart';

/// Moderator sign-in. Renders outside the shell, so it owns its own
/// [Scaffold]: a single 620px page frame centred on cream — 2px ink
/// outline, 14px radius, 8px hard ink shadow — holding a 330px column.
class AdminLoginPage extends ConsumerStatefulWidget {
  const AdminLoginPage({super.key});

  @override
  ConsumerState<AdminLoginPage> createState() => _AdminLoginPageState();
}

class _AdminLoginPageState extends ConsumerState<AdminLoginPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _loading = false;
  String? _error;
  String? _notice;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    setState(() {
      _loading = true;
      _error = null;
      _notice = null;
    });
    try {
      final response = await ref.read(authRepositoryProvider).signInWithEmail(
            _emailController.text.trim(),
            _passwordController.text,
          );
      if (response.user == null) {
        throw const AuthException('Login failed. Please try again.');
      }
      if (mounted) {
        GoRouter.of(context).go(AdminRoutePaths.dashboard);
      }
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'Sign in failed. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _forgotPassword() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      setState(() {
        _notice = null;
        _error = 'Enter your email address first, then tap forgot password.';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _notice = null;
    });
    try {
      await ref.read(authRepositoryProvider).resetPassword(email);
      if (mounted) {
        setState(() => _notice = 'Reset link sent. Check your inbox.');
      }
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Reset failed. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

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
                  width: 330,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text('BSHEEL ADMIN', style: BsheelType.displayLg),
                      const SizedBox(height: 2),
                      const BsheelLabel('Moderator sign in'),
                      const SizedBox(height: 16),
                      BsheelField(
                        controller: _emailController,
                        label: 'Email',
                        hint: 'your@email.com',
                        keyboardType: TextInputType.emailAddress,
                        enabled: !_loading,
                      ),
                      const SizedBox(height: 16),
                      BsheelField(
                        controller: _passwordController,
                        label: 'Password',
                        hint: 'Enter your password',
                        obscureText: true,
                        enabled: !_loading,
                        onSubmitted: (_) => _login(),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 16),
                        BsheelCallout.danger(_error!),
                      ],
                      if (_notice != null) ...[
                        const SizedBox(height: 16),
                        BsheelCallout.positive(_notice!),
                      ],
                      const SizedBox(height: 16),
                      BsheelButton.primary(
                        label: 'LOG IN',
                        expand: true,
                        height: 52,
                        loading: _loading,
                        onPressed: _loading ? null : _login,
                      ),
                      const SizedBox(height: 14),
                      BsheelLink(
                        'Forgot password?',
                        align: TextAlign.center,
                        onTap: _loading ? null : _forgotPassword,
                      ),
                    ],
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
