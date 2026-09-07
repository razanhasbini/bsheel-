import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../backend/backend_config.dart';
import '../backend/mobile_nest_backend.dart';
import 'package:app_core/app_core.dart' show AppLogger;

import '../providers/auth_session_provider.dart';
import '../providers/current_profile_provider.dart';
import '../providers/app_config_provider.dart';
import '../../features/quests/data/quest_providers.dart';
import '../../features/submissions/data/submission_providers.dart';
import '../../features/feed/presentation/providers/feed_provider.dart';
import '../../features/notifications/presentation/providers/notifications_provider.dart';
import '../../features/leaderboard/presentation/providers/leaderboard_provider.dart';

/// Reconnects the selected realtime transport and refreshes hot providers when the app
/// returns to the foreground.
///
/// Why: iOS suspends background processes; the Realtime WebSocket dies
/// silently. Without this, on resume the channels appear "subscribed" but no
/// events flow, and every FutureProvider keeps serving stale cache forever
/// until the app is force-killed. This is the single biggest cause of the
/// "left and came back, app is stuck" symptom.
///
/// Lives at the root of [QuestApp] so it catches resume regardless of which
/// route the user was on.
class AppResumeObserver with WidgetsBindingObserver {
  AppResumeObserver(this._ref);

  final WidgetRef _ref;
  DateTime? _pausedAt;

  void attach() => WidgetsBinding.instance.addObserver(this);
  void detach() => WidgetsBinding.instance.removeObserver(this);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        _pausedAt ??= DateTime.now();
      case AppLifecycleState.resumed:
        _handleResume();
      case AppLifecycleState.detached:
        break;
    }
  }

  void _handleResume() {
    final pausedFor = _pausedAt == null
        ? Duration.zero
        : DateTime.now().difference(_pausedAt!);
    _pausedAt = null;

    // Short trips out (notifications shade, app switcher peek) — don't
    // bother refetching. The realtime socket usually survives < 3s suspends.
    if (pausedFor < const Duration(seconds: 3)) return;

    refreshAfterReconnect(_ref, 'app resumed after ${pausedFor.inSeconds}s');
  }
}

/// Shared "we just regained connection, treat all cached data as suspect"
/// path. Used by both the lifecycle observer (resume from background) and
/// the connectivity provider (wifi/cellular bounce). Pulling them together
/// means each surface has one code path that decides what to refresh.
void refreshAfterReconnect(WidgetRef ref, String reason) {
  final user = ref.read(authSessionProvider);
  if (user == null) return;

  AppLogger.info(
      '[Lifecycle] $reason — reconnecting realtime + refreshing hot data');

  // Kick the Realtime socket. iOS may have killed it during suspend, or the
  // OS may have switched the device off wifi. The SDK's auto-reconnect
  // doesn't always fire when the socket was held in a half-open state.
  // Disconnect alone is enough — the SDK transparently reconnects on the
  // next channel subscribe, which is exactly what the invalidate() calls
  // below trigger via the StreamProviders that watch realtime channels.
  if (BackendConfig.usesNest) {
    final realtime = MobileNestBackend.repositories.realtime;
    realtime.disconnect();
    unawaited(() async {
      try {
        await realtime.connect();
      } catch (error) {
        AppLogger.warning('[Lifecycle] Realtime reconnect failed: $error');
      }
    }());
  } else {
    try {
      Supabase.instance.client.realtime.disconnect();
    } catch (e) {
      AppLogger.warning('[Lifecycle] Realtime disconnect failed: $e');
    }
  }

  // Invalidate the hot read paths so the user sees fresh data on whatever
  // screen they're on. SWR caches mean these don't flash empty.
  ref.invalidate(currentProfileProvider);
  ref.invalidate(activeQuestProvider);
  ref.invalidate(questHistoryProvider);
  ref.invalidate(userSubmissionsProvider);
  ref.invalidate(feedProvider);
  ref.invalidate(notificationsProvider);
  ref.invalidate(unreadCountProvider);
  ref.invalidate(leaderboardProvider);
  ref.invalidate(followingLeaderboardProvider);
  ref.invalidate(liveAppConfigProvider);
  // `appConfigProvider` is the one-shot read behind socialLoginEnabled;
  // unlike liveAppConfigProvider it has no realtime channel, so without
  // this it is only ever fetched once per process and an admin toggling
  // the social-login kill switch wouldn't land until a cold start.
  ref.invalidate(appConfigProvider);
  // Cheap re-read of the auth session to catch background refresh-token
  // rotations that finished while we were paused.
  ref.invalidate(authSessionProvider);
}
