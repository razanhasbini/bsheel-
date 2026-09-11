import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:app_core/app_core.dart';
import 'package:app_models/app_models.dart';
import 'package:app_contracts/app_contracts.dart';
import 'package:shared_ui/shared_ui.dart';
import '../../../../core/providers/auth_session_provider.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/router/safe_back.dart';
import '../../../../core/services/analytics_service.dart';
import '../../../../core/services/app_badge_service.dart';
import '../../../../core/utils/account_lock_guard.dart';
import '../providers/notifications_provider.dart';
import '../../../../l10n/app_localizations.dart';

/// Arcade Pop notifications page, matched to `export/mobile/11-notifications
/// .jpg` and the 19-card catalogue in `export/notifications/`.
///
/// Logic (auto mark-as-read, badge clearing, filtering, navigation per
/// notification type) is unchanged — the destinations in
/// [_navigateForNotification] are load-bearing, and `submission_rejected`
/// is the primary route into the appeal flow.
class NotificationsPage extends ConsumerStatefulWidget {
  const NotificationsPage({super.key});

  @override
  ConsumerState<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends ConsumerState<NotificationsPage> {
  int _filterIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await AppBadgeService.clear();
      final user = ref.read(authSessionProvider);
      if (user == null) return;
      // Skip the markAllAsRead RPC when there's nothing unread — saves a
      // round-trip on every page open and removes the badge-desync risk
      // when the user backs out before the RPC completes. Also skip
      // entirely for locked accounts (RLS rejects, badge desyncs).
      final unread = ref.read(unreadCountProvider).valueOrNull ?? 0;
      if (unread == 0 || isAccountLocked(ref)) return;
      try {
        await ref.read(notificationsRepositoryProvider).markAllAsRead(user.id);
        if (!mounted) return;
        ref.invalidate(unreadCountProvider);
        ref.invalidate(notificationsProvider);
      } catch (e) {
        AppLogger.error('[Notifications] markAllAsRead failed', e);
        // Don't invalidate on failure — the badge would briefly show 0
        // then snap back to the real count, which is worse than just
        // leaving the count untouched.
      }
    });
  }

  List<NotificationModel> _filtered(List<NotificationModel> all) {
    if (_filterIndex == 0) return all;
    return all.where((n) {
      switch (_filterIndex) {
        case 1:
          return n.type == NotificationType.reactionReceived ||
              n.type == NotificationType.reactionMilestone ||
              n.type == NotificationType.newFollower ||
              n.type == NotificationType.newComment ||
              n.type == NotificationType.commentReply ||
              n.type == NotificationType.mention ||
              n.type == NotificationType.followQuestCompleted ||
              n.type == NotificationType.collabJoined ||
              n.type == NotificationType.leaderboardOvertaken ||
              n.type == NotificationType.top10Entry;
        case 2:
          return n.type == NotificationType.questAssigned ||
              n.type == NotificationType.questExpired ||
              n.type == NotificationType.questTimerWarning ||
              n.type == NotificationType.streakAtRisk;
        case 3:
          return n.type == NotificationType.submissionApproved ||
              n.type == NotificationType.submissionRejected ||
              n.type == NotificationType.levelUp ||
              n.type == NotificationType.announcement ||
              n.type == NotificationType.newSubmission ||
              n.type == NotificationType.appealSubmitted ||
              n.type == NotificationType.collabPartnerApproved ||
              n.type == NotificationType.pendingReviewReminder;
        default:
          return true;
      }
    }).toList();
  }

  static const EdgeInsets _listPadding = EdgeInsets.fromLTRB(
    QuestSpacing.screenPadding,
    8,
    QuestSpacing.screenPadding,
    24,
  );

  @override
  Widget build(BuildContext context) {
    // Mount the realtime subscription — keeps the list + badge in sync
    // with incoming notifications without requiring a pull-to-refresh.
    ref.watch(notificationsRealtimeProvider);
    final l = AppLocalizations.of(context)!;
    final filters = [l.all, l.social, l.quests, l.rewards];
    final notificationsAsync = ref.watch(notificationsProvider);
    final ink = QuestColors.text(context);

    return Scaffold(
      backgroundColor: QuestColors.bg(context),
      body: Column(
        children: [
          // ── Header ────────────────────────────────────────────────
          // The render draws a 42pt white icon button at r11 with a 3px
          // ink shadow, then the page title in Syne 800 23. Nothing else
          // sits on this row.
          Padding(
            padding: EdgeInsets.only(
              top: MediaQuery.of(context).padding.top + 14,
              bottom: 12,
              left: QuestSpacing.screenPadding,
              right: QuestSpacing.screenPadding,
            ),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () => safeBack(context),
                  behavior: HitTestBehavior.opaque,
                  // 44pt hit box around a 42pt paint box: the design draws
                  // the smaller square, the touch floor is non-negotiable.
                  child: SizedBox(
                    width: QuestSpacing.minTouchTarget,
                    height: QuestSpacing.minTouchTarget,
                    child: Center(
                      child: Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: QuestColors.cardBg(context),
                          borderRadius: BorderRadius.circular(11),
                          border: Border.all(color: ink, width: 2),
                          boxShadow: QuestSpacing.shadowSm,
                        ),
                        child: Icon(Icons.arrow_back_rounded,
                            color: ink, size: 18),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Text(
                    l.notifications.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: QuestTypography.osDisplaySmall.copyWith(
                      color: ink,
                      fontSize: 23,
                      letterSpacing: -0.6,
                      height: 1.1,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Filter chips ────────────────────────────────────────────
          SizedBox(
            height: QuestSpacing.minTouchTarget,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(
                  horizontal: QuestSpacing.screenPadding),
              itemCount: filters.length,
              itemBuilder: (context, i) {
                final active = i == _filterIndex;
                return GestureDetector(
                  onTap: () => setState(() => _filterIndex = i),
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding:
                        EdgeInsets.only(right: i < filters.length - 1 ? 6 : 0),
                    child: Center(
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 7),
                        decoration: BoxDecoration(
                          // The render draws the selected filter as an ink
                          // chip with cream text, not a gold one. Gold means
                          // "waiting on you" in this design; spending it on a
                          // tab selection weakens it where it matters.
                          color: active ? ink : QuestColors.cardBg(context),
                          borderRadius: BorderRadius.circular(11),
                          border: Border.all(color: ink, width: 2),
                        ),
                        child: Text(
                          filters[i].toUpperCase(),
                          style: QuestTypography.osLabelSmall.copyWith(
                            letterSpacing: 0.8,
                            height: 1.2,
                            color: active ? QuestColors.osBg : ink,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 6),

          // ── Content ────────────────────────────────────────────────
          Expanded(
            child: notificationsAsync.when(
              loading: () => const ArcadeSkeletonList(
                itemCount: 5,
                itemHeight: 80,
                spacing: 10,
                padding: _listPadding,
              ),
              error: (e, _) => _ErrorState(
                message: l.failedToLoad,
                retryLabel: l.retry,
                onRetry: () => ref.invalidate(notificationsProvider),
              ),
              data: (allNotifications) {
                final notifications = _filtered(allNotifications);
                return RefreshIndicator(
                  color: QuestColors.osRed,
                  backgroundColor: QuestColors.cardBg(context),
                  onRefresh: () async => ref.invalidate(notificationsProvider),
                  child: notifications.isEmpty
                      ? ListView(
                          padding: _listPadding,
                          children: [_EmptyState(title: l.noNewSignals)],
                        )
                      : ListView.separated(
                          // Keyed by the active filter so scroll position is
                          // preserved when the user toggles ALL ↔ SOCIAL etc.,
                          // instead of snapping back to the top on every tap.
                          key: PageStorageKey<int>(_filterIndex),
                          padding: _listPadding,
                          itemCount: notifications.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: _NotificationCard.gap),
                          itemBuilder: (context, index) {
                            final n = notifications[index];
                            return _NotificationCard(
                              type: n.type,
                              title: n.title,
                              body: n.body,
                              actorUsername: n.actorUsername,
                              actorAvatarUrl: n.actorAvatarUrl,
                              isRead: n.isRead,
                              timeAgo: timeAgo(n.createdAt),
                              onTap: () => _handleTap(n),
                            );
                          },
                        ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleTap(NotificationModel n) async {
    // Wrap the read-mark in try/catch so a transient RLS/network blip
    // doesn't (a) silently swallow the failure and leave the unread state
    // stale OR (b) block the navigation. Navigate either way; only
    // invalidate the providers if the mark actually succeeded.
    if (!n.isRead) {
      try {
        await ref.read(notificationsRepositoryProvider).markAsRead(n.id);
        if (mounted) {
          ref.invalidate(notificationsProvider);
          ref.invalidate(unreadCountProvider);
        }
      } catch (e) {
        AppLogger.warning('[Notifications] markAsRead failed for ${n.id}: $e');
      }
    }
    if (!mounted) return;
    ref.read(analyticsProvider).notificationTapped(n.type);
    _navigateForNotification(context, n);
  }

  void _navigateForNotification(
      BuildContext context, NotificationModel notification) {
    final refId = notification.referenceId;
    // UX-201: every type either has a destination or falls back to /home.
    // The previous `default: break` and the missing-refId branches dead-
    // ended on a no-op tap; users would tap repeatedly thinking the app
    // froze. Now every path navigates somewhere sensible.
    switch (notification.type) {
      case NotificationType.questAssigned:
      case NotificationType.questExpired:
      case NotificationType.questTimerWarning:
      case NotificationType.pendingReviewReminder:
      case NotificationType.streakAtRisk:
        context.goNamed(RouteNames.home);
      // Journey notifications carry the RUN as their reference, so a tap
      // lands on the journey itself. Sending them to Home and throwing a
      // modal is what left people asking what had changed.
      // A hidden quest that just opened: land on the quest itself, since it
      // may belong to no journey at all.
      case NotificationType.hiddenQuestDiscovered:
        if (refId != null) {
          context.pushNamed(RouteNames.questDetails,
              pathParameters: {'id': refId});
        } else {
          context.goNamed(RouteNames.home);
        }
      case NotificationType.journeyStageUnlocked:
      case NotificationType.journeyTeammateAdvanced:
      case NotificationType.journeyCompleted:
        if (refId != null) {
          context.pushNamed(RouteNames.journeyDetail,
              pathParameters: {'runId': refId});
        } else {
          context.goNamed(RouteNames.home);
        }
      case NotificationType.submissionApproved:
      case NotificationType.submissionRejected:
      case NotificationType.newSubmission:
      case NotificationType.appealSubmitted:
        if (refId != null) {
          context.pushNamed(RouteNames.submissionStatus,
              pathParameters: {'id': refId});
        } else {
          context.goNamed(RouteNames.home);
        }
      case NotificationType.reactionReceived:
      case NotificationType.reactionMilestone:
      case NotificationType.newComment:
      case NotificationType.commentReply:
      case NotificationType.mention:
      case NotificationType.followQuestCompleted:
        if (refId != null) {
          context.pushNamed(RouteNames.feedPostDetails,
              pathParameters: {'id': refId});
        } else {
          // Mention/comment without a target post — drop the user on the
          // notifications page (already where they are) is annoying;
          // route to feed instead.
          context.goNamed(RouteNames.feed);
        }
      case NotificationType.newFollower:
        if (notification.actorId != null) {
          context.pushNamed(RouteNames.userProfile,
              pathParameters: {'userId': notification.actorId!});
        } else {
          context.goNamed(RouteNames.profile);
        }
      case NotificationType.leaderboardOvertaken:
      case NotificationType.top10Entry:
        context.goNamed(RouteNames.leaderboard);
      case NotificationType.levelUp:
        context.goNamed(RouteNames.profile);
      default:
        // Catch-all (announcement and any future types) lands on /home
        // so taps never become silent no-ops.
        context.goNamed(RouteNames.home);
    }
  }
}

// ── Card ────────────────────────────────────────────────────────────────────

/// One notification, drawn as the render draws it: the **whole card** is
/// tinted by what the notification means, and every line of type on it is
/// picked by [QuestColors.onAccent] so contrast holds on every ground.
///
/// Read/unread is carried by **border weight and shadow only** — the fill
/// says what the notification is about, never whether it has been opened,
/// and the body text is never dimmed for having been looked at.
class _NotificationCard extends StatelessWidget {
  const _NotificationCard({
    required this.type,
    required this.title,
    required this.body,
    required this.actorUsername,
    required this.actorAvatarUrl,
    required this.isRead,
    required this.timeAgo,
    required this.onTap,
  });

  final String type;
  final String title;
  final String body;
  final String? actorUsername;
  final String? actorAvatarUrl;
  final bool isRead;
  final String timeAgo;
  final VoidCallback onTap;

  /// Gap between cards in the list.
  static const double gap = 10;

  /// Radius, shadow depth and padding read off
  /// `export/mobile/11-notifications.jpg`.
  static const double _radius = 14;
  static const double _shadowDepth = 4;
  static const EdgeInsets _padding = EdgeInsets.symmetric(
    horizontal: 14,
    vertical: 13,
  );

  /// The ground for a notification type.
  ///
  /// Read one-by-one off `export/notifications/notif-01.jpg` …
  /// `notif-19.jpg`, which is one card per type. Colour maps to **meaning**:
  ///
  /// | Ground | Means | Types |
  /// |---|---|---|
  /// | jade | cleared | `submission_approved`, `collab_partner_approved` |
  /// | coral | rejected / urgent | `submission_rejected`, `quest_timer_warning`, `leaderboard_overtaken` |
  /// | gold | a person has to act | `appeal_submitted`, `quest_assigned`, `top_10_entry` |
  /// | violet | progression | `level_up`, `new_follower`, `collab_joined` |
  /// | sky | you were named | `mention` |
  /// | cream + dashed | spent, nothing to do | `quest_expired` |
  /// | white | informational | everything else |
  ///
  /// `collab_joined` and `collab_partner_approved` have no card in the
  /// catalogue; they take the ground of the bucket they belong to.
  static Color _ground(String type) => switch (type) {
        NotificationType.submissionApproved => QuestColors.osSuccess,
        NotificationType.collabPartnerApproved => QuestColors.osSuccess,
        NotificationType.submissionRejected => QuestColors.osRed,
        NotificationType.questTimerWarning => QuestColors.osRed,
        NotificationType.leaderboardOvertaken => QuestColors.osRed,
        NotificationType.appealSubmitted => QuestColors.osAccent,
        NotificationType.questAssigned => QuestColors.osAccent,
        NotificationType.top10Entry => QuestColors.osAccent,
        NotificationType.levelUp => QuestColors.osPrimary,
        NotificationType.newFollower => QuestColors.osPrimary,
        NotificationType.collabJoined => QuestColors.osPrimary,
        NotificationType.mention => QuestColors.osCool,
        NotificationType.questExpired => QuestColors.osSurface,
        // white: new_submission, pending_review_reminder,
        // reaction_received, reaction_milestone, new_comment,
        // comment_reply, follow_quest_completed, announcement.
        _ => QuestColors.osCard,
      };

  /// The mono label — the type, ALL CAPS, spaces for underscores, exactly
  /// as the render prints it ("SUBMISSION REJECTED", "SUBMISSION APPROVED",
  /// "MENTION"). Every type yields four words or fewer, so the caps rule
  /// holds without a per-type table.
  ///
  /// Used as the headline only when the notification carries no title of
  /// its own, which is the case for rows written before titles existed.
  static String _label(String type) =>
      type.replaceAll('_', ' ').trim().toUpperCase();

  /// The headline the server wrote, or the type label when there is none.
  ///
  /// This line was missing entirely: the card drew [_label] and the body,
  /// and dropped `title`. For every social type the actor's name lives in
  /// the title and the body is generic — `followed` is
  /// `["<actor> followed you. 👋", "Your party just got one person
  /// bigger."]` — so a notification never said *who* had followed,
  /// commented, replied, reacted or mentioned you. The actor's username and
  /// avatar were fetched and used only to route the tap.
  String get _headline => title.trim().isNotEmpty ? title.trim() : _label(type);

  @override
  Widget build(BuildContext context) {
    final ink = QuestColors.text(context);
    final ground = _ground(type);

    // `quest_expired` is the one type the render draws with a dashed
    // outline on the warm surface — the same language the disabled button
    // uses, so it reads as "over" rather than merely quiet.
    final expired = type == NotificationType.questExpired;
    final flat =
        ground == QuestColors.osCard || ground == QuestColors.osSurface;

    // On a tinted ground the shadow is ink. On white it is muted, so the
    // coral/jade/gold cards keep the visual lead they are meant to have.
    final shadowColor = flat ? QuestColors.osTextMuted : ink;
    final borderColor = expired || isRead ? QuestColors.osTextMuted : ink;
    final borderWidth = isRead ? 1.0 : QuestSpacing.cardBorderWidth;

    final labelColor = QuestColors.onAccentSoft(ground);
    // The body is never alpha-dimmed: `onAccent` is what keeps ink on
    // coral/jade/sky and white on violet, and dimming it drops below AA.
    final bodyColor = expired
        ? QuestColors.onAccentSoft(ground)
        : QuestColors.onAccent(ground);

    final lines = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          _headline,
          // Two lines: a display name plus the copy around it runs past one
          // at 320dp, and truncating to "sami dropped a…" loses the point.
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          // The display face at 14 against the body face at 14: same size,
          // different voice, so the headline leads without a size jump.
          // `osHeadlineSmall` is already w800 — no weight override needed.
          style: QuestTypography.osHeadlineSmall.copyWith(color: bodyColor),
        ),
        const SizedBox(height: 4),
        Text(
          body,
          // Bounded so a long quest title inside the message cannot push
          // the timestamp off the card. Checked at 320dp.
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: QuestTypography.osBodyMedium.copyWith(
            color: bodyColor,
            fontWeight: FontWeight.w600,
            fontVariations: const [FontVariation('wght', 600)],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          timeAgo.toUpperCase(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: QuestTypography.osLabelSmall.copyWith(
            color: labelColor,
            letterSpacing: 0.4,
          ),
        ),
      ],
    );

    // The actor's face, when the notification is about a person. Bordered in
    // the same on-accent ink as the type, so it holds on every ground.
    final actor = actorUsername;
    final content = actor == null
        ? lines
        : Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PixelAvatar(
                imageUrl: actorAvatarUrl,
                username: actor,
                size: 40,
                borderColor: labelColor,
              ),
              const SizedBox(width: 11),
              Expanded(child: lines),
            ],
          );

    final decorated = expired
        ? _DashedCard(
            radius: _radius,
            color: borderColor,
            strokeWidth: borderWidth,
            fill: ground,
            child: Padding(padding: _padding, child: content),
          )
        : Container(
            padding: _padding,
            decoration: BoxDecoration(
              color: ground,
              borderRadius: BorderRadius.circular(_radius),
              border: Border.all(color: borderColor, width: borderWidth),
              // Unread keeps the hard shadow; read drops it and thins the
              // border to 1px. This is the one place a 1px border is right.
              boxShadow: isRead
                  ? null
                  : QuestSpacing.hardShadow(_shadowDepth, color: shadowColor),
            ),
            child: content,
          );

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minHeight: QuestSpacing.minTouchTarget,
        ),
        child: decorated,
      ),
    );
  }
}

// ── Dashed rounded rectangle ────────────────────────────────────────────────

/// A filled, dashed-outline rounded rectangle.
///
/// Flutter has no dashed [Border], and the design uses one twice on this
/// screen: on the `quest_expired` card and on the empty state.
class _DashedCard extends StatelessWidget {
  const _DashedCard({
    required this.child,
    required this.radius,
    required this.color,
    required this.strokeWidth,
    this.fill,
  });

  final Widget child;
  final double radius;
  final Color color;
  final double strokeWidth;
  final Color? fill;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: CustomPaint(
        painter: _DashedRRectPainter(
          radius: radius,
          color: color,
          strokeWidth: strokeWidth,
        ),
        child: child,
      ),
    );
  }
}

class _DashedRRectPainter extends CustomPainter {
  const _DashedRRectPainter({
    required this.radius,
    required this.color,
    required this.strokeWidth,
  });

  final double radius;
  final Color color;
  final double strokeWidth;

  // Dash geometry is fixed rather than configurable: a dashed outline means
  // one thing in this design, so it should look identical everywhere.
  static const double _dash = 6;
  static const double _gap = 5;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    // Inset by half the stroke so the dashes sit inside the bounds rather
    // than straddling them.
    final inset = strokeWidth / 2;
    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        inset,
        inset,
        size.width - strokeWidth,
        size.height - strokeWidth,
      ),
      Radius.circular(radius - inset),
    );

    final path = Path()..addRRect(rrect);
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = (distance + _dash).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance = end + _gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedRRectPainter oldDelegate) =>
      oldDelegate.radius != radius ||
      oldDelegate.color != color ||
      oldDelegate.strokeWidth != strokeWidth;
}

// ── Empty + error ───────────────────────────────────────────────────────────

/// `EMPTY STATE` in mono muted over `NO NEW SIGNALS` in Syne, inside a
/// dashed r14 box with no fill — exactly as the render draws it.
class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: _DashedCard(
        radius: 14,
        color: QuestColors.osTextMuted,
        strokeWidth: QuestSpacing.cardBorderWidth,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 26),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                'EMPTY STATE',
                textAlign: TextAlign.center,
                style: QuestTypography.osLabelSmall.copyWith(
                  color: QuestColors.osTextMuted,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                title.toUpperCase(),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: QuestTypography.osHeadlineMedium.copyWith(
                  color: QuestColors.osTextSecondary,
                  fontSize: 17,
                  height: 1.15,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({
    required this.message,
    required this.retryLabel,
    required this.onRetry,
  });
  final String message;
  final String retryLabel;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final ink = QuestColors.text(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(QuestSpacing.screenPadding),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: QuestColors.osRed,
                shape: BoxShape.circle,
                border: Border.all(color: ink, width: 2),
                boxShadow: QuestSpacing.shadowSm,
              ),
              child: Icon(Icons.error_outline,
                  color: QuestColors.onAccent(QuestColors.osRed), size: 36),
            ),
            const SizedBox(height: 20),
            Text(
              message,
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: QuestTypography.osHeadlineMedium.copyWith(color: ink),
            ),
            const SizedBox(height: 14),
            ArcadeButton(
              label: retryLabel,
              onTap: onRetry,
              variant: ArcadeButtonVariant.secondary,
              size: ArcadeButtonSize.small,
              expand: false,
            ),
          ],
        ),
      ),
    );
  }
}
