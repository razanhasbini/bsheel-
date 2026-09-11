import 'package:app_core/app_core.dart';
import 'package:app_models/app_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/auth_session_provider.dart';
import '../providers/current_profile_provider.dart';
import '../providers/profile_repository_provider.dart';
import '../router/app_router.dart';
import '../services/sign_out_service.dart';

/// Asks the 13+ question exactly once per account, after sign-in.
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
  /// True from the moment we decide to ask until the answer is recorded, so
  /// a profile refetch mid-dialog cannot stack a second copy on top.
  bool _inFlight = false;

  @override
  void initState() {
    super.initState();
    // The profile may already be loaded by the time this mounts (warm
    // restart), in which case the listener below never fires for it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _maybeAsk(ref.read(currentProfileProvider).valueOrNull);
    });
  }

  Future<void> _maybeAsk(ProfileModel? profile) async {
    if (_inFlight || profile == null || profile.ageVerified) return;
    if (ref.read(authSessionProvider) == null) return;
    _inFlight = true;

    // Let the post-sign-in navigation settle first, so the dialog is not
    // torn down together with the login page it would otherwise open over.
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;
    final navContext = _rootNavigatorContext();
    // The `.mounted` check is on the navigator's context itself, which is
    // the one the lint (rightly) wants guarded — this widget's own
    // `mounted` says nothing about it.
    if (navContext == null || !navContext.mounted) {
      _inFlight = false;
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

    try {
      if (confirmed == true) {
        await ref.read(profileRepositoryProvider).confirmAge();
        // Refetch so the next emission carries ageVerified: true and this
        // never asks again.
        ref.invalidate(currentProfileProvider);
      } else {
        // Under 13: the account cannot stay signed in. The message goes to
        // the app-level messenger, which outlives the screen change — read
        // through a fresh context, since the sign-out just replaced the
        // route stack the previous one belonged to.
        await signOutAndCleanup(ref);
        final messengerContext = _rootNavigatorContext();
        if (messengerContext != null && messengerContext.mounted) {
          ScaffoldMessenger.maybeOf(messengerContext)?.showSnackBar(
            const SnackBar(
              content: Text('Bsheel is for players aged 13 and older.'),
            ),
          );
        }
      }
    } catch (e) {
      // Network hiccup recording the answer: nothing persisted, so the next
      // profile emission asks again rather than silently treating an
      // unrecorded "yes" as recorded.
      AppLogger.warning('[AgeGate] Could not record the answer: $e');
    } finally {
      _inFlight = false;
    }
  }

  /// The router's root navigator's context, or null before the first frame
  /// or mid-teardown. Read fresh at each use rather than held across an
  /// await, so a context that outlived its route stack is never handed to a
  /// dialog or a messenger; callers still check `.mounted` at the use site.
  BuildContext? _rootNavigatorContext() =>
      ref.read(appRouterProvider).routerDelegate.navigatorKey.currentContext;

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<ProfileModel?>>(currentProfileProvider, (_, next) {
      final profile = next.valueOrNull;
      if (profile != null) _maybeAsk(profile);
    });
    return widget.child;
  }
}
