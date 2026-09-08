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
      extendBody: true, // floating nav sits over the content
      body: Stack(
        children: [
          Column(
            children: [
              if (!isOnline) const OfflineBanner(),
              Expanded(child: widget.child),
            ],
          ),
          // Floating nav
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _FloatingPillNav(
              currentIndex: currentIndex,
              onTap: (index) => _onTap(context, index),
            ),
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

  int _currentIndex(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    if (location.startsWith(RoutePaths.feed)) return 1;
    if (location.startsWith(RoutePaths.collab)) return 2;
    if (location.startsWith(RoutePaths.leaderboard)) return 3;
    if (location.startsWith(RoutePaths.profile)) return 4;
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
        context.goNamed(RouteNames.collab);
      case 3:
        context.goNamed(RouteNames.leaderboard);
      case 4:
        context.goNamed(RouteNames.profile);
    }
  }
}

// ── Floating pill nav ──────────────────────────────────────────────────────

class _FloatingPillNav extends StatelessWidget {
  const _FloatingPillNav({
    required this.currentIndex,
    required this.onTap,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;

  static const _items = <_NavItem>[
    _NavItem(icon: Icons.home_outlined, activeIcon: Icons.home, label: 'HOME'),
    _NavItem(
        icon: Icons.dynamic_feed_outlined,
        activeIcon: Icons.dynamic_feed,
        label: 'FEED'),
    _NavItem(
        icon: Icons.group_add_outlined,
        activeIcon: Icons.group_add,
        label: 'COLLAB'),
    _NavItem(
        icon: Icons.emoji_events_outlined,
        activeIcon: Icons.emoji_events,
        label: 'RANK'),
    _NavItem(
        icon: Icons.person_outline, activeIcon: Icons.person, label: 'YOU'),
  ];

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Pill always uses dark ink bg — this is the Arcade Pop signature.
    final pillBg =
        isDark ? QuestColors.darkCard : QuestColors.osTextPrimary; // ink
    final inactive = QuestColors.textPrimary.withAlpha(160);

    // Hug the bottom edge: instead of letting SafeArea push the pill above
    // the full system inset (34pt on iPhones with a home indicator) and
    // adding extra cream on top, take only a fraction of the inset so the
    // home indicator sits just below — or visually atop — the pill. Big
    // visual win: ~30pt of dead cream space removed across every screen.
    return Padding(
      padding: EdgeInsets.only(
        left: 12,
        right: 12,
        bottom: bottomPad > 0 ? (bottomPad * 0.30).clamp(8.0, 14.0) : 10,
        top: 4,
      ),
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: pillBg,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: pillBg, width: 2),
          boxShadow: [
            BoxShadow(
              color: QuestColors.pureBlack.withAlpha(40),
              offset: const Offset(0, 6),
              blurRadius: 0,
            ),
            BoxShadow(
              color: QuestColors.osPrimary.withAlpha(20),
              offset: const Offset(0, 12),
              blurRadius: 24,
            ),
          ],
        ),
        child: Row(
          children: List.generate(_items.length, (index) {
            final active = index == currentIndex;
            final item = _items[index];
            return Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  HapticFeedback.lightImpact();
                  onTap(index);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  padding: const EdgeInsets.symmetric(
                    vertical: 10,
                    horizontal: 4,
                  ),
                  decoration: BoxDecoration(
                    color:
                        active ? QuestColors.accentYellow : Colors.transparent,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        active ? item.activeIcon : item.icon,
                        size: 20,
                        color: active ? QuestColors.accentYellowInk : inactive,
                      ),
                      const SizedBox(height: 2),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          item.label,
                          maxLines: 1,
                          overflow: TextOverflow.visible,
                          style: QuestTypography.headlineSmall.copyWith(
                            fontSize: 8,
                            letterSpacing: 0.4,
                            color:
                                active ? QuestColors.accentYellowInk : inactive,
                            height: 1,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}

class _NavItem {
  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
  });
  final IconData icon;
  final IconData activeIcon;
  final String label;
}
