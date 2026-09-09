import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:app_core/app_core.dart';
import 'package:app_repositories/app_repositories.dart'
    show RealtimeDomainEvent;
import '../../core/backend/app_backend.dart';
import '../../core/router/route_names.dart';
import '../../core/providers/auth_session_provider.dart';
import '../../core/providers/connectivity_provider.dart';
import '../../features/feed/presentation/providers/feed_provider.dart';
import '../../core/providers/current_profile_provider.dart';
import '../../core/services/live_activity_service.dart';
import '../../features/leaderboard/presentation/providers/leaderboard_provider.dart';
import '../../features/notifications/presentation/providers/notifications_provider.dart';
import '../../features/follows/data/follows_providers.dart';
import '../../features/quests/data/quest_providers.dart';
import '../../features/settings/data/push_preference.dart';
import '../../features/submissions/data/submission_providers.dart';
import '../widgets/loading_view.dart';
import '../widgets/level_up_overlay.dart';

/// Direction A — "Arcade Pop" floating bottom nav.
/// Drop-in replacement for apps/mobile_app/lib/shared/navigation/bottom_nav_shell.dart
///
/// Same behaviour: 5 tabs (HOME / FEED / COLLAB / RANK / PROFILE), same
/// routing, same level-up overlay, same offline banner. Only the visual
/// layer is rewritten — a dark violet-ink pill floats 24px off the bottom
/// edge with a gold-filled active tab.

final _previousLevelProvider = StateProvider<int?>((ref) => null);

class BottomNavShell extends ConsumerStatefulWidget {
  final Widget child;

  const BottomNavShell({super.key, required this.child});

  @override
  ConsumerState<BottomNavShell> createState() => _BottomNavShellState();
}

class _BottomNavShellState extends ConsumerState<BottomNavShell> {
  OverlayEntry? _levelUpEntry;

  // Global XP-freshness realtime: home_page used to own the only
  // submission subscription, but it dies the moment the user leaves the
  // home tab. If a submission is approved while the user is on leaderboard
  // or profile, neither `profiles.xp` nor the cached leaderboard get
  // invalidated — so the three screens drift apart. Subscribing here means
  // XP-touching events refresh every surface as long as the user is
  // anywhere inside the bottom-nav shell.
  StreamSubscription<RealtimeDomainEvent>? _realtimeSubscription;
  String? _subscribedUserId;

