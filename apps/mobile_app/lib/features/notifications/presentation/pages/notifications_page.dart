import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:app_core/app_core.dart';
import 'package:app_models/app_models.dart';
import 'package:supabase_contracts/supabase_contracts.dart';
import 'package:shared_ui/shared_ui.dart';
import '../../../../core/providers/auth_session_provider.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/router/safe_back.dart';
import '../../../../core/services/analytics_service.dart';
import '../../../../core/services/app_badge_service.dart';
import '../../../../core/utils/account_lock_guard.dart';
import '../providers/notifications_provider.dart';
import '../../../../l10n/app_localizations.dart';

/// Arcade Pop notifications page. Logic (auto mark-as-read, badge clearing,
/// filtering, navigation per notification type) is unchanged.
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
              n.type == NotificationType.leaderboardOvertaken ||
              n.type == NotificationType.top10Entry;
        case 2:
          return n.type == NotificationType.questAssigned ||
              n.type == NotificationType.questExpired ||
              n.type == NotificationType.questTimerWarning;
        case 3:
          return n.type == NotificationType.submissionApproved ||
              n.type == NotificationType.submissionRejected ||
              n.type == NotificationType.levelUp ||
              n.type == NotificationType.announcement ||
              n.type == NotificationType.newSubmission ||
              n.type == NotificationType.appealSubmitted ||
              n.type == NotificationType.pendingReviewReminder;
        default:
          return true;
      }
    }).toList();
  }

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
          Padding(
            padding: EdgeInsets.only(
              top: MediaQuery.of(context).padding.top + 14,
              bottom: 4,
              left: QuestSpacing.screenPadding,
              right: QuestSpacing.screenPadding,
            ),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () => safeBack(context),
                  child: Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: QuestColors.cardBg(context),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: ink, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: ink,
                          offset: const Offset(2, 3),
                          blurRadius: 0,
                        ),
                      ],
                    ),
                    child: Icon(Icons.arrow_back_rounded, color: ink, size: 20),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'SIGNALS',
                  style: QuestTypography.headlineLarge.copyWith(
                    color: ink,
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                    height: 1,
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  width: 40,
                  height: 6,
                  decoration: BoxDecoration(
                    color: QuestColors.softRed,
                    borderRadius: BorderRadius.circular(2),
                    border: Border.all(color: ink, width: 1.5),
                  ),
                ),
                const Spacer(),
              ],
            ),
          ),

          // ── Filter chips ────────────────────────────────────────────
          SizedBox(
            height: 36,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(
                  horizontal: QuestSpacing.screenPadding, vertical: 4),
              itemCount: filters.length,
              itemBuilder: (context, i) {
                final active = i == _filterIndex;
                return GestureDetector(
                  onTap: () => setState(() => _filterIndex = i),
                  child: Padding(
                    padding:
                        EdgeInsets.only(right: i < filters.length - 1 ? 8 : 0),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: active
                            ? QuestColors.accentYellow
                            : QuestColors.cardBg(context),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: ink, width: 1.8),
                        boxShadow: active
                            ? [
                                BoxShadow(
                                  color: ink,
                                  offset: const Offset(1.5, 2),
                                  blurRadius: 0,
                                ),
                              ]
                            : null,
                      ),
                      child: Center(
                        child: Text(
                          filters[i].toUpperCase(),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.8,
                            color: ink,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 4),

          // ── Content ────────────────────────────────────────────────
          Expanded(
            child: notificationsAsync.when(
              loading: () => const Center(
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              error: (e, _) => _ErrorState(
                message: l.failedToLoad,
                retryLabel: l.retry,
                onRetry: () => ref.invalidate(notificationsProvider),
              ),
              data: (allNotifications) {
                final notifications = _filtered(allNotifications);
                if (notifications.isEmpty) {
                  return _EmptyState(title: l.noNewSignals);
                }

                return RefreshIndicator(
                  color: QuestColors.softRed,
                  backgroundColor: QuestColors.cardBg(context),
                  onRefresh: () async => ref.invalidate(notificationsProvider),
                  child: ListView.separated(
                    // Keyed by the active filter so scroll position is
                    // preserved when the user toggles ALL ↔ SOCIAL etc.,
                    // instead of snapping back to the top on every tap.
                    key: PageStorageKey<int>(_filterIndex),
                    padding: const EdgeInsets.fromLTRB(
                      QuestSpacing.screenPadding,
                      8,
                      QuestSpacing.screenPadding,
                      24,
                    ),
                    itemCount: notifications.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final n = notifications[index];
                      return _ArcadeNotificationTile(
                        title: n.title,
                        body: n.body,
                        type: n.type,
                        isRead: n.isRead,
                        timeAgo: _timeAgo(n.createdAt),
                        actorAvatarUrl: n.actorAvatarUrl,
                        actorUsername: n.actorUsername,
                        onActorTap: n.actorId == null
                            ? null
                            : () => context.pushNamed(
                                  RouteNames.userProfile,
                                  pathParameters: {'userId': n.actorId!},
                                ),
                        onTap: () async {
                          // Wrap the read-mark in try/catch so a transient
                          // RLS/network blip doesn't (a) silently swallow
                          // the failure and leave the unread dot stale OR
                          // (b) block the navigation. Navigate either
                          // way; only invalidate the providers if the
                          // mark actually succeeded.
                          if (!n.isRead) {
                            try {
                              await ref
                                  .read(notificationsRepositoryProvider)
                                  .markAsRead(n.id);
                              if (context.mounted) {
                                ref.invalidate(notificationsProvider);
                                ref.invalidate(unreadCountProvider);
                              }
                            } catch (e) {
                              AppLogger.warning(
                                  '[Notifications] markAsRead failed for ${n.id}: $e');
                            }
                          }
                          if (context.mounted) {
                            ref
                                .read(analyticsProvider)
                                .notificationTapped(n.type);
                            _navigateForNotification(context, n);
                          }
                        },
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
        context.goNamed(RouteNames.home);
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

  String _timeAgo(DateTime dt) => timeAgo(dt);
}

// ── Tile ────────────────────────────────────────────────────────────────────

class _ArcadeNotificationTile extends StatelessWidget {
  const _ArcadeNotificationTile({
    required this.title,
    required this.body,
    required this.type,
    required this.isRead,
    required this.timeAgo,
    required this.onTap,
    this.actorAvatarUrl,
    this.actorUsername,
    this.onActorTap,
  });

  final String title;
  final String body;
  final String type;
  final bool isRead;
  final String timeAgo;
  final VoidCallback onTap;
  final String? actorAvatarUrl;
  final String? actorUsername;
  final VoidCallback? onActorTap;

  @override
  Widget build(BuildContext context) {
    final ink = QuestColors.text(context);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          // Read/unread is distinguished by border + shadow below, not fill.
          color: QuestColors.cardBg(context),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isRead ? ink.withAlpha(120) : ink,
            width: isRead ? 1.5 : 2,
          ),
          boxShadow: isRead
              ? null
              : [
                  BoxShadow(
                    color: ink,
                    offset: const Offset(2, 3),
                    blurRadius: 0,
                  ),
                ],
        ),
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Icon tile or actor avatar
            _buildLeadingWidget(ink),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: QuestTypography.labelMedium.copyWith(
                            color: ink,
                            fontWeight: FontWeight.w800,
                            fontSize: 13.5,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (!isRead)
                        Container(
                          width: 9,
                          height: 9,
                          margin: const EdgeInsets.only(left: 6, top: 2),
                          decoration: BoxDecoration(
                            color: QuestColors.softRed,
                            shape: BoxShape.circle,
                            border: Border.all(color: ink, width: 1.5),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    body,
                    style: QuestTypography.bodySmall.copyWith(
                      color: ink.withAlpha(180),
                      fontSize: 12.5,
                      height: 1.35,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (_isSocialType(type) && actorUsername != null)
                        GestureDetector(
                          onTap: onActorTap,
                          child: _MetaPill(
                            label: '@$actorUsername',
                            ink: ink,
                            backgroundColor: QuestColors.accentYellow,
                          ),
                        ),
                      _MetaPill(
                        label: timeAgo,
                        ink: ink,
                        backgroundColor: QuestColors.bg(context),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _isSocialType(String type) {
    return type == NotificationType.reactionReceived ||
        type == NotificationType.reactionMilestone ||
        type == NotificationType.newFollower ||
        type == NotificationType.newComment ||
        type == NotificationType.commentReply ||
        type == NotificationType.followQuestCompleted;
  }

  Widget _buildLeadingWidget(Color ink) {
    if (_isSocialType(type) &&
        (actorAvatarUrl != null || actorUsername != null)) {
      return GestureDetector(
        onTap: onActorTap,
        child: PixelAvatar(
          imageUrl: actorAvatarUrl,
          username: actorUsername ?? '?',
          size: 40,
          borderColor: ink,
        ),
      );
    }
    final (icon, tint) = _iconAndTint(type);
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: tint,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: ink, width: 2),
      ),
      child: Icon(icon, color: QuestColors.osTextOnPrimary, size: 20),
    );
  }

  (IconData, Color) _iconAndTint(String type) {
    switch (type) {
      case NotificationType.submissionApproved:
        return (Icons.check_circle_rounded, QuestColors.successGreen);
      case NotificationType.submissionRejected:
        return (Icons.cancel_rounded, QuestColors.softRed);
      case NotificationType.levelUp:
        return (Icons.trending_up_rounded, QuestColors.osPrimary);
      case NotificationType.questAssigned:
        return (Icons.flag_rounded, QuestColors.accentYellow);
      case NotificationType.questExpired:
        return (Icons.hourglass_empty_rounded, QuestColors.textMuted);
      case NotificationType.questTimerWarning:
        return (Icons.alarm_rounded, QuestColors.softRed);
      case NotificationType.reactionReceived:
      case NotificationType.reactionMilestone:
        return (Icons.favorite_rounded, QuestColors.softRed);
      case NotificationType.newFollower:
        return (Icons.person_add_rounded, QuestColors.osPrimary);
      case NotificationType.newComment:
      case NotificationType.commentReply:
        return (Icons.chat_bubble_rounded, QuestColors.osPrimary);
      case NotificationType.followQuestCompleted:
        return (Icons.emoji_events_rounded, QuestColors.accentYellow);
      case NotificationType.leaderboardOvertaken:
        return (Icons.bolt_rounded, QuestColors.softRed);
      case NotificationType.top10Entry:
        return (Icons.military_tech_rounded, QuestColors.accentYellow);
      case NotificationType.announcement:
        return (Icons.campaign_rounded, QuestColors.osPrimary);
      case NotificationType.newSubmission:
      case NotificationType.appealSubmitted:
      case NotificationType.pendingReviewReminder:
        return (Icons.assignment_rounded, QuestColors.osPrimary);
      default:
        return (Icons.notifications_rounded, QuestColors.osPrimary);
    }
  }
}

class _MetaPill extends StatelessWidget {
  const _MetaPill({
    required this.label,
    required this.ink,
    required this.backgroundColor,
  });

  final String label;
  final Color ink;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: ink, width: 1.2),
      ),
      // Cap the chip width so a 30-char @handle truncates with an ellipsis
      // instead of stretching past the row on small phones.
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 180),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: QuestTypography.labelSmall.copyWith(
            color: ink,
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.3,
          ),
        ),
      ),
    );
  }
}

// ── Empty + error ───────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    final ink = QuestColors.text(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: ink, width: 2.5),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [QuestColors.osPrimary, QuestColors.softRed],
              ),
              boxShadow: [
                BoxShadow(
                  color: ink,
                  offset: const Offset(2, 3),
                  blurRadius: 0,
                ),
              ],
            ),
            child: const Icon(Icons.notifications_off_rounded,
                color: QuestColors.osTextOnPrimary, size: 38),
          ),
          const SizedBox(height: 20),
          Text(
            title.toUpperCase(),
            style: QuestTypography.headlineSmall.copyWith(
              color: ink,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Your signal feed is clear.',
            style: QuestTypography.bodyMedium.copyWith(
              color: ink.withAlpha(170),
            ),
          ),
        ],
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: QuestColors.softRed,
              shape: BoxShape.circle,
              border: Border.all(color: ink, width: 2.5),
              boxShadow: [
                BoxShadow(
                  color: ink,
                  offset: const Offset(2, 3),
                  blurRadius: 0,
                ),
              ],
            ),
            child: const Icon(Icons.error_outline,
                color: QuestColors.osTextOnPrimary, size: 36),
          ),
          const SizedBox(height: 20),
          Text(
            message,
            style: QuestTypography.headlineSmall.copyWith(
              color: ink,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 14),
          GestureDetector(
            onTap: onRetry,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
              decoration: BoxDecoration(
                color: QuestColors.accentYellow,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: ink, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: ink,
                    offset: const Offset(2, 3),
                    blurRadius: 0,
                  ),
                ],
              ),
              child: Text(
                retryLabel.toUpperCase(),
                style: QuestTypography.labelMedium.copyWith(
                  color: ink,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                  letterSpacing: 1.2,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
