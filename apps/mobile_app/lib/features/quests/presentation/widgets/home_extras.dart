import 'dart:async';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:app_contracts/app_contracts.dart';

import 'package:app_core/app_core.dart';
import 'package:app_models/app_models.dart';

import '../../../../design/bs_widgets.dart';
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
                        ? QuestColors.softRed
                        : tier >= 2
                            ? QuestColors.accentYellow
                            : QuestColors.softRed.withAlpha(180),
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

final _moodTodayProvider = FutureProvider<String?>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  final saved = prefs.getString('mood_pick_v1');
  if (saved == null) return null;
  final parts = saved.split('|');
  if (parts.length != 2) return null;
  // parts[0] = ISO date, parts[1] = emoji. Only valid if today.
  final today = DateTime.now();
  final picked = DateTime.tryParse(parts[0]);
  if (picked == null) return null;
  final sameDay = picked.year == today.year &&
      picked.month == today.month &&
      picked.day == today.day;
  return sameDay ? parts[1] : null;
});

class BsMoodOfDayCard extends ConsumerWidget {
  const BsMoodOfDayCard({super.key});

  static const _moods = ['😴', '😎', '🔥', '😬', '🥹', '🎯'];

  Future<void> _pick(WidgetRef ref, String emoji) async {
    HapticFeedback.lightImpact();
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now();
    final dateOnly =
        DateTime(today.year, today.month, today.day).toIso8601String();
    await prefs.setString('mood_pick_v1', '$dateOnly|$emoji');
    ref.invalidate(_moodTodayProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ink = QuestColors.text(context);
    final moodAsync = ref.watch(_moodTodayProvider);
    final picked = moodAsync.valueOrNull;

    if (picked != null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: QuestColors.cardBg(context),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: ink, width: 2),
          boxShadow: [
            BoxShadow(color: ink, offset: const Offset(3, 3), blurRadius: 0),
          ],
        ),
        child: Row(children: [
          Text(picked, style: const TextStyle(fontSize: 28, height: 1)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              "TODAY'S VIBE LOCKED IN",
              style: QuestTypography.labelSmall.copyWith(
                color: ink.withAlpha(160),
                fontSize: 10,
                letterSpacing: 1.4,
              ),
            ),
          ),
        ]),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      decoration: BoxDecoration(
        color: QuestColors.cardBg(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: ink, width: 2),
        boxShadow: [
          BoxShadow(color: ink, offset: const Offset(3, 3), blurRadius: 0),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "HOW YOU FEELING TODAY?",
            style: QuestTypography.labelSmall.copyWith(
              color: ink.withAlpha(180),
              fontSize: 10,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (final e in _moods)
                GestureDetector(
                  onTap: () => _pick(ref, e),
                  behavior: HitTestBehavior.opaque,
                  child: BsMinTouch(
                    child: Text(e,
                        style: const TextStyle(fontSize: 28, height: 1)),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

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
    this.weeklyGoal = 300,
  });

  final List<UserQuestModel> questHistory;
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

  @override
  Widget build(BuildContext context) {
    final ink = QuestColors.text(context);
    final xp = _xpThisWeek();
    final progress = (xp / weeklyGoal).clamp(0.0, 1.0);
    final hitGoal = xp >= weeklyGoal;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: QuestColors.cardBg(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: ink, width: 2),
        boxShadow: [
          BoxShadow(color: ink, offset: const Offset(3, 3), blurRadius: 0),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text(
              'THIS WEEK',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: QuestTypography.labelSmall.copyWith(
                color: ink.withAlpha(160),
                fontSize: 10,
                letterSpacing: 1.4,
              ),
            ),
            const Spacer(),
            Flexible(
              child: Text(
                '$xp / $weeklyGoal XP',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: QuestTypography.headlineSmall.copyWith(
                  color: hitGoal ? QuestColors.osSuccessText : ink,
                  fontSize: 13,
                  letterSpacing: 0.3,
                ),
              ),
            ),
          ]),
          const SizedBox(height: 10),
          // Track + fill, chunky-bordered to match Arcade Pop bar treatments.
          LayoutBuilder(builder: (_, c) {
            return Stack(children: [
              Container(
                width: c.maxWidth,
                height: 18,
                decoration: BoxDecoration(
                  color: ink.withAlpha(15),
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: ink, width: 1.5),
                ),
              ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 600),
                curve: Curves.easeOut,
                width: math.max(8, c.maxWidth * progress),
                height: 18,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: hitGoal
                        ? [QuestColors.successGreen, QuestColors.successGreen]
                        : [QuestColors.osPrimary, QuestColors.softRed],
                  ),
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: ink, width: 1.5),
                ),
              ),
            ]);
          }),
          const SizedBox(height: 6),
          Text(
            hitGoal
                ? 'WEEKLY GOAL CLEARED. KEEP COOKING.'
                : 'GOAL: $weeklyGoal XP BY SUNDAY',
            style: QuestTypography.labelSmall.copyWith(
              color: ink.withAlpha(140),
              fontSize: 10,
              letterSpacing: 1.2,
            ),
          ),
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
                  border: Border.all(color: ink, width: 1.5),
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
              const _PulseDot(color: QuestColors.softRed),
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

