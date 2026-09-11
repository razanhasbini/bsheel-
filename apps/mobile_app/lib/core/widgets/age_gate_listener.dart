import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/onboarding/presentation/providers/onboarding_provider.dart';
import '../providers/auth_session_provider.dart';
import '../providers/profile_repository_provider.dart';
import '../router/app_router.dart';
import '../router/route_names.dart';
import '../services/sign_out_service.dart';

/// Asks the 13+ question exactly once per account, after sign-in and after
/// onboarding.
///
/// It used to be a dialog in front of the phone / Apple / Google buttons,
/// which meant a returning user answered it on every sign-in and a refusal
/// aborted a flow that had not yet created anything to refuse. Now the
/// answer lives on the profile (`profiles.age_verified`), the account is
/// created or opened first, and this asks only while that flag is false —
/// so once per account, however many devices or sign-ins follow. The email
/// signup form still carries its own checkbox and arrives here already
/// answered.
///
/// Three things the first version of this got wrong, all load-bearing:
///
/// - It read the flag from the *public* profile (`profiles/:id`), which
///   deliberately omits `age_verified`, so every user looked unconfirmed
///   forever and the dialog came back after every YES. The flag is read
///   from `profiles/me`, and only here.
/// - It asked wherever the user happened to be — during the splash, on each
///   walkthrough step. A `go()` underneath an open dialog removes the
///   dialog, so it kept reappearing. It now waits for the shell: signed in,
///   onboarding complete, on a real page.
/// - It treated a dialog dismissed *by navigation* (`showDialog` → null)
///   as "I'm under 13" and signed the user out. Only an explicit NO does
///   that; null means "not answered", and it simply asks again later.
///
/// Mounted in `MaterialApp.router`'s builder chain, which sits *above* the
/// router's Navigator — so the dialog is opened from the router's own root
/// navigator rather than from this widget's context.
class AgeGateListener extends ConsumerStatefulWidget {
  const AgeGateListener({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AgeGateListener> createState() => _AgeGateListenerState();
}

class _AgeGateListenerState extends ConsumerState<AgeGateListener> {
  /// The user id this process has already asked (or is asking) — one fetch
  /// and at most one dialog per sign-in, whatever else re-triggers below.
  String? _askedFor;

  /// True from the decision to ask until the answer is recorded, so a
  /// route change or profile refetch mid-dialog cannot stack a second copy.
  bool _inFlight = false;

  GoRouter? _router;

  /// Routes where the question must NOT appear: the splash (its `go` to
  /// home would swallow the dialog), the auth pages (nobody is signed in),
  /// the phone callback (transient), the phone gate and the walkthrough
  /// (each step navigates, and the gate has its own job to finish first).
  static const _quietRoutes = {
    RoutePaths.splash,
    RoutePaths.login,
    RoutePaths.signup,
    RoutePaths.forgotPassword,
    RoutePaths.resetPassword,
    RoutePaths.phoneSigninCallback,
    RoutePaths.verifyPhone,
    RoutePaths.onboardingWalkthrough,
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Route changes are the trigger that matters: the walkthrough's final
      // `go(home)` is when the question becomes appropriate, and no
      // provider emits for that.
      _router = ref.read(appRouterProvider);
      _router!.routerDelegate.addListener(_evaluate);
      _evaluate();
    });
  }

  @override
  void dispose() {
    _router?.routerDelegate.removeListener(_evaluate);
    super.dispose();
  }

  bool _onQuietRoute() {
    final router = _router;
    if (router == null) return true;
    final path = router.routerDelegate.currentConfiguration.uri.path;
    return _quietRoutes.contains(path);
  }

  Future<void> _evaluate() async {
    if (!mounted || _inFlight) return;
    final user = ref.read(authSessionProvider);
    if (user == null) {
      // Signed out: the next sign-in (same or different account) is asked
      // afresh — the server flag, not this field, is what makes it "once".
      _askedFor = null;
      return;
    }
    if (_askedFor == user.id) return;
    // Onboarding first. Null means the pref has not loaded; wait for it.
    if (ref.read(onboardingCompleteProvider).valueOrNull != true) return;
    if (_onQuietRoute()) return;

    _askedFor = user.id;
    _inFlight = true;
    try {
      final own = await ref.read(profileRepositoryProvider).getOwnProfile();
      if (!mounted) return;
      if (own.ageVerified) return; // Already answered on some device.
      await _ask();
    } catch (e) {
      // Could not read the flag: do not guess either way. Try again on the
      // next route change.
      AppLogger.warning('[AgeGate] Could not read the profile: $e');
      _askedFor = null;
    } finally {
      _inFlight = false;
    }
  }

  Future<void> _ask() async {
    // Let the navigation that brought us here finish its frame, so the
    // dialog is not opened over a page that is still being replaced.
    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (!mounted || _onQuietRoute()) {
      _askedFor = null;
      return;
    }
    final navContext = _router?.routerDelegate.navigatorKey.currentContext;
    // The `.mounted` check is on the navigator's context itself, which is
    // the one the lint (rightly) wants guarded.
    if (navContext == null || !navContext.mounted) {
      _askedFor = null;
      return;
    }

    final confirmed = await showDialog<bool>(
      context: navContext,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: AlertDialog(
          backgroundColor: QuestColors.cardBg(ctx),
          title: Text(
            'AGE CHECK',
            style: QuestTypography.osHeadlineSmall.copyWith(
              color: QuestColors.text(ctx),
            ),
          ),
          content: Text(
            'Bsheel is for players aged 13 and older. Are you 13 or older?',
            style: QuestTypography.osBodyMedium.copyWith(
              color: QuestColors.textDim(ctx),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(
                "I'M UNDER 13",
                style: QuestTypography.osHeadlineSmall.copyWith(
                  fontSize: 14,
                  color: QuestColors.osTextSecondary,
                ),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(
                'YES, 13+',
                style: QuestTypography.osHeadlineSmall.copyWith(
                  fontSize: 14,
                  color: QuestColors.osPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;

    switch (confirmed) {
      case true:
        try {
          await ref.read(profileRepositoryProvider).confirmAge();
        } catch (e) {
          // Nothing persisted, so the next route change asks again rather
          // than silently treating an unrecorded "yes" as recorded.
          AppLogger.warning('[AgeGate] Could not record the answer: $e');
          _askedFor = null;
        }
      case false:
        // Under 13: the account cannot stay signed in. The message goes to
        // the app-level messenger, which outlives the screen change — read
        // through a fresh context, since the sign-out replaces the route
        // stack the previous one belonged to.
        await signOutAndCleanup(ref);
        final messengerContext =
            _router?.routerDelegate.navigatorKey.currentContext;
        if (messengerContext != null && messengerContext.mounted) {
          ScaffoldMessenger.maybeOf(messengerContext)?.showSnackBar(
            const SnackBar(
              content: Text('Bsheel is for players aged 13 and older.'),
            ),
          );
        }
      case null:
        // The page under the dialog was replaced (a `go` somewhere) before
        // anyone answered. Not a refusal — ask again on a calmer route.
        _askedFor = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    // A sign-in or sign-out is a trigger too; the route listener alone
    // would miss a session that changes without a navigation.
    ref.listen(authSessionProvider, (_, __) => _evaluate());
    ref.listen(onboardingCompleteProvider, (_, __) => _evaluate());
    return widget.child;
  }
}
