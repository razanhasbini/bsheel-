import 'package:app_core/app_core.dart';
import 'package:app_repositories/app_repositories.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../core/providers/session_providers.dart';

/// Sign-in for a partner.
///
/// The same credentials as the app: a business member is an ordinary
/// Bsheel user who additionally belongs to a business, so there is no
/// separate partner account to create or remember. Whether they may see a
/// dashboard is decided after sign-in, by membership, not here.
class BusinessLoginPage extends ConsumerStatefulWidget {
  const BusinessLoginPage({super.key});

  @override
  ConsumerState<BusinessLoginPage> createState() => _BusinessLoginPageState();
}

class _BusinessLoginPageState extends ConsumerState<BusinessLoginPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _email.text.trim();
    final password = _password.text;
    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = 'Enter your email and password.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await ref
          .read(authRepositoryProvider)
          .signInWithEmail(email, password);
      final user = result.user;
      if (user == null) {
        setState(() => _error = 'Confirm your email address, then sign in.');
        return;
      }
      // Setting the session is what lets the router decide; the membership
      // read it depends on fires from there.
      ref.read(sessionProvider.notifier).state = user;
    } on AuthException catch (error) {
      // The API's own message, not a guess at which field was wrong.
      setState(() => _error = error.message);
    } catch (_) {
      setState(() => _error = 'Could not sign in. Check your connection.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: QuestColors.bg(context),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: ArcadeCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('BSHEEL FOR BUSINESS',
                      style: QuestTypography.osLabelSmall
                          .copyWith(color: QuestColors.textDim(context))),
                  const SizedBox(height: 6),
                  Text('Partner dashboard',
                      style: QuestTypography.osHeadlineMedium),
                  const SizedBox(height: 20),
                  ArcadeTextField(
                    controller: _email,
                    label: 'EMAIL',
                    keyboardType: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 12),
                  ArcadeTextField(
                    controller: _password,
                    label: 'PASSWORD',
                    obscureText: true,
                    onSubmitted: (_) => _submit(),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!,
                        style: QuestTypography.osBodySmall
                            .copyWith(color: QuestColors.osRed)),
                  ],
                  const SizedBox(height: 18),
                  ArcadeButton(
                    label: _busy ? 'SIGNING IN…' : 'SIGN IN',
                    onTap: _busy ? null : _submit,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Use your Bsheel account. Dashboard access comes from '
                    'your business membership.',
                    style: QuestTypography.osBodySmall
                        .copyWith(color: QuestColors.textDim(context)),
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
