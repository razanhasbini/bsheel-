import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app_contracts/app_contracts.dart';

import 'package:app_core/app_core.dart';
import 'package:app_models/app_models.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../../core/providers/auth_session_provider.dart';
import '../../../../core/backend/app_backend.dart';
import '../../../../core/router/route_names.dart';
import '../../../submissions/data/submission_providers.dart';
import '../../data/quest_providers.dart';
import 'package:go_router/go_router.dart';

// ─────────────────────────────────────────────────────────────────────────
// Streak Flame
//
// A chunky animated flame that gently sways + scales when the user's
// streak hits a milestone (3 / 7 / 14 / 30). Designed to live inline
// next to a streak number — drop it in wherever the count is rendered.
// Pure visual; doesn't itself fetch streak data.
// ─────────────────────────────────────────────────────────────────────────

class BsStreakFlame extends StatefulWidget {
  const BsStreakFlame({
    super.key,
    required this.streak,
    this.size = 28,
  });

  final int streak;
  final double size;

  @override
  State<BsStreakFlame> createState() => _BsStreakFlameState();
}

class _BsStreakFlameState extends State<BsStreakFlame>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  // Tier kicks in at every milestone so the flame visually grows with
  // the user's commitment level — 1d = tiny ember, 30+ = inferno.
  int _tier() {
    if (widget.streak >= 30) return 4;
    if (widget.streak >= 14) return 3;
    if (widget.streak >= 7) return 2;
    if (widget.streak >= 3) return 1;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final tier = _tier();
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        // Sway: ~3deg back-and-forth. Scale: ±4%.
        final t = (_ctrl.value - 0.5) * 2; // -1..1
        final angle = t * 0.05;
        final scale = 1 + t * 0.04;
        return Transform.rotate(
          angle: angle,
          child: Transform.scale(
            scale: scale,
            child: SizedBox(
              width: widget.size * (1 + tier * 0.06),
              height: widget.size * (1 + tier * 0.06),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Outer glow that swells with tier
                  Icon(
                    Icons.local_fire_department_rounded,
                    size: widget.size * (1 + tier * 0.06),
                    color: tier >= 4
                        ? QuestColors.osRed
                        : tier >= 2
                            ? QuestColors.accentYellow
                            : QuestColors.osRed.withAlpha(180),
                  ),
                  // Inner hot core appears only at higher tiers
                  if (tier >= 2)
                    Positioned(
                      bottom: widget.size * 0.18,
                      child: Container(
                        width: widget.size * 0.32,
                        height: widget.size * 0.32,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [
                              QuestColors.pureWhite.withAlpha(220),
                              QuestColors.accentYellow.withAlpha(0),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Mood of the day
//
// One-tap emoji pick that records "today's mood" client-side. Renders
// nothing if a mood was already picked today. Persists across launches
// via SharedPreferences. Stays purely on-device until we want to publish
// to profile / feed surfaces.
// ─────────────────────────────────────────────────────────────────────────

// ─────────────────────────────────────────────────────────────────────────
// Weekly XP meter
//
// Horizontal bar charting how much XP the user pulled in over the last 7
// days against a 300-XP weekly goal. Uses the user's already-loaded
// quest history so it adds zero network calls — just a fold over
// `approvedAt` timestamps.
// ─────────────────────────────────────────────────────────────────────────

class BsWeeklyXpMeter extends StatelessWidget {
  const BsWeeklyXpMeter({
    super.key,
    required this.questHistory,
    this.weeklyGoal = 500,
  });

  final List<UserQuestModel> questHistory;

  /// 500 in the frame's `340 / 500`.
  final int weeklyGoal;

  int _xpThisWeek() {
    final now = DateTime.now();
    final weekStart = now.subtract(const Duration(days: 7));
    return questHistory
        .where((q) =>
            q.status == 'approved' &&
            q.completedAt != null &&
            q.completedAt!.isAfter(weekStart))
        .fold<int>(0, (sum, q) => sum + (q.quest?.xpReward ?? 0));
  }

  /// One filled segment per completed seventh of the goal. The frame draws
  /// seven discrete cells, not a continuous bar.
  static const int _segments = 7;

  @override
  Widget build(BuildContext context) {
    final ink = QuestColors.text(context);
    final xp = _xpThisWeek();
    final progress = (xp / weeklyGoal).clamp(0.0, 1.0);
    final filled = (progress * _segments).floor().clamp(0, _segments);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: QuestColors.osCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: ink, width: 2),
        // Sky, 4px. The frame gives this card a coloured shadow because
        // the weekly goal is the one thing on the lower half of home that
        // is still in play.
        boxShadow: QuestSpacing.hardShadow(4, color: QuestColors.osCool),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Text(
                  'WEEKLY XP',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: QuestTypography.osLabelMedium.copyWith(
                    color: QuestColors.osTextSecondary,
                    fontSize: 10,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '$xp / $weeklyGoal',
                maxLines: 1,
                style: QuestTypography.osLabelMedium.copyWith(
                  color: QuestColors.osTextPrimary,
                  fontSize: 11,
                  letterSpacing: 0.4,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ArcadeSegments(total: _segments, filled: filled),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Friend activity strip
//
// Horizontal carousel of the 5 most recent feed posts from users the
// viewer follows. Uses `feedProvider` with `feedScopeFollowing` so we
// piggyback on the network call FeedPage will make anyway, no new
// queries. Each tap deep-links to that post's details.
// ─────────────────────────────────────────────────────────────────────────

/// Lightweight row representing one user currently mid-quest.
/// Backed by the `get_following_active_quests` RPC (see migration 0138).
class ActiveQuestPeer {
  ActiveQuestPeer({
    required this.userId,
    required this.username,
    required this.displayName,
    required this.avatarUrl,
    required this.questTitle,
    required this.xpReward,
    required this.expiresAt,
  });

  final String userId;
  final String username;
  final String displayName;
  final String? avatarUrl;
  final String questTitle;
  final int xpReward;
  final DateTime expiresAt;

  factory ActiveQuestPeer.fromRow(Map<String, dynamic> row) {
    return ActiveQuestPeer(
      userId: row['user_id'] as String,
      username: (row['username'] as String?) ?? '',
      displayName: (row['display_name'] as String?) ?? '',
      avatarUrl: row['avatar_url'] as String?,
      questTitle: (row['quest_title'] as String?) ?? '',
      xpReward: (row['xp_reward'] as int?) ?? 0,
      expiresAt: DateTime.parse(row['expires_at'] as String),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Quest of the Day — admin-curated ticket
//
// Powered by `get_quest_of_the_day` RPC (migration 0139). One row per UTC
// day; the RPC returns null when nothing's queued so the home page just
// hides the widget. Cached SWR-style: a transient fetch failure keeps the
// previous ticket on screen instead of flashing empty.
// ─────────────────────────────────────────────────────────────────────────

QuestOfTheDayModel? _lastGoodQotd;

/// Drops the module-scoped SWR cache. Call on sign-out so the next user
/// on the same device can't see the previous user's QOTD state briefly.
void resetQotdCache() {
  _lastGoodQotd = null;
}

final questOfTheDayProvider = FutureProvider<QuestOfTheDayModel?>((ref) async {
  try {
    final row = await AppBackend.repositories.quests
        .getQuestOfTheDay()
        .timeout(const Duration(seconds: 6));
    if (row == null) {
      _lastGoodQotd = null;
      return null;
    }
    final fresh = QuestOfTheDayModel.fromRow(row);
    _lastGoodQotd = fresh;
    return fresh;
  } catch (e, st) {
    // Surface the parse / network failure so we can spot a regression
    // instead of silently swallowing it and rendering an empty page.
    AppLogger.warning('[QOTD] fetch/parse failed: $e\n$st');
    return _lastGoodQotd;
  }
});

final activeQuestPeersProvider =
    FutureProvider<List<ActiveQuestPeer>>((ref) async {
  // Keep dependency so auth changes re-evaluate this provider — the RPC
  // returns rows scoped to the current user's follow graph.
  ref.watch(authSessionProvider);
  try {
    final rows = await AppBackend.repositories.quests
        .getFollowingActiveQuests(limit: 12)
        .timeout(const Duration(seconds: 6));
    return rows.map(ActiveQuestPeer.fromRow).toList(growable: false);
  } catch (_) {
    // Migration not deployed yet, or transient network blip — show nothing
    // rather than spamming error UI on the home page. The completed-feed
    // tiles below will still render.
    return const [];
  }
});

class BsFriendActivityStrip extends ConsumerWidget {
  const BsFriendActivityStrip({super.key});

  String _timeLeft(DateTime expiresAt) {
    final d = expiresAt.difference(DateTime.now());
    if (d.isNegative || d.inMinutes < 1) return 'ending';
    if (d.inHours < 1) return '${d.inMinutes}m left';
    final h = d.inHours;
    final m = d.inMinutes - h * 60;
    return m == 0 ? '${h}h left' : '${h}h ${m}m';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ink = QuestColors.text(context);
    // Only show the 2 most recent LIVE questers — no completed/submitted
    // posts. Strip hides entirely when nobody is currently mid-quest so
    // the home page doesn't carry a stale "no activity" row.
    final activePeers = (ref.watch(activeQuestPeersProvider).valueOrNull ??
            const <ActiveQuestPeer>[])
        .take(2)
        .toList();

    if (activePeers.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            'WHAT EVERYONE IS DOING',
            style: QuestTypography.labelSmall.copyWith(
              color: ink.withAlpha(160),
              fontSize: 10,
              letterSpacing: 1.4,
            ),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 142,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 2),
            itemCount: activePeers.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (_, i) {
              final peer = activePeers[i];
              return _ActiveChip(
                peer: peer,
                timeLabel: _timeLeft(peer.expiresAt),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// "Doing now" tile — visually distinct (violet accent + pulsing live
/// dot) from the completed-post tiles so the user reads it as a
/// real-time signal. Tap → open the questing user's profile.
class _ActiveChip extends StatelessWidget {
  const _ActiveChip({required this.peer, required this.timeLabel});

  final ActiveQuestPeer peer;
  final String timeLabel;

  @override
  Widget build(BuildContext context) {
    final ink = QuestColors.text(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => context.pushNamed(
        RouteNames.userProfile,
        pathParameters: {'userId': peer.userId},
      ),
      child: Container(
        width: 168,
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
        decoration: BoxDecoration(
          // Paper-light card so the title + status text read at a glance;
          // the violet border keeps "DOING NOW" tiles visually distinct
          // from the completed-feed tiles next to them in the strip.
          color: QuestColors.cardBg(context),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: QuestColors.osPrimary, width: 2),
          boxShadow: [
            BoxShadow(color: ink, offset: const Offset(3, 3), blurRadius: 0),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: QuestColors.osPrimary.withAlpha(40),
                  border: Border.all(color: ink, width: 2),
                ),
                clipBehavior: Clip.antiAlias,
                child: peer.avatarUrl != null && peer.avatarUrl!.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: peer.avatarUrl!,
                        fit: BoxFit.cover,
                        memCacheWidth: 56,
                      )
                    : Center(
                        child: Text(
                          peer.displayName.isNotEmpty
                              ? peer.displayName[0].toUpperCase()
                              : '?',
                          style: QuestTypography.labelSmall.copyWith(
                            color: ink,
                            fontSize: 11,
                          ),
                        ),
                      ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  peer.displayName.isNotEmpty
                      ? peer.displayName
                      : '@${peer.username}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: QuestTypography.labelMedium.copyWith(
                    color: ink,
                    fontSize: 11,
                    letterSpacing: 0.1,
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 6),
            // Live indicator + status text.
            Row(children: [
              const _PulseDot(color: QuestColors.osRed),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  'DOING NOW',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: QuestTypography.labelSmall.copyWith(
                    color: QuestColors.osRedText,
                    fontSize: 9,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 4),
            Text(
              peer.questTitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: QuestTypography.headlineSmall.copyWith(
                color: ink,
                fontSize: 12,
                height: 1.2,
                letterSpacing: 0.2,
              ),
            ),
            const Spacer(),
            Text(
              timeLabel,
              style: QuestTypography.labelSmall.copyWith(
                color: ink.withAlpha(140),
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PulseDot extends StatefulWidget {
  const _PulseDot({required this.color});
  final Color color;

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        final opacity = 0.45 + 0.55 * _c.value;
        return Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.color.withValues(alpha: opacity),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Quest of the Day — ticket widget
//
// Visual port of qotd_ticket_widget.html: yellow accent-fill card with
// ink border + hard drop-shadow, two cream notches at the mid-line, a
// dashed divider, the quest title + XP badge, a compact key/value strip,
// a decorative barcode, and a chunky black "Accept" CTA with a coral seal.
//
// The widget is silent when there's no QOTD for today (RPC returned
// null) — caller can mount it unconditionally; nothing renders.
// ─────────────────────────────────────────────────────────────────────────
// Quest of the Day — ticket
//
// `03-home-no-quest.jpg` draws this as one flat sky card: a cream glyph
// tile, two lines of text, and a dark TAKE button. The bespoke ticket art
// this replaced — a dashed perforation, two punched side notches, a
// barcode, a zigzag tear line, an XP stamp and four key/value cells — was
// roughly 700 lines of CustomPainter standing in for a row, and none of it
// is in the frame.
//
// The routing it carried is not gone: a first-time rejection still turns
// the right-hand slot into APPEAL, which is one of the three routes into
// `submission_status_page`.
//
// The widget is silent when there's no QOTD for today (the RPC returned
// null) — callers can mount it unconditionally.
// ─────────────────────────────────────────────────────────────────────────

enum _QotdStatus {
  fresh, // not yet accepted; show accept CTA
  inProgress, // active assignment, not yet submitted
  submitted, // submitted, awaiting admin review
  approved, // approved — bonus XP awarded
  rejected, // rejected — appeal option available
  reRejected, // rejected again post-appeal; no further appeals
  expired, // timer ran out without submission; no re-accept
}

class BsQuestOfDayTicket extends ConsumerStatefulWidget {
  const BsQuestOfDayTicket({super.key, this.onAccept});

  /// Called when the accept CTA is tapped. The caller assigns the quest
  /// (via `assign_specific_quest`); the widget awaits the returned Future
  /// so the CTA stays disabled while the RPC is in flight.
  final Future<void> Function(QuestOfTheDayModel qotd)? onAccept;

  @override
  ConsumerState<BsQuestOfDayTicket> createState() => _BsQuestOfDayTicketState();
}

class _BsQuestOfDayTicketState extends ConsumerState<BsQuestOfDayTicket> {
  // Guards against double-tap firing two assign RPCs. Held true until the
  // parent's onAccept Future resolves; provider invalidation then flips
  // the slot away from TAKE so a second tap is impossible.
  bool _accepting = false;

  // One-shot timer that fires at the next UTC midnight to invalidate
  // questOfTheDayProvider, so a long-lived app picks up tomorrow's quest
  // without the user needing to pull-to-refresh.
  Timer? _midnightRefresh;

  @override
  void initState() {
    super.initState();
    _scheduleMidnightRefresh();
  }

  @override
  void dispose() {
    _midnightRefresh?.cancel();
    super.dispose();
  }

  void _scheduleMidnightRefresh() {
    _midnightRefresh?.cancel();
    final now = DateTime.now().toUtc();
    final nextUtcMidnight = DateTime.utc(now.year, now.month, now.day + 1);
    // 1s slack so the server has rolled over by the time we re-fetch.
    final delay = nextUtcMidnight.difference(now) + const Duration(seconds: 1);
    _midnightRefresh = Timer(delay, () {
      if (!mounted) return;
      ref.invalidate(questOfTheDayProvider);
      ref.invalidate(activeQuestProvider);
      ref.invalidate(questHistoryProvider);
      _scheduleMidnightRefresh();
    });
  }

  Future<void> _handleAccept() async {
    if (_accepting) return;
    final qotd = ref.read(questOfTheDayProvider).valueOrNull;
    if (qotd == null) return;
    setState(() => _accepting = true);
    HapticFeedback.mediumImpact();
    try {
      await widget.onAccept?.call(qotd);
    } finally {
      if (mounted) setState(() => _accepting = false);
    }
  }

  /// Resolve which status to render by comparing the QOTD's quest id
  /// against the user's active quest + recent history. The most recent
  /// `UserQuest` keyed on the same quest_id wins.
  _QotdStatus _resolveStatus(QuestOfTheDayModel qotd) {
    final active = ref.watch(activeQuestProvider).valueOrNull;
    final history =
        ref.watch(questHistoryProvider).valueOrNull ?? const <UserQuestModel>[];
    final submissions = ref.watch(userSubmissionsProvider).valueOrNull ??
        const <SubmissionModel>[];

    // A live active quest for this QOTD is the freshest signal — prefer it
    // over any history join.
    if (active != null && active.questId == qotd.questId) {
      if (active.status == UserQuestStatus.assigned) {
        return _QotdStatus.inProgress;
      }
      if (active.status == UserQuestStatus.submitted) {
        return _QotdStatus.submitted;
      }
    }

    // Otherwise scan history for the most recent attempt on this quest,
    // limited to the last 48h so an old completion doesn't bleed into
    // today's stub.
    final cutoff = DateTime.now().subtract(const Duration(hours: 48));
    final candidates = history
        .where((q) => q.questId == qotd.questId && q.assignedAt.isAfter(cutoff))
        .toList()
      ..sort((a, b) => b.assignedAt.compareTo(a.assignedAt));
    if (candidates.isEmpty) return _QotdStatus.fresh;
    final latest = candidates.first;
    switch (latest.status) {
      case UserQuestStatus.assigned:
        return _QotdStatus.inProgress;
      case UserQuestStatus.submitted:
        return _QotdStatus.submitted;
      case UserQuestStatus.approved:
        return _QotdStatus.approved;
      case UserQuestStatus.rejected:
        // Differentiate a first-time rejection (can appeal) from a
        // post-appeal re-rejection (no further appeals) by looking up the
        // matching submission's appealed flag.
        final wasAppealed = submissions.any(
          (s) => s.userQuestId == latest.id && s.appealed,
        );
        return wasAppealed ? _QotdStatus.reRejected : _QotdStatus.rejected;
      case UserQuestStatus.expired:
        return _QotdStatus.expired;
      default:
        return _QotdStatus.fresh;
    }
  }

  /// The user_quest id an appeal or detail view would navigate to. Null
  /// when no matching row exists, which is what keeps the APPEAL slot a
  /// promise the API can honour.
  String? _matchingUserQuestId(QuestOfTheDayModel qotd) {
    final active = ref.read(activeQuestProvider).valueOrNull;
    if (active != null && active.questId == qotd.questId) return active.id;
    final history =
        ref.read(questHistoryProvider).valueOrNull ?? const <UserQuestModel>[];
    final cutoff = DateTime.now().subtract(const Duration(hours: 48));
    final candidates = history
        .where((q) => q.questId == qotd.questId && q.assignedAt.isAfter(cutoff))
        .toList()
      ..sort((a, b) => b.assignedAt.compareTo(a.assignedAt));
    return candidates.isEmpty ? null : candidates.first.id;
  }

  @override
  Widget build(BuildContext context) {
    final qotd = ref.watch(questOfTheDayProvider).valueOrNull;
    if (qotd == null) return const SizedBox.shrink();

    final status = _resolveStatus(qotd);
    final ink = QuestColors.text(context);
    // Ink on sky. White on sky measures 1.9:1.
    final fg = QuestColors.onAccent(QuestColors.osCool);
    final canAppeal =
        status == _QotdStatus.rejected && _matchingUserQuestId(qotd) != null;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      decoration: BoxDecoration(
        color: QuestColors.osCool,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: ink, width: 2),
        boxShadow: QuestSpacing.shadowMd,
      ),
      child: Row(
        children: [
          // 34pt cream tile, r9 — the frame's ticket glyph.
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: QuestColors.osBg,
              borderRadius: BorderRadius.circular(QuestSpacing.radiusGlyph),
              border: Border.all(color: ink, width: 2),
            ),
            child: Icon(
              Icons.confirmation_number_outlined,
              color: ink,
              size: 18,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'QUEST OF THE DAY · +${qotd.bonusXp} XP',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: QuestTypography.osLabelSmall.copyWith(
                    color: fg,
                    fontSize: 9,
                    letterSpacing: 0.9,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  qotd.questTitle.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: QuestTypography.osHeadlineMedium.copyWith(
                    color: fg,
                    fontSize: 15,
                    letterSpacing: -0.3,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 11),
          _TicketAction(
            status: status,
            busy: _accepting,
            onAccept: _handleAccept,
            onAppeal: canAppeal
                ? () {
                    final id = _matchingUserQuestId(qotd);
                    if (id == null) return;
                    context.pushNamed(
                      RouteNames.submissionStatus,
                      pathParameters: {'id': id},
                    );
                  }
                : null,
          ),
        ],
      ),
    );
  }
}

/// The ticket's right-hand slot: `h38`, `r9`, **ink ground with cream
/// text** when it is an action, and a flat cream chip when it is only a
/// state.
///
/// Cream on the ink fill is correct — that is an ink panel, not an accent.
class _TicketAction extends StatelessWidget {
  const _TicketAction({
    required this.status,
    required this.busy,
    required this.onAccept,
    required this.onAppeal,
  });

  final _QotdStatus status;
  final bool busy;
  final VoidCallback onAccept;
  final VoidCallback? onAppeal;

  @override
  Widget build(BuildContext context) {
    final ink = QuestColors.text(context);

    final (String label, VoidCallback? onTap) = switch (status) {
      _QotdStatus.fresh => ('TAKE', busy ? null : onAccept),
      _QotdStatus.rejected when onAppeal != null => ('APPEAL', onAppeal),
      _QotdStatus.rejected => ('REJECTED', null),
      _QotdStatus.inProgress => ('LIVE', null),
      _QotdStatus.submitted => ('IN REVIEW', null),
      _QotdStatus.approved => ('DONE', null),
      _QotdStatus.reRejected => ('FINAL', null),
      _QotdStatus.expired => ('MISSED', null),
    };

    final actionable = onTap != null;
    final chip = Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 13),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: actionable ? ink : QuestColors.osBg,
        borderRadius: BorderRadius.circular(QuestSpacing.radiusGlyph),
        border: Border.all(color: ink, width: 2),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: QuestTypography.osButtonText.copyWith(
          color: actionable ? QuestColors.osBg : QuestColors.osTextSecondary,
          fontSize: 12,
          letterSpacing: 0.6,
        ),
      ),
    );

    if (!actionable) return chip;
    return Semantics(
      button: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        // 38 painted, 44 tappable.
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: QuestSpacing.minTouchTarget,
          ),
          child: Center(child: chip),
        ),
      ),
    );
  }
}
