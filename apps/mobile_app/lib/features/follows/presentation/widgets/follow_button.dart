import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app_core/app_core.dart';
import '../../../../core/providers/current_profile_provider.dart';
import '../../../../core/services/analytics_service.dart';
import '../../../../core/utils/account_lock_guard.dart';
import '../../../../l10n/app_localizations.dart';
import '../../data/follows_providers.dart';

class FollowButton extends ConsumerStatefulWidget {
  const FollowButton({
    super.key,
    required this.targetUserId,
    this.expand = true,
  });

  final String targetUserId;

  /// When `true` the button fills the available width (recommended placement
  /// below the avatar row). Set to `false` for compact contexts.
  final bool expand;

  @override
  ConsumerState<FollowButton> createState() => _FollowButtonState();
}

class _FollowButtonState extends ConsumerState<FollowButton> {
  // Follow status now lives in `isFollowingProvider(targetUserId)` so the
  // shell-level follows realtime channel can refresh every visible button
  // when a row changes. Local `_busy` tracks just the in-flight toggle.
  bool _busy = false;
  bool _pressed = false;

  Future<void> _toggleFollow(bool isFollowing) async {
    if (_busy) return;
    // Run guards BEFORE the haptic so a rejected tap doesn't buzz the
    // user — buzzing only when the action will actually proceed makes
    // the feedback meaningful.
    // Self-follow defense — RLS rejects this, but callers occasionally
    // render the button on the viewer's own profile via deep link / list
    // bug. Block client-side so the user gets feedback, not silence.
    final me = ref.read(currentProfileProvider).valueOrNull;
    if (me != null && me.id == widget.targetUserId) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("You can't follow yourself.")),
      );
      return;
    }
    if (guardAccountAction(context, ref)) return;
    HapticFeedback.selectionClick();
    // UX-102: confirm before unfollow. Easy to misfire when the
    // FOLLOWED button is right next to the row's profile-tap area in
    // the followers/following list.
    if (isFollowing) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: QuestColors.cardBg(ctx),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: QuestColors.text(ctx), width: 2),
          ),
          title: Text('UNFOLLOW?',
              style: QuestTypography.headlineSmall
                  .copyWith(color: QuestColors.softRed)),
          content: Text(
            'You won\'t see their posts in your feed and they won\'t be notified.',
            style: QuestTypography.bodyMedium
                .copyWith(color: QuestColors.text(ctx)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('CANCEL',
                  style: QuestTypography.labelSmall
                      .copyWith(color: QuestColors.textDim(ctx))),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('UNFOLLOW',
                  style: QuestTypography.labelSmall
                      .copyWith(color: QuestColors.softRed)),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    setState(() => _busy = true);
    try {
      final repo = ref.read(followsRepositoryProvider);
      // Invalidate both sides' follow-counts caches so the FOLLOWERS /
      // FOLLOWING numbers on whichever profile the viewer lands on next
      // reflect the toggle, instead of the stale pre-toggle count. The
      // shell-level follows realtime channel will fire too, but only on
      // the actor's side — explicit invalidation keeps the UI snappy.
      void invalidateCounts() {
        ref.invalidate(followCountsProvider(widget.targetUserId));
        ref.invalidate(isFollowingProvider(widget.targetUserId));
        final me = ref.read(currentProfileProvider).valueOrNull;
        if (me != null) {
          ref.invalidate(followCountsProvider(me.id));
        }
      }

      if (isFollowing) {
        await repo.unfollow(widget.targetUserId);
        ref.read(analyticsProvider).unfollowed(widget.targetUserId);
        invalidateCounts();
        if (mounted) setState(() => _busy = false);
      } else {
        await repo.follow(widget.targetUserId);
        ref.read(analyticsProvider).followAdded(widget.targetUserId);
        invalidateCounts();
        if (mounted) setState(() => _busy = false);
        // Fire-and-forget notification — must not block the UI flip
        // back to "FOLLOWED" if FCM is slow or down.
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[Follow] Error: $e');
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(isFollowing
                  ? "Couldn't unfollow. Check your connection."
                  : "Couldn't follow. Check your connection.")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ink = QuestColors.text(context);
    final l = AppLocalizations.of(context)!;

    final followingAsync = ref.watch(isFollowingProvider(widget.targetUserId));
    final isFollowing = followingAsync.valueOrNull ?? false;
    final loading = _busy || followingAsync.isLoading;

    final bg =
        isFollowing ? QuestColors.cardBg(context) : QuestColors.osPrimary;
    final fg = isFollowing ? ink : QuestColors.osTextOnPrimary;
    final icon =
        isFollowing ? Icons.check_rounded : Icons.person_add_alt_1_rounded;

    final child = AnimatedContainer(
      duration: const Duration(milliseconds: 80),
      transform: Matrix4.translationValues(0, _pressed ? 3 : 0, 0),
      padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 20),
      decoration: BoxDecoration(
        color: loading ? bg.withAlpha(160) : bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: loading ? ink.withAlpha(120) : ink,
          width: 2,
        ),
        // UX-308: drop the chunky drop-shadow while loading so the
        // faded fill reads "disabled" instead of "active but greyed".
        boxShadow: (_pressed || loading)
            ? const []
            : [
                BoxShadow(
                  color: ink,
                  offset: const Offset(0, 3),
                  blurRadius: 0,
                ),
              ],
      ),
      child: Row(
        mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (loading)
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(fg),
              ),
            )
          else
            Icon(icon, size: 16, color: fg),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              (isFollowing ? l.followed : l.follow).toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Syne',
                fontVariations: const [FontVariation('wght', 800)],
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: fg,
                letterSpacing: 1.1,
                height: 1,
              ),
            ),
          ),
        ],
      ),
    );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: loading ? null : (_) => setState(() => _pressed = true),
      onTapUp: loading
          ? null
          : (_) {
              setState(() => _pressed = false);
              _toggleFollow(isFollowing);
            },
      onTapCancel: loading ? null : () => setState(() => _pressed = false),
      child: widget.expand
          ? SizedBox(width: double.infinity, child: child)
          : child,
    );
  }
}
