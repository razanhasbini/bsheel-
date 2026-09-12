import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/providers/auth_repository_provider.dart';
import '../../../../core/router/route_names.dart';
import '../pending_auth_error.dart';

/// Where a CAMARA Number Verification return lands, on web and on device.
///
/// This used to be an inline builder that fired the exchange from a
/// post-frame callback and rendered `SizedBox.shrink()` while it ran. Two
/// things were wrong with that, and both of them showed up as a **white
/// page** with a 400 in the console:
///
/// **The exchange could throw, and nothing caught it.** The handoff code is
/// single-use and short-lived, so the second attempt on one code is a 400 by
/// design. On the web the browser keeps `?handoff=…` in the address bar, so
/// an ordinary reload — or a back button — replays a code that has already
/// been spent. The throw escaped the callback, `context.go` never ran, and
/// the user was left looking at the blank widget forever. A spent code now
/// lands on the login page saying so.
///
/// **A builder can run more than once.** Every rebuild fired another
/// exchange; one sign-in produced six POSTs to `phone/complete`, five of
/// them guaranteed failures racing the one that worked. The exchange is now
/// owned by a State and runs exactly once per mount.
///
/// It also shows a spinner rather than nothing: the call crosses the network
/// to the operator's token endpoint, and a blank screen during it is
/// indistinguishable from the crash this class exists to prevent.
class PhoneSigninCallbackScreen extends ConsumerStatefulWidget {
  const PhoneSigninCallbackScreen({super.key, required this.uri});

  final Uri uri;

  @override
  ConsumerState<PhoneSigninCallbackScreen> createState() =>
      _PhoneSigninCallbackScreenState();
}

class _PhoneSigninCallbackScreenState
    extends ConsumerState<PhoneSigninCallbackScreen> {
  @override
  void initState() {
    super.initState();
    // After the first frame: `context.go` needs a mounted navigator, and
    // reading providers during initState is not allowed.
    WidgetsBinding.instance.addPostFrameCallback((_) => _complete());
  }

  Future<void> _complete() async {
    if (!mounted) return;

    // A refusal comes back the same way a success does, carrying `error`
    // instead of `handoff`. It is handed to the login page rather than shown
    // from here: this route is about to be torn down, so a messenger read
    // from THIS context belongs to a widget being disposed and the message
    // never appears — which is why a refused number used to bounce back in
    // silence.
    final failure = widget.uri.queryParameters['error'];
    if (failure != null && failure.isNotEmpty) {
      _bounceToLogin(failure);
      return;
    }

    try {
      // Awaited, because on web this call is the one that actually exchanges
      // the handoff code for a session — navigating first would bounce off
      // the auth gate before the tokens land. On mobile it just wakes the
      // waiting sign-in call and returns immediately, so the await costs
      // nothing there.
      await ref.read(authRepositoryProvider).handlePhoneCallback(widget.uri);
      if (mounted) context.go(RoutePaths.home);
    } catch (error) {
      AppLogger.error('[PhoneSignin] Handoff exchange failed', error);
      _bounceToLogin(error.toString());
    }
  }

  void _bounceToLogin(String reason) {
    ref.read(pendingAuthErrorProvider.notifier).state = reason;
    if (mounted) context.go(RoutePaths.login);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: QuestColors.bg(context),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text('CONFIRMING YOUR NUMBER…',
                style: QuestTypography.osLabelSmall),
          ],
        ),
      ),
    );
  }
}