// QOTD ticket interaction states. Drives which body the ticket renders
// + which copy goes on the bottom-half (the "stub" after cut).
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

  /// Called when the accept CTA is tapped. Caller is responsible for
  /// actually assigning the quest (e.g. via the existing
  /// `assign_specific_quest` RPC). The widget awaits the returned
  /// Future so the CTA stays disabled while the RPC is in-flight.
  final Future<void> Function(QuestOfTheDayModel qotd)? onAccept;

  @override
  ConsumerState<BsQuestOfDayTicket> createState() => _BsQuestOfDayTicketState();
}

class _BsQuestOfDayTicketState extends ConsumerState<BsQuestOfDayTicket> {
  // Guards against double-tap firing two assign RPCs. Held true until
  // the parent's onAccept Future resolves; provider invalidation then
  // flips the body away from the fresh CTA so a second tap is impossible.
  bool _accepting = false;

  // One-shot timer that fires at the next UTC midnight to invalidate
  // questOfTheDayProvider so a long-lived app picks up tomorrow's quest
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
    // Add 1s slack so the server has rolled over by the time we re-fetch.
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

  String _difficultyStars(String difficulty) {
    switch (difficulty.toLowerCase()) {
      case 'easy':
        return '★ ☆ ☆ ☆';
      case 'hard':
        return '★ ★ ★ ☆';
      case 'medium':
      default:
        return '★ ★ ☆ ☆';
    }
  }

