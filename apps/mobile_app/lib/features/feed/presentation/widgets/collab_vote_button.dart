import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app_core/app_core.dart';
import 'package:app_models/app_models.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:supabase_contracts/supabase_contracts.dart';

import '../../../../core/utils/account_lock_guard.dart';
import '../../../collab/data/collab_providers.dart';

/// Arcade-pop avatar vote button used by the reels card's action rail and
/// the post detail page's participants list. Tap toggles the vote with a
/// synchronous busy guard, scale-pop animation and an optimistic count
/// update; long-press opens the user's profile when a handler is provided.
class CollabVoteButton extends ConsumerStatefulWidget {
  const CollabVoteButton({
    super.key,
    required this.member,
    required this.groupId,
    required this.accentColor,
    required this.isLeader,
    required this.onVoteApplied,
    this.onLongPress,
    this.avatarSize = 36,
    this.tapBoxWidth = 56,
    this.tapBoxHeight = 72,
    this.showCountChip = true,
  });

  final CollabFeedMember member;
  final String groupId;
  final Color accentColor;
  final bool isLeader;
  final VoidCallback? onLongPress;
  final void Function({required bool nowVoted, required int newCount})
      onVoteApplied;

  /// Visible avatar diameter (the surrounding ring + glow add ~6pt extra).
  final double avatarSize;

  /// Hit-box width — kept >= 44pt to satisfy Apple HIG even when avatar shrinks.
  final double tapBoxWidth;

  /// Hit-box height — has to fit the avatar + count chip stack.
  final double tapBoxHeight;

  /// When false, only the tappable avatar renders (no count chip below).
  /// The parent is then responsible for displaying the vote count wherever
  /// it wants (e.g. as a big "funky" number next to the row in the detail
  /// page participants header).
  final bool showCountChip;

  @override
  ConsumerState<CollabVoteButton> createState() => CollabVoteButtonState();
}