  // Dynamic Island / Lock Screen Live Activity bookkeeping. Tracks the
  // quest id currently mirrored to the system so we can `end` it the
  // moment the active quest goes null (submitted / canceled / expired)
  // and `start` a new one cleanly when the user rolls again.
  String? _liveActivityQuestId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureXpRealtime());
  }

  @override
  void dispose() {
    _levelUpEntry?.remove();
    final subscription = _realtimeSubscription;
    if (subscription != null) unawaited(subscription.cancel());
    super.dispose();
  }

  void _ensureXpRealtime() {
    if (!mounted) return;
    final user = ref.read(authSessionProvider);
    if (user == null) {
      // Logged out — drop any stale subscription.
      final subscription = _realtimeSubscription;
      if (subscription != null) unawaited(subscription.cancel());
      _realtimeSubscription = null;
      _subscribedUserId = null;
      return;
    }
    if (_subscribedUserId == user.id) return;
    final previousSubscription = _realtimeSubscription;
    if (previousSubscription != null) {
      unawaited(previousSubscription.cancel());
    }
    _realtimeSubscription = null;
    _subscribedUserId = user.id;

    void invalidateXpSurfaces() {
      // `profiles.xp` is the single source of truth; home tile, profile
      // stat pill, and leaderboard rows all derive from it. Home's quest
      // sections (active / pending / history / submissions) are touched
      // by the same DB events, so we invalidate them here too — that
      // lets us drop the duplicate channels HomePage used to own.
      ref.invalidate(currentProfileProvider);
      ref.invalidate(leaderboardProvider);
      ref.invalidate(followingLeaderboardProvider);
      ref.invalidate(activeQuestProvider);
      ref.invalidate(questHistoryProvider);
      ref.invalidate(userSubmissionsProvider);
    }

    final realtime = AppBackend.repositories.realtime;
    _realtimeSubscription = realtime.events.listen((event) {
      final eventUserId = event.data['userId'];
      final targetUserId = event.data['targetUserId'];
      final profileId = event.data['profileId'];
      if ((event.type.startsWith('submission.') ||
              event.type.startsWith('quest.')) &&
          eventUserId == user.id) {
        invalidateXpSurfaces();
      } else if (event.type == 'profile.updated' && profileId == user.id) {
        ref.invalidate(currentProfileProvider);
        ref.invalidate(leaderboardProvider);
        ref.invalidate(followingLeaderboardProvider);
      } else if (event.type.startsWith('notification.') &&
          eventUserId == user.id) {
        ref.invalidate(notificationsProvider);
        ref.invalidate(unreadCountProvider);
      } else if (event.type == 'social.follow.changed' &&
          (eventUserId == user.id || targetUserId == user.id)) {
        ref.invalidate(followCountsProvider(user.id));
        ref.invalidate(isFollowingProvider);
        ref.invalidate(feedProvider);
      }
    });
    unawaited(() async {
      try {
        await realtime.connect();
      } catch (error) {
        AppLogger.warning('[ShellRealtime] Nest connection failed: $error');
      }
    }());

    // Re-apply the push-notifications preference. `bootstrap.dart` registers
    // the FCM token on every cold start regardless of the setting, so
    // without this a user who switched push OFF would silently start
    // receiving it again after the next launch.
    unawaited(ref.read(pushPreferenceProvider.notifier).reconcile());

    // Pre-warm tab content so switching tabs feels instant. These reads
    // start in parallel the moment the user lands inside the shell, while
    // the home tab itself is rendering. By the time the user taps FEED /
    // RANK / notifications they're already loaded from cache.
    ref.read(feedProvider);
    ref.read(leaderboardProvider);
    ref.read(notificationsProvider);
    ref.read(unreadCountProvider);

    // Cold-start sync: if the user is opening the app with a quest
    // already in flight (cached + revalidating in the background), the
    // `ref.listen` below won't fire because Riverpod won't emit a
    // "change". Read the current snapshot ourselves and mirror it.
    final initialQuest = ref.read(activeQuestProvider).valueOrNull;
    if (initialQuest != null && initialQuest.expiresAt != null) {
      ref
          .read(liveActivityServiceProvider)
          .startForQuest(initialQuest)
          .then((id) {
        if (id != null && mounted) {
          _liveActivityQuestId = initialQuest.questId;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Re-subscribe if auth changes (login/logout swaps user.id).
    ref.listen(authSessionProvider, (_, __) {
      _ensureXpRealtime();
      // Logout: tear down any Dynamic Island activity so the next user
      // doesn't inherit a stale countdown.
      if (ref.read(authSessionProvider) == null) {
        ref.read(liveActivityServiceProvider).endAll();
        _liveActivityQuestId = null;
      }
    });

    // Mirror the active quest into the Dynamic Island / Lock Screen Live
    // Activity. Each transition handled explicitly:
    //  - null → quest        → start activity
    //  - questA → questB     → end A, start B (handled by start's de-dupe)
    //  - quest → null        → end activity
    //  - quest → same quest, new expiresAt (re-roll, admin edit) → update
    ref.listen(activeQuestProvider, (previous, next) {
      final newQuest = next.valueOrNull;
      final service = ref.read(liveActivityServiceProvider);

      // Quest cleared.
      if (newQuest == null) {
        final prevId = _liveActivityQuestId;
        if (prevId != null) {
          service.endForQuest(prevId);
          _liveActivityQuestId = null;
        }
        return;
      }

      // Quest is the same as the currently-mirrored one — could be a
      // deadline update (admin tweaked durationHours) or a status flip.
      if (_liveActivityQuestId == newQuest.questId) {
        final expires = newQuest.expiresAt;
        if (expires != null) {
          service.update(
            questId: newQuest.questId,
            expiresAt: expires,
            status: newQuest.status,
          );
        }
        return;
      }

      // New / different quest. End the prior one then spin a fresh
      // activity. The native side de-dupes per quest id, so even if we
      // raced an end+start the OS won't show two competing widgets.
      final prevId = _liveActivityQuestId;
      if (prevId != null) service.endForQuest(prevId);
      service.startForQuest(newQuest).then((activityId) {
        if (activityId != null && mounted) {
          _liveActivityQuestId = newQuest.questId;
        }
      });
    });

    final currentIndex = _currentIndex(context);
    final isOnline = ref.watch(connectivityProvider).valueOrNull ?? true;

    // Listen for level changes to trigger level-up overlay
    ref.listen(currentProfileProvider, (previous, next) {
      final newProfile = next.valueOrNull;
      if (newProfile == null) return;
      final prevLevel = ref.read(_previousLevelProvider);
      if (prevLevel != null && newProfile.level > prevLevel) {
        _showLevelUpOverlay(newProfile.level);
      }
      ref.read(_previousLevelProvider.notifier).state = newProfile.level;
    });

    return Scaffold(
      backgroundColor: QuestColors.bg(context),
      // The frame docks the nav to the bottom edge as an opaque cream bar,
      // so content stops above it rather than scrolling under it.
      body: Column(
        children: [
          if (!isOnline) const OfflineBanner(),
          Expanded(child: widget.child),
          _ArcadeBottomNav(
            currentIndex: currentIndex,
            onTap: (index) => _onTap(context, index),
          ),
        ],
      ),
    );
  }

  void _showLevelUpOverlay(int newLevel) {
    _levelUpEntry?.remove();
    _levelUpEntry = OverlayEntry(
      builder: (_) => LevelUpOverlay(
        newLevel: newLevel,
        onDismiss: () {
          _levelUpEntry?.remove();
          _levelUpEntry = null;
        },
      ),
    );
    Overlay.of(context).insert(_levelUpEntry!);
  }

  /// -1 means "no tab owns this route". Collab lives inside the shell but is
  /// not one of the five tabs the frame draws, so nothing lights up there.
  int _currentIndex(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    if (location.startsWith(RoutePaths.feed)) return 1;
    if (location.startsWith(RoutePaths.map)) return 2;
    if (location.startsWith(RoutePaths.leaderboard)) return 3;
    if (location.startsWith(RoutePaths.profile)) return 4;
    if (location.startsWith(RoutePaths.collab)) return -1;
    return 0;
  }

  void _onTap(BuildContext context, int index) {
    switch (index) {
      case 0:
        context.goNamed(RouteNames.home);
      case 1:
        // Tapping FEED — whether arriving here or already here — should
        // reset the user to the top of the feed and refresh. Mark the
        // saved index back to 0, bump the scroll-reset tick (the live
        // FeedPage listens and animates to page 0), and invalidate the
        // feed provider so a fresh fetch runs.
        ref.read(feedLastIndexProvider.notifier).state = 0;
        ref.read(feedScrollResetTickProvider.notifier).state++;
        ref.invalidate(feedProvider);
        context.goNamed(RouteNames.feed);
      case 2:
        context.goNamed(RouteNames.map);
      case 3:
        context.goNamed(RouteNames.leaderboard);
      case 4:
        context.goNamed(RouteNames.profile);
    }
  }
}

// ── Bottom nav ─────────────────────────────────────────────────────────────
//
// Read off `export/mobile/12-profile.jpg` and
// `export/components/component-05-bottom-nav.jpg`: a flush cream bar with a
// 2px ink top rule, five tabs, geometric glyphs, and NO fill or pill behind
// the active tab — "active tab is ink, inactive is soft ink". The previous
// implementation was a floating ink pill with a gold active chip, which is
// the one thing the component sheet writes out as wrong.
//
// The sheet also says COLLAB is reached from the feed rather than the nav
// ("five tabs is already the ceiling"), so SEARCH takes the third slot.

class _ArcadeBottomNav extends StatelessWidget {
  const _ArcadeBottomNav({
    required this.currentIndex,
    required this.onTap,
  });

  /// -1 when the current route is not one of the five tabs (collab).
  final int currentIndex;
  final ValueChanged<int> onTap;

  static const _items = <_NavItem>[
    _NavItem(glyph: _NavGlyphShape.square, label: 'HOME'),
    _NavItem(glyph: _NavGlyphShape.lines, label: 'FEED'),
    _NavItem(glyph: _NavGlyphShape.target, label: 'MAP'),
    _NavItem(glyph: _NavGlyphShape.triangle, label: 'RANKS'),
    _NavItem(glyph: _NavGlyphShape.circle, label: 'PROFILE'),
  ];

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;
    final ink = QuestColors.text(context);

    return Container(
      decoration: BoxDecoration(
        color: QuestColors.osSurface,
        border: Border(top: BorderSide(color: ink, width: 2)),
      ),
      padding: EdgeInsets.only(bottom: bottomPad > 0 ? bottomPad * 0.35 : 0),
      child: Row(
        children: List.generate(_items.length, (index) {
          final active = index == currentIndex;
          final item = _items[index];
          final fg = active ? ink : QuestColors.osTextMuted;
          return Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                HapticFeedback.lightImpact();
                onTap(index);
              },
              child: ConstrainedBox(
                // 44pt floor on the hit box, not the paint: the glyph plus a
                // 10px label only measures ~32 on its own.
                constraints: const BoxConstraints(
                    minHeight: QuestSpacing.minTouchTarget),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(4, 10, 4, 10),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _NavGlyph(shape: item.glyph, color: fg),
                      const SizedBox(height: 6),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          item.label,
                          maxLines: 1,
                          style: QuestTypography.osLabelSmall.copyWith(
                            color: fg,
                            fontSize: 10,
                            letterSpacing: 0.8,
                            height: 1,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

enum _NavGlyphShape { square, lines, target, triangle, circle }

class _NavItem {
  const _NavItem({required this.glyph, required this.label});
  final _NavGlyphShape glyph;
  final String label;
}

/// The five nav glyphs are drawn, not iconised: the frame uses plain
/// geometry (filled square, ruled square, target, triangle, disc) and no
/// Material icon is that shape.
class _NavGlyph extends StatelessWidget {
  const _NavGlyph({required this.shape, required this.color});

  final _NavGlyphShape shape;
  final Color color;

  static const double _size = 13;

  @override
  Widget build(BuildContext context) {
    switch (shape) {
      case _NavGlyphShape.square:
        return Container(
          width: _size,
          height: _size,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        );
      case _NavGlyphShape.circle:
        return Container(
          width: _size,
          height: _size,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        );
      case _NavGlyphShape.lines:
      case _NavGlyphShape.target:
      case _NavGlyphShape.triangle:
        return SizedBox(
          width: _size,
          height: _size,
          child: CustomPaint(
            painter: _NavGlyphPainter(shape: shape, color: color),
          ),
        );
    }
  }
}

class _NavGlyphPainter extends CustomPainter {
  const _NavGlyphPainter({required this.shape, required this.color});

  final _NavGlyphShape shape;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    switch (shape) {
      case _NavGlyphShape.lines:
        // Ruled square: four bars, 1.6 tall, evenly spaced.
        const bar = 1.6;
        final gap = (size.height - bar * 4) / 3;
        for (var i = 0; i < 4; i++) {
          canvas.drawRect(
            Rect.fromLTWH(0, i * (bar + gap), size.width, bar),
            paint,
          );
        }
      case _NavGlyphShape.target:
        final centre = size.center(Offset.zero);
        canvas.drawCircle(
          centre,
          size.width / 2 - 0.75,
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,
        );
        canvas.drawCircle(centre, size.width / 6, paint);
      case _NavGlyphShape.triangle:
        final path = Path()
          ..moveTo(size.width / 2, 0)
          ..lineTo(size.width, size.height)
          ..lineTo(0, size.height)
          ..close();
        canvas.drawPath(path, paint);
      case _NavGlyphShape.square:
      case _NavGlyphShape.circle:
        break;
    }
  }

  @override
  bool shouldRepaint(_NavGlyphPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.shape != shape;
}
