import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:app_repositories/app_repositories.dart'
    show ApiException, AuthException;

import '../../../../core/providers/repository_providers.dart';
import '../../../../core/router/admin_route_names.dart';
import '../../../../core/theme/bsheel_design.dart';
import '../../../../shared/widgets/bsheel_widgets.dart';

/// "Port" login. Single centred hairline card on a pure white page,
/// small inverted brand mark, light display headline with an italic
/// accent ("Sign in to the {desk.}"), solid black pill submit.
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BsheelColors.bg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: BsheelCard(
                padding: const EdgeInsets.fromLTRB(32, 32, 32, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Brand
                    Row(
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: BsheelColors.ink,
                            borderRadius: BorderRadius.circular(BsheelRadii.sm),
                          ),
                          alignment: Alignment.center,
                          child: const Text(
                            'B',
                            style: TextStyle(
                              fontFamily: BsheelFonts.body,
                              fontWeight: FontWeight.w400,
                              fontSize: 18,
                              color: BsheelColors.pureWhite,
                              height: 1,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Bsheel',
                              style: BsheelType.displaySm.copyWith(
                                fontSize: 20,
                                height: 1,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'ADMIN · V1.0',
                              style: BsheelType.labelSm.copyWith(
                                fontSize: 9,
                                letterSpacing: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 28),
                    const BsheelEyebrow('Restricted area'),
                    const SizedBox(height: 12),
                    BsheelDisplay(
                      'Sign in to the {desk.}',
                      baseStyle: BsheelType.displayLg.copyWith(fontSize: 38),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Mods, ops and admins only. Everyone else: open the '
                      'mobile app instead.',
                      style: BsheelType.bodyMd.copyWith(
                        color: BsheelColors.inkSoft,
                      ),
                    ),
                    const SizedBox(height: 24),
                    _Field(
                      controller: _emailController,
                      label: 'EMAIL',
                      hint: 'you@bsheel.app',
                    ),
                    const SizedBox(height: 14),
                    _Field(
                      controller: _passwordController,
                      label: 'PASSWORD',
                      hint: '••••••••',
                      obscure: true,
                      onSubmitted: (_) => _login(),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: BsheelColors.paper,
                          borderRadius: BorderRadius.circular(BsheelRadii.md),
                          border: Border.all(
                            color: BsheelColors.danger,
                            width: BsheelBorders.thin,
                          ),
                        ),
                        child: Text(
                          _error!,
                          style: BsheelType.bodySm.copyWith(
                            color: BsheelColors.onCream(BsheelColors.danger),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: BsheelButton.primary(
                            label: _loading ? 'SIGNING IN…' : 'SIGN IN',
                            icon: _loading ? null : Icons.arrow_forward_rounded,
                            loading: _loading,
                            onPressed: _loading ? null : _login,
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

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.label,
    this.hint,
    this.obscure = false,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final bool obscure;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: BsheelType.labelSm),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          obscureText: obscure,
          style: BsheelType.bodyMd,
          onSubmitted: onSubmitted,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: BsheelType.bodyMd.copyWith(
              color: BsheelColors.inkMuted,
            ),
            filled: true,
            fillColor: BsheelColors.paper,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 11,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(BsheelRadii.md),
              borderSide: const BorderSide(
                color: BsheelColors.line,
                width: BsheelBorders.thin,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(BsheelRadii.md),
              borderSide: const BorderSide(
                color: BsheelColors.line,
                width: BsheelBorders.thin,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(BsheelRadii.md),
              borderSide: const BorderSide(
                color: BsheelColors.ink,
                width: BsheelBorders.thin,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