class CollabVoteButtonState extends ConsumerState<CollabVoteButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;
  late final Animation<double> _countScale;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    // Avatar scale — subtle squash + bounce.
    _scale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 0.85)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 30,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 0.85, end: 1.18)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 30,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.18, end: 1.0)
            .chain(CurveTween(curve: Curves.elasticOut)),
        weight: 40,
      ),
    ]).animate(_ctrl);
    // Count "pop" — bigger arc so the new number reads clearly, then
    // springs smoothly back to its resting size.
    _countScale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 1.7)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 25,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.7, end: 1.0)
            .chain(CurveTween(curve: Curves.elasticOut)),
        weight: 75,
      ),
    ]).animate(_ctrl);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  /// Public wrapper so external widgets (e.g. a vote chip in a list row)
  /// can fire the same vote toggle as a direct avatar tap.
  Future<void> triggerToggle() => _toggle();

  Future<void> _toggle() async {
    final submissionId = widget.member.submissionId;
    if (_busy || submissionId == null || widget.groupId.isEmpty) return;
    if (guardAccountAction(context, ref)) return;

    // Migration 0149 restored 0097's server-side `status = 'approved'`
    // requirement on vote_collab. get_feed emits EVERY group member —
    // including ones whose submission is still pending or was rejected —
    // so without this check those buttons would optimistically flip and
    // then roll back with an error toast. Fail fast and quietly instead.
    if (widget.member.submissionStatus != SubmissionStatus.approved) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("You can't vote on this until it's approved."),
        ),
      );
      return;
    }

    // Synchronously block the next tap BEFORE any optimistic UI mutation —
    // otherwise two taps in the same frame both pass the `_busy` check.
    _busy = true;

    final wasVoted = widget.member.viewerVoted;
    final prevCount = widget.member.voteCount;
    final newCount = (prevCount + (wasVoted ? -1 : 1)).clamp(0, 1 << 30);

    widget.onVoteApplied(nowVoted: !wasVoted, newCount: newCount);
    _ctrl.forward(from: 0);
    if (mounted) setState(() {});

    try {
      final repo = ref.read(collabRepositoryProvider);
      if (wasVoted) {
        await repo.unvoteCollab(widget.groupId, submissionId);
      } else {
        await repo.voteCollab(widget.groupId, submissionId);
      }
    } catch (e) {
      widget.onVoteApplied(nowVoted: wasVoted, newCount: prevCount);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_voteErrorMessage(e))),
        );
      }
    } finally {
      _busy = false;
      if (mounted) setState(() {});
    }
  }

  /// Map a `vote_collab` failure to a one-line user message. The RPC raises:
  ///   42501 → not authenticated, or account suspended/banned
  ///   P0001 → not eligible for voting, or hourly vote cap reached
  ///   P0002 → group not found
  /// Anything else (network, JSON, etc.) falls through to a generic line.
  ///
  /// Order matters: the rate-limit and account-status cases share their
  /// SQLSTATE with the generic branches below, so they must be matched on
  /// message text FIRST or the user gets told the post is ineligible when
  /// they were really just throttled.
  String _voteErrorMessage(Object error) {
    final msg = error.toString();
    if (msg.contains('rate limit')) {
      return 'Slow down — too many votes. Try again shortly.';
    }
    if (msg.contains('Account not active')) {
      return 'Your account is paused, so voting is disabled.';
    }
    if (msg.contains('42501') || msg.contains('Authentication required')) {
      return 'Sign in again to vote.';
    }
    if (msg.contains('P0001') ||
        msg.contains('not eligible for voting') ||
        msg.contains('does not belong to that group')) {
      return 'This submission can no longer be voted on.';
    }
    if (msg.contains('P0002') || msg.contains('Group not found')) {
      return 'This group is no longer available.';
    }
    return 'Vote failed — try again';
  }

  @override
  Widget build(BuildContext context) {
    final voted = widget.member.viewerVoted;
    final accent = widget.accentColor;
    final name = widget.member.displayName.isNotEmpty
        ? widget.member.displayName
        : widget.member.username;

    return Semantics(
      button: true,
      toggled: voted,
      label: voted
          ? 'Voted for $name. ${widget.member.voteCount} votes. Tap to remove vote.'
          : 'Vote for $name. ${widget.member.voteCount} votes.',
      child: GestureDetector(
        onTap: _toggle,
        onLongPress: widget.onLongPress,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: widget.tapBoxWidth,
          height: widget.tapBoxHeight,
          child: ScaleTransition(
            scale: _scale,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        // Match the profile-page avatar shape: rounded
                        // rectangle (radiusSm), not a circle. Image fills
                        // the frame because PixelAvatar uses BoxFit.cover.
                        borderRadius:
                            BorderRadius.circular(QuestSpacing.radiusSm + 2),
                        border: Border.all(
                          color: voted ? accent : accent.withAlpha(40),
                          width: voted ? 2.5 : 1.5,
                        ),
                        boxShadow: voted
                            ? [
                                BoxShadow(
                                  color: accent.withAlpha(140),
                                  blurRadius: 10,
                                  spreadRadius: 1,
                                ),
                              ]
                            : null,
                      ),
                      child: PixelAvatar(
                        username: widget.member.username,
                        imageUrl: widget.member.avatarUrl,
                        size: widget.avatarSize,
                      ),
                    ),
                    if (widget.isLeader)
                      const Positioned(
                        top: -10,
                        right: -8,
                        child: LeaderCrown(size: 22),
                      ),
                  ],
                ),
                if (widget.showCountChip) ...[
                  const SizedBox(height: 4),
                  // Count pops big on tap then springs back smoothly.
                  ScaleTransition(
                    scale: _countScale,
                    child: Text(
                      widget.member.voteCount.toString(),
                      style: TextStyle(
                        fontFamily: 'Syne',
                        color: voted ? accent : accent.withAlpha(220),
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                        height: 1.0,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Hand-drawn leader crown ────────────────────────────────────────────────

/// Doodle-style crown for the versus leader. CustomPainter so the strokes
/// look hand-drawn instead of an emoji glyph that picks up the system
/// font's color/scale weirdly. Public so the post-details media overlay
/// and any future leader badge can reuse the same artwork.
class LeaderCrown extends StatelessWidget {
  const LeaderCrown({super.key, this.size = 22});
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _CrownPainter()),
    );
  }
}

class _CrownPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Crown silhouette: 3 spikes + a base band.
    final body = Path()
      ..moveTo(w * 0.10, h * 0.85)        // bottom-left of band
      ..lineTo(w * 0.10, h * 0.55)        // up to left spike base
      ..lineTo(w * 0.27, h * 0.20)        // up to left spike tip
      ..lineTo(w * 0.43, h * 0.55)        // down between spikes
      ..lineTo(w * 0.50, h * 0.10)        // up to centre tip
      ..lineTo(w * 0.57, h * 0.55)        // down between spikes
      ..lineTo(w * 0.73, h * 0.20)        // up to right spike tip
      ..lineTo(w * 0.90, h * 0.55)        // down to right spike base
      ..lineTo(w * 0.90, h * 0.85)        // bottom-right of band
      ..close();

    // Yellow fill — Arcade-Pop accent.
    final fill = Paint()..color = QuestColors.accentYellow;
    canvas.drawPath(body, fill);

    // Chunky ink stroke.
    final stroke = Paint()
      ..color = QuestColors.osBorderStrong
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(body, stroke);

    // Three "jewel" dots in the band.
    final dot = Paint()..color = QuestColors.osRed;
    final dotStroke = Paint()
      ..color = QuestColors.osBorderStrong
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    final r = w * 0.06;
    for (final cx in [w * 0.27, w * 0.50, w * 0.73]) {
      canvas.drawCircle(Offset(cx, h * 0.72), r, dot);
      canvas.drawCircle(Offset(cx, h * 0.72), r, dotStroke);
    }
  }

  @override
  bool shouldRepaint(covariant _CrownPainter oldDelegate) => false;
}