  String _lengthLabel(int hours) {
    if (hours <= 0) return 'NO LIMIT';
    if (hours < 24) return '${hours}H';
    final d = hours ~/ 24;
    final rem = hours % 24;
    return rem == 0 ? '${d}D' : '${d}D ${rem}H';
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

    // If there's a live active quest for this QOTD, prefer that signal —
    // it reflects the current state before any history join.
    if (active != null && active.questId == qotd.questId) {
      if (active.status == UserQuestStatus.assigned) {
        return _QotdStatus.inProgress;
      }
      if (active.status == UserQuestStatus.submitted) {
        return _QotdStatus.submitted;
      }
    }

    // Otherwise scan history for the most recent attempt on this quest.
    // Limit to anything assigned in the last 48h so an old completion
    // doesn't bleed into today's stub.
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
        // Differentiate first-time rejection (can appeal) from
        // post-appeal re-rejection (no further appeals) by looking
        // up the matching submission's appealed flag.
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

  /// Resolve the user_quest id we'd navigate to for an appeal / detail
  /// view. Falls back to null if we can't find a matching row.
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

  // Visual constant: keep the top half (eyebrow + ticket # + dashed cut
  // line) at a fixed pixel height so the side notches can be positioned
  // accurately at the cut line without measuring at runtime.
  static const double _topHalfHeight = 38;

  @override
  Widget build(BuildContext context) {
    final qotdAsync = ref.watch(questOfTheDayProvider);
    final qotd = qotdAsync.valueOrNull;
    if (qotd == null) return const SizedBox.shrink();

    final status = _resolveStatus(qotd);
    final ink = QuestColors.text(context);
    final pageBg = QuestColors.bg(context);
    const navy = QuestColors.osTextPrimary;
    final isTorn = status != _QotdStatus.fresh;

    // Body content for the current status. No animation between states —
    // the provider invalidation that flips the body is instant.
    final body = status == _QotdStatus.fresh
        ? _QotdBodyFresh(
            qotd: qotd,
            navy: navy,
            ink: ink,
            difficultyStars: _difficultyStars(qotd.questDifficulty),
            lengthLabel: _lengthLabel(qotd.questDurationHours),
            busy: _accepting,
            onAccept: _handleAccept,
          )
        : _QotdBodyStub(
            qotd: qotd,
            status: status,
            navy: navy,
            ink: ink,
            // APPEAL only makes sense when the latest attempt was a
            // first-time rejection AND we can locate the user_quest row
            // to deep-link into. Re-rejected and expired stubs are
            // terminal — no action.
            canAppeal: status == _QotdStatus.rejected &&
                _matchingUserQuestId(qotd) != null,
            onAppeal: () {
              final id = _matchingUserQuestId(qotd);
              if (id == null) return;
              context.pushNamed(
                RouteNames.submissionStatus,
                pathParameters: {'id': id},
              );
            },
          );

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(color: ink, offset: const Offset(4, 4), blurRadius: 0),
        ],
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Top half — perforation line below it is dashed when
              // fresh and a zigzag/torn pattern after the ticket has
              // been "punched".
              _QotdTopHalf(
                qotd: qotd,
                navy: navy,
                ink: ink,
                height: _topHalfHeight,
                torn: isTorn,
              ),
              body,
            ],
          ),
          // Side notches sit at the cut line — same y as the bottom edge
          // of the top half (height − notch radius).
          Positioned(
            left: -12,
            top: _topHalfHeight - 12,
            child: _Notch(bg: pageBg, ink: ink),
          ),
          Positioned(
            right: -12,
            top: _topHalfHeight - 12,
            child: _Notch(bg: pageBg, ink: ink),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Top half (ticket stub) — stays put during the cut animation; on cut
// completion it slightly tilts up to read as "torn".
// ─────────────────────────────────────────────────────────────────────────

class _QotdTopHalf extends StatelessWidget {
  const _QotdTopHalf({
    required this.qotd,
    required this.navy,
    required this.ink,
    required this.height,
    required this.torn,
  });

  final QuestOfTheDayModel qotd;
  final Color navy;
  final Color ink;
  final double height;
  // When true, the perforation line is rendered as a zigzag/torn edge
  // instead of the fresh-ticket dashed perforation. Visually confirms
  // the ticket has been "punched" without an animation.
  final bool torn;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Container(
        decoration: BoxDecoration(
          color: navy,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(22),
            topRight: Radius.circular(22),
          ),
          border: Border.all(color: ink, width: 2),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: Text(
                        "★ TODAY'S QUEST TICKET",
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: QuestTypography.labelSmall.copyWith(
                          color: QuestColors.accentYellow,
                          fontSize: 10,
                          letterSpacing: 1.4,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Ticket # is static; the clock ticks inside its own
                    // micro-widget so the rest of the top half doesn't
                    // rebuild every second. Mono digits keep the width
                    // constant as it ticks.
                    Flexible(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              '№ ${qotd.displayTicketNo}  ·  ',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontFamily: 'JetBrainsMono',
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: QuestColors.textPrimary,
                              ),
                            ),
                          ),
                          const _ResetClockText(
                            fontSize: 10,
                            color: QuestColors.textPrimary,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Perforation line — dashed for fresh tickets, zigzag for
            // tickets that have been "torn" (any non-fresh state).
            SizedBox(
              height: torn ? 8 : 2,
              child: CustomPaint(
                size: Size(double.infinity, torn ? 8 : 2),
                painter: torn
                    ? const _ZigzagLinePainter(color: QuestColors.accentYellow)
                    : const _DashedLinePainter(color: QuestColors.accentYellow),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Self-ticking countdown text. Owns its own Timer so the parent widget
// tree doesn't have to rebuild every second just to refresh this
// 6-character string. Drop wherever the live clock is needed.
class _ResetClockText extends StatefulWidget {
  const _ResetClockText({required this.fontSize, required this.color});

  final double fontSize;
  final Color color;

  @override
  State<_ResetClockText> createState() => _ResetClockTextState();
}

class _ResetClockTextState extends State<_ResetClockText> {
  Timer? _ticker;
  late Duration _untilReset;

  @override
  void initState() {
    super.initState();
    _untilReset = _calc();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _untilReset = _calc());
    });
  }

  Duration _calc() {
    final now = DateTime.now().toUtc();
    final nextUtcMidnight = DateTime.utc(now.year, now.month, now.day + 1);
    return nextUtcMidnight.difference(now);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final h = _untilReset.inHours.toString().padLeft(2, '0');
    final m = (_untilReset.inMinutes - _untilReset.inHours * 60)
        .toString()
        .padLeft(2, '0');
    final s = (_untilReset.inSeconds - _untilReset.inMinutes * 60)
        .toString()
        .padLeft(2, '0');
    return Text(
      '$h:$m:$s',
      style: TextStyle(
        fontFamily: 'JetBrainsMono',
        fontSize: widget.fontSize,
        fontWeight: FontWeight.w700,
        color: widget.color,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Body — "fresh" (pre-accept) variant
// ─────────────────────────────────────────────────────────────────────────

class _QotdBodyFresh extends StatelessWidget {
  const _QotdBodyFresh({
    required this.qotd,
    required this.navy,
    required this.ink,
    required this.difficultyStars,
    required this.lengthLabel,
    required this.busy,
    required this.onAccept,
  });

  final QuestOfTheDayModel qotd;
  final Color navy;
  final Color ink;
  final String difficultyStars;
  final String lengthLabel;
  final bool busy;
  final VoidCallback onAccept;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: navy,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(22),
          bottomRight: Radius.circular(22),
        ),
        border: Border(
          left: BorderSide(color: ink, width: 2),
          right: BorderSide(color: ink, width: 2),
          bottom: BorderSide(color: ink, width: 2),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Text(
                    qotd.questTitle,
                    style: QuestTypography.displayLarge.copyWith(
                      color: QuestColors.textPrimary,
                      fontSize: 22,
                      height: 1.05,
                      letterSpacing: -0.4,
                      fontWeight: FontWeight.w800,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 10),
                _XpStamp(xp: qotd.totalXpReward),
              ],
            ),
            const SizedBox(height: 12),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              childAspectRatio: 5,
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
              children: [
                _KvCell(
                  label: 'TYPE',
                  value: qotd.questCategory.isNotEmpty
                      ? qotd.questCategory.toUpperCase()
                      : 'SOLO',
                ),
                _KvCell(label: 'LENGTH', value: lengthLabel),
                // Live clock — self-ticks; doesn't trigger a body rebuild.
                const _KvLiveResetCell(),
                _KvCell(label: 'DIFFICULTY', value: difficultyStars),
              ],
            ),
            const SizedBox(height: 12),
            const SizedBox(
              height: 28,
              child: CustomPaint(
                size: Size(double.infinity, 28),
                painter: _BarcodePainter(color: QuestColors.accentYellow),
              ),
            ),
            const SizedBox(height: 12),
            _AcceptButton(onTap: onAccept, busy: busy),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Body — "stub" (post-accept) variant
// ─────────────────────────────────────────────────────────────────────────

class _QotdBodyStub extends StatelessWidget {
  const _QotdBodyStub({
    required this.qotd,
    required this.status,
    required this.navy,
    required this.ink,
    required this.canAppeal,
    required this.onAppeal,
  });

  final QuestOfTheDayModel qotd;
  final _QotdStatus status;
  final Color navy;
  final Color ink;
  final bool canAppeal;
  final VoidCallback onAppeal;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: navy,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(22),
          bottomRight: Radius.circular(22),
        ),
        border: Border(
          left: BorderSide(color: ink, width: 2),
          right: BorderSide(color: ink, width: 2),
          bottom: BorderSide(color: ink, width: 2),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 18, 14, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              qotd.questTitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: QuestTypography.headlineSmall.copyWith(
                color: QuestColors.textPrimary.withAlpha(180),
                fontSize: 15,
                decoration: (status == _QotdStatus.rejected ||
                        status == _QotdStatus.reRejected ||
                        status == _QotdStatus.expired)
                    ? TextDecoration.lineThrough
                    : null,
                decorationColor: QuestColors.textPrimary.withAlpha(100),
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: 12),
            _StatusStamp(status: status, qotd: qotd),
            if (canAppeal) ...[
              const SizedBox(height: 14),
              GestureDetector(
                onTap: onAppeal,
                behavior: HitTestBehavior.opaque,
                child: Container(
                  height: 44,
                  width: double.infinity,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: QuestColors.accentYellow,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: ink, width: 2),
                    boxShadow: [
                      BoxShadow(
                          color: ink,
                          offset: const Offset(3, 3),
                          blurRadius: 0),
                    ],
                  ),
                  child: Text(
                    'APPEAL THIS DECISION',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: QuestTypography.labelLarge.copyWith(
                      color: QuestColors.accentYellowInk,
                      fontSize: 12,
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// Big diagonal status stamp — sits inline in the stub. Uses the in-app
// palette: gold for "in progress", coral for rejection, green for
// approval, navy/yellow for submitted-awaiting-review.
class _StatusStamp extends StatelessWidget {
  const _StatusStamp({required this.status, required this.qotd});

  final _QotdStatus status;
  final QuestOfTheDayModel qotd;

  ({String label, Color bg, Color fg, IconData icon}) _style() {
    switch (status) {
      case _QotdStatus.inProgress:
        return (
          label: 'DAILY QUEST · IN PROGRESS',
          bg: QuestColors.accentYellow,
          fg: QuestColors.accentYellowInk,
          icon: Icons.timer_outlined,
        );
      case _QotdStatus.submitted:
        return (
          label: 'DAILY QUEST · SUBMITTED',
          bg: QuestColors.osPrimary,
          fg: QuestColors.onAccent(QuestColors.osPrimary),
          icon: Icons.send_rounded,
        );
      case _QotdStatus.approved:
        return (
          label: 'DAILY QUEST · APPROVED  +${qotd.totalXpReward} XP',
          bg: QuestColors.successGreen,
          fg: QuestColors.onAccent(QuestColors.successGreen),
          icon: Icons.check_circle_rounded,
        );
      case _QotdStatus.rejected:
        return (
          label: 'DAILY QUEST · REJECTED',
          bg: QuestColors.softRed,
          fg: QuestColors.onAccent(QuestColors.softRed),
          icon: Icons.cancel_rounded,
        );
      case _QotdStatus.reRejected:
        return (
          label: 'DAILY QUEST · REJECTED ×2  · FINAL',
          bg: QuestColors.softRed,
          fg: QuestColors.onAccent(QuestColors.softRed),
          icon: Icons.block_rounded,
        );
      case _QotdStatus.expired:
        return (
          label: 'DAILY QUEST · EXPIRED',
          bg: QuestColors.osTextPrimary,
          fg: QuestColors.textPrimary,
          icon: Icons.hourglass_disabled_rounded,
        );
      case _QotdStatus.fresh:
        // Never rendered, but the switch has to be exhaustive.
        return (
          label: '',
          bg: Colors.transparent,
          fg: Colors.transparent,
          icon: Icons.help_outline,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _style();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: s.bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: QuestColors.osTextPrimary.withAlpha(160), width: 1.5),
      ),
      child: Row(
        children: [
          Icon(s.icon, color: s.fg, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              s.label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: QuestTypography.labelLarge.copyWith(
                color: s.fg,
                fontSize: 12,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Static tap-to-accept CTA. Solid yellow fill, dark ink label, no
// progress animation — single tap fires onTap. While `busy` is true the
// tap is swallowed and the label reads "ACCEPTING…" so a double-tap
// can't fire two assign RPCs.
class _AcceptButton extends StatelessWidget {
  const _AcceptButton({required this.onTap, required this.busy});

  final VoidCallback onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    const ink = QuestColors.osTextPrimary;
    return GestureDetector(
      onTap: busy ? null : onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: QuestColors.accentYellow,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: ink, width: 2),
        ),
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                busy ? Icons.hourglass_top_rounded : Icons.touch_app_rounded,
                size: 18,
                color: ink,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  busy ? 'ACCEPTING…' : 'ACCEPT QUEST',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: QuestTypography.labelLarge.copyWith(
                    color: ink,
                    fontSize: 12,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Clippers were removed when the layout switched from a Stack-with-
// overlap to a Column. Each half now uses asymmetric BorderRadius on
// its own Container — same visual result, half the cost per frame.

class _Notch extends StatelessWidget {
  const _Notch({required this.bg, required this.ink});

  final Color bg;
  final Color ink;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: bg,
        shape: BoxShape.circle,
        border: Border.all(color: ink, width: 2),
      ),
    );
  }
}

class _XpStamp extends StatelessWidget {
  const _XpStamp({required this.xp});

  final int xp;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: QuestColors.accentYellowInk,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '+$xp',
            style: const TextStyle(
              color: QuestColors.accentYellow,
              fontSize: 16,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
              height: 1,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'XP',
            style: TextStyle(
              fontFamily: 'JetBrainsMono',
              color: QuestColors.accentYellow.withAlpha(180),
              fontSize: 8,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}

// Variant of _KvCell whose value is a self-ticking clock. Keeps the
// per-second setState scoped to the 8-character text node, so the rest
// of the body subtree (GridView, CustomPaints, etc.) doesn't rebuild
// every second.
class _KvLiveResetCell extends StatelessWidget {
  const _KvLiveResetCell();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          'RESETS IN',
          style: TextStyle(
            fontFamily: 'JetBrainsMono',
            fontSize: 8,
            fontWeight: FontWeight.w500,
            letterSpacing: 1.2,
            color: QuestColors.accentYellow.withAlpha(190),
            height: 1,
          ),
        ),
        const SizedBox(height: 2),
        const _ResetClockText(fontSize: 11, color: QuestColors.textPrimary),
      ],
    );
  }
}

class _KvCell extends StatelessWidget {
  const _KvCell({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    // Navy-card colours: muted yellow eyebrow, full-white value so the
    // pairs read clearly without competing with the title.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          label,
          style: TextStyle(
            fontFamily: 'JetBrainsMono',
            fontSize: 8,
            fontWeight: FontWeight.w500,
            letterSpacing: 1.2,
            color: QuestColors.accentYellow.withAlpha(190),
            height: 1,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            fontFamily: 'DMSans',
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            color: QuestColors.textPrimary,
            letterSpacing: 0.2,
            height: 1.1,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

class _DashedLinePainter extends CustomPainter {
  const _DashedLinePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.square;
    const dash = 5.0;
    const gap = 4.0;
    double x = 0;
    final y = size.height / 2;
    while (x < size.width) {
      final end = math.min(x + dash, size.width);
      canvas.drawLine(Offset(x, y), Offset(end, y), paint);
      x = end + gap;
    }
  }

  @override
  bool shouldRepaint(_DashedLinePainter old) => old.color != color;
}

// Zigzag line — used instead of the dashed perforation once the ticket
// has been "torn" (any post-accept state). Top edge has small upward
// peaks pointing into the ticket above; bottom edge has matching peaks
// pointing into the body below — same painter, drawn as a single
// continuous zigzag at mid-height.
class _ZigzagLinePainter extends CustomPainter {
  const _ZigzagLinePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeJoin = StrokeJoin.miter
      ..strokeCap = StrokeCap.square;

    const peakWidth = 8.0;
    final h = size.height;
    final top = h * 0.15;
    final bottom = h * 0.85;

    final path = Path()..moveTo(0, h / 2);
    double x = 0;
    bool up = true;
    while (x < size.width) {
      x += peakWidth / 2;
      path.lineTo(x, up ? top : bottom);
      up = !up;
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_ZigzagLinePainter old) => old.color != color;
}

class _BarcodePainter extends CustomPainter {
  const _BarcodePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    // Deterministic pseudo-random pattern based on index so the barcode
    // looks irregular but stable across rebuilds.
    final widthsRule = [2.0, 2.0, 3.0, 1.0, 2.0, 3.0, 2.0, 1.0];
    final heightsRule = [1.0, 1.0, 1.0, 0.7, 0.8, 1.0, 0.9, 1.0];
    double x = 0;
    int i = 0;
    while (x < size.width) {
      final w = widthsRule[i % widthsRule.length];
      final hFrac = heightsRule[i % heightsRule.length];
      final h = size.height * hFrac;
      canvas.drawRect(
        Rect.fromLTWH(x, size.height - h, w, h),
        paint,
      );
      x += w + 2;
      i++;
    }
  }

  @override
  bool shouldRepaint(_BarcodePainter old) => old.color != color;
}

// ─────────────────────────────────────────────────────────────────────────
// Slot Reels Generator
//
// Replacement for the previous arcade slot machine + "GENERATE A QUEST"
// CTA. Visual port of design #03 (Slot Reels) from
// qotd_animated_widgets.html, recoloured to the Bsheel palette (coral
// gradient + gold accents on cream-paper reels).
//
// Animation budget: one shared 1.6s controller drives the bulbs +
// jackpot pulse + neon flicker. Each reel has its own infinitely-looping
// AnimationController at slightly different speeds so the letters never
// land in sync.
// ─────────────────────────────────────────────────────────────────────────

class BsSlotReelsGenerator extends StatefulWidget {
  const BsSlotReelsGenerator({
    super.key,
    required this.onGenerate,
  });

  final VoidCallback onGenerate;

  @override
  State<BsSlotReelsGenerator> createState() => _BsSlotReelsGeneratorState();
}

class _BsSlotReelsGeneratorState extends State<BsSlotReelsGenerator>
    with TickerProviderStateMixin {
  // Screen-specific colour — not a theme token.
  static const Color _deepCoral = Color(0xFFC72A48);

  // Reel letter strips. Three strips, deliberately offset so the same
  // glyph never lines up vertically across reels — the eye reads it as
  // motion even when frozen.
  static const _stripA = ['B', 'S', 'H', 'E', 'E', 'L', '?'];
  static const _stripB = ['Q', 'U', 'E', 'S', 'T', '!', 'B'];
  static const _stripC = ['1', '★', '7', '♦', '★', '✦', '★'];

  late final AnimationController _meta;
  late final AnimationController _reelA;
  late final AnimationController _reelB;
  late final AnimationController _reelC;

  @override
  void initState() {
    super.initState();
    _meta = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();
    _reelA = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
    _reelB = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1700),
    )..repeat();
    _reelC = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();
  }

  @override
  void dispose() {
    _meta.dispose();
    _reelA.dispose();
    _reelB.dispose();
    _reelC.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ink = QuestColors.text(context);

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(color: ink, offset: const Offset(4, 4), blurRadius: 0),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            // Coral → deeper coral gradient bg with a gold radial glow
            // from the top to match the HTML reference.
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [QuestColors.softRed, _deepCoral],
            ),
            border: Border.all(color: ink, width: 2),
            borderRadius: BorderRadius.circular(22),
          ),
          child: Stack(
            children: [
              // Top-center gold glow
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: const Alignment(0, -1.1),
                      radius: 0.95,
                      colors: [
                        QuestColors.accentYellow.withAlpha(96),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ── Marquee bulb row ──────────────────────────────
                  _MarqueeBulbs(meta: _meta),
                  const SizedBox(height: 10),
                  // ── Headline row: DAILY JACKPOT + meta ────────────
                  Row(
                    children: [
                      Flexible(
                        child: _NeonLabel(
                          meta: _meta,
                          text: '★ DAILY JACKPOT ★',
                        ),
                      ),
                      const Spacer(),
                      Flexible(
                        child: Text(
                          '№ ${_metaTicket()} · ROLL ME',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            fontFamily: 'JetBrainsMono',
                            color: QuestColors.onAccent(QuestColors.softRed),
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // ── Reels grid ────────────────────────────────────
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: ink,
                      borderRadius: BorderRadius.circular(14),
                      // Inner gold "win line" stroke — visually echoes
                      // the horizontal jackpot ribbon from the HTML.
                      border:
                          Border.all(color: QuestColors.accentYellow, width: 2),
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Row(
                          children: [
                            Expanded(
                                child: _Reel(strip: _stripA, ctrl: _reelA)),
                            const SizedBox(width: 8),
                            Expanded(
                                child: _Reel(strip: _stripB, ctrl: _reelB)),
                            const SizedBox(width: 8),
                            Expanded(
                                child: _Reel(strip: _stripC, ctrl: _reelC)),
                          ],
                        ),
                        // Mid-line glowing ribbon (the "win line")
                        IgnorePointer(
                          child: Container(
                            height: 2,
                            margin: const EdgeInsets.symmetric(horizontal: 6),
                            decoration: BoxDecoration(
                              color: QuestColors.accentYellow,
                              boxShadow: [
                                BoxShadow(
                                  color:
                                      QuestColors.accentYellow.withAlpha(180),
                                  blurRadius: 6,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  // ── CTA — jackpot pulse via animated ring ─────────
                  AnimatedBuilder(
                    animation: _meta,
                    builder: (_, __) {
                      // Pulse expands from 0 → 8 over the cycle, then resets.
                      final v = _meta.value;
                      final ringSize = 8.0 * (1 - ((v * 2 - 1).abs()));
                      final ringAlpha =
                          (180 * (1 - v)).clamp(0.0, 255.0).toInt();
                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          HapticFeedback.mediumImpact();
                          widget.onGenerate();
                        },
                        child: Container(
                          width: double.infinity,
                          padding: EdgeInsets.all(ringSize),
                          child: Container(
                            height: 48,
                            decoration: BoxDecoration(
                              color: QuestColors.accentYellow,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: ink, width: 2),
                              boxShadow: [
                                BoxShadow(
                                  color: QuestColors.accentYellow
                                      .withAlpha(ringAlpha),
                                  spreadRadius: ringSize,
                                  blurRadius: 0,
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                // Rotating lever icon
                                RotationTransition(
                                  turns: _meta,
                                  child: Container(
                                    width: 22,
                                    height: 22,
                                    decoration: BoxDecoration(
                                      color: ink,
                                      shape: BoxShape.circle,
                                    ),
                                    alignment: Alignment.center,
                                    child: const Text(
                                      '↻',
                                      style: TextStyle(
                                        color: QuestColors.accentYellow,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w800,
                                        height: 1,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Flexible(
                                  child: Text(
                                    'LOCK IN · GENERATE QUEST',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: QuestTypography.labelLarge.copyWith(
                                      color: QuestColors.accentYellowInk,
                                      fontSize: 13,
                                      letterSpacing: 1.2,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Vanity ticket number that ticks slowly so the row reads as
  // alive without committing to a real backend value.
  String _metaTicket() {
    final epochMin = DateTime.now().millisecondsSinceEpoch ~/ 60000;
    final n = (epochMin * 37) % 10000;
    return n.toString().padLeft(4, '0');
  }
}

class _MarqueeBulbs extends StatelessWidget {
  const _MarqueeBulbs({required this.meta});
  final AnimationController meta;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 8,
      child: AnimatedBuilder(
        animation: meta,
        builder: (_, __) {
          // Bulbs alternate odd/even phase so the marquee reads as a
          // running chase, not a single global blink.
          final v = meta.value;
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              for (int i = 0; i < 9; i++)
                Opacity(
                  opacity:
                      ((i.isEven ? v : 1 - v) * 0.75 + 0.25).clamp(0.0, 1.0),
                  child: Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: QuestColors.accentYellow,
                      boxShadow: [
                        BoxShadow(
                          color: QuestColors.accentYellow.withAlpha(180),
                          blurRadius: 6,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _NeonLabel extends StatelessWidget {
  const _NeonLabel({required this.meta, required this.text});
  final AnimationController meta;
  final String text;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: meta,
      builder: (_, __) {
        // Subtle 1Hz flicker: opacity dips to 70% at the midpoint and
        // the glow intensifies — same effect as @keyframes slotNeon.
        final dim = ((meta.value - 0.5).abs() * 2); // 0 → 1 → 0
        final glow = (0.7 + (1 - dim) * 0.3);
        return Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontFamily: 'Syne',
            fontSize: 13,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.6,
            color: QuestColors.accentYellow.withValues(alpha: glow),
            shadows: [
              Shadow(
                color: QuestColors.accentYellow
                    .withValues(alpha: 0.7 + (1 - dim) * 0.3),
                blurRadius: 6 + (1 - dim) * 12,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Reel extends StatelessWidget {
  const _Reel({required this.strip, required this.ctrl});

  final List<String> strip;
  final AnimationController ctrl;

  @override
  Widget build(BuildContext context) {
    const cellH = 56.0;
    final ink = QuestColors.text(context);
    return Container(
      height: cellH,
      decoration: BoxDecoration(
        color: QuestColors.bg(context),
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: AnimatedBuilder(
        animation: ctrl,
        builder: (_, __) {
          final progress = ctrl.value; // 0..1 across a full loop
          final totalH = cellH * strip.length;
          final offset = -progress * totalH;
          return ClipRect(
            child: OverflowBox(
              minHeight: totalH * 2,
              maxHeight: totalH * 2,
              child: Transform.translate(
                offset: Offset(0, offset),
                child: Column(
                  // Render the strip twice for seamless looping.
                  children: [
                    for (int rep = 0; rep < 2; rep++)
                      for (final glyph in strip)
                        SizedBox(
                          height: cellH,
                          child: Center(
                            child: Text(
                              glyph,
                              style: TextStyle(
                                color: ink,
                                fontSize: 28,
                                fontWeight: FontWeight.w800,
                                fontFamily: 'Syne',
                                letterSpacing: -0.3,
                                height: 1,
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
      ),
    );
  }
}
