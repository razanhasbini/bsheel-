import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app_core/app_core.dart' show AppLogger;
import 'package:app_models/app_models.dart';
import 'package:app_repositories/app_repositories.dart';
import 'package:supabase_contracts/supabase_contracts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/providers/supabase_provider.dart';
import '../../../../core/providers/auth_session_provider.dart';
import '../../../../core/backend/backend_config.dart';
import '../../../../core/backend/mobile_nest_backend.dart';

final notificationsRepositoryProvider =
    Provider<NotificationsRepository>((ref) {
  return SupabaseNotificationsRepository(ref.watch(supabaseClientProvider));
});

// SWR caches — keep last-good notifications + unread count on screen if a
// refresh fails (matches the rest of the app's read providers).
List<NotificationModel>? _lastGoodNotifications;
int? _lastGoodUnread;

/// Drops the module-scoped SWR caches. Call on sign-out so the next user
/// on the same device can't see the previous user's notification badge.
void resetNotificationCaches() {
  _lastGoodNotifications = null;
  _lastGoodUnread = null;
}

final notificationsProvider =
    FutureProvider<List<NotificationModel>>((ref) async {
  // Keep dependency so auth changes re-evaluate this provider.
  final user = ref.watch(authSessionProvider);
  if (user == null) {
    _lastGoodNotifications = null;
    return [];
  }
  try {
    final fresh = await ref
        .watch(notificationsRepositoryProvider)
        .getNotifications(user.id)
        .timeout(const Duration(seconds: 8));
    _lastGoodNotifications = fresh;
    return fresh;
  } catch (e) {
    if (_lastGoodNotifications != null) {
      AppLogger.warning('[Notifications] Fetch failed, serving cached: $e');
      return _lastGoodNotifications!;
    }
    rethrow;
  }
});

/// Realtime subscription that invalidates notification providers when a
/// row is inserted/updated for the current user. Watch this from the
/// notifications page (and the bottom-nav bell if it's mounted) so the
/// badge + list stay in sync with FCM pushes without requiring a pull.
final notificationsRealtimeProvider = Provider.autoDispose<void>((ref) {
  final user = ref.watch(authSessionProvider);
  if (user == null) return;

  Timer? throttle;
  void scheduleInvalidate() {
    throttle?.cancel();
    throttle = Timer(const Duration(milliseconds: 250), () {
      ref.invalidate(notificationsProvider);
      ref.invalidate(unreadCountProvider);
    });
  }

  if (BackendConfig.usesNest) {
    final realtime = MobileNestBackend.repositories.realtime;
    final subscription = realtime.events
        .where((event) => event.type.startsWith('notification.'))
        .listen((_) => scheduleInvalidate());
    unawaited(() async {
      try {
        await realtime.connect();
      } catch (error) {
        AppLogger.warning('[Realtime] Notification connection failed: $error');
      }
    }());
    ref.onDispose(() {
      throttle?.cancel();
      unawaited(subscription.cancel());
    });
    return;
  }

  final client = ref.watch(supabaseClientProvider);

  final channel = client.channel('notifications_realtime_${user.id}')
    ..onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: Tables.notifications,
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: NotificationColumns.userId,
        value: user.id,
      ),
      callback: (_) => scheduleInvalidate(),
    )
    ..onPostgresChanges(
      event: PostgresChangeEvent.update,
      schema: 'public',
      table: Tables.notifications,
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: NotificationColumns.userId,
        value: user.id,
      ),
      callback: (_) => scheduleInvalidate(),
    )
    ..subscribe();

  ref.onDispose(() {
    throttle?.cancel();
    client.removeChannel(channel);
  });
});

final unreadCountProvider = FutureProvider<int>((ref) async {
  // Keep dependency so auth changes re-evaluate this provider.
  final user = ref.watch(authSessionProvider);
  if (user == null) {
    _lastGoodUnread = null;
    return 0;
  }
  try {
    final fresh = await ref
        .watch(notificationsRepositoryProvider)
        .getUnreadCount(user.id)
        .timeout(const Duration(seconds: 5));
    _lastGoodUnread = fresh;
    return fresh;
  } catch (e) {
    if (_lastGoodUnread != null) {
      AppLogger.warning('[UnreadCount] Fetch failed, serving cached: $e');
      return _lastGoodUnread!;
    }
    // Badge defaults to 0 rather than rethrowing — an angry red dot on
    // transient errors is worse than a missing one.
    return 0;
  }
});
