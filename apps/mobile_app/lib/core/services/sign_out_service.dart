import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app_core/app_core.dart' show AppLogger;

import '../providers/auth_repository_provider.dart';
import '../providers/current_profile_provider.dart' show resetProfileCache;
import '../../features/feed/presentation/providers/feed_provider.dart'
    show
        resetFeedCache,
        feedLastIndexProvider,
        feedSortProvider,
        feedScopeProvider;
import '../../features/leaderboard/presentation/providers/leaderboard_provider.dart'
    show resetLeaderboardCaches;
import '../../features/notifications/presentation/providers/notifications_provider.dart'
    show resetNotificationCaches;
import '../../features/onboarding/presentation/providers/onboarding_provider.dart'
    show clearOnboardingComplete;
import '../../features/quests/data/quest_providers.dart' show resetQuestCaches;
import '../../features/quests/presentation/widgets/home_extras.dart'
    show resetQotdCache;
import '../../features/reactions/presentation/providers/reaction_controller.dart'
    show resetReactionState;
import '../../features/submissions/data/submission_providers.dart'
    show resetSubmissionsCache;
import 'analytics_service.dart';
import '../backend/app_backend.dart';

/// Single sign-out entry point. Clears every device-scoped cache,
/// resets analytics identity, removes the FCM token from this device's
/// profile row, clears the onboarding flag, and finally calls
/// `signOut()`. Call this from every sign-out UI surface (settings,
/// delete-account success, profile error state) — never call
/// `authRepository.signOut()` directly.
///
/// Ordering is intentional:
///   1. Delete server-side FCM token while we still have a session.
///   2. Clear device-scoped flags (onboarding, analytics).
///   3. Clear module-level SWR caches so the next user can't see them.
///   4. Sign out (auth listener will also fire defensive cache resets).
Future<void> signOutAndCleanup(WidgetRef ref) async {
  try {
    await _deleteFcmTokenServerSide();
  } catch (e) {
    AppLogger.warning('[SignOut] FCM token delete failed: $e');
  }

  try {
    await clearOnboardingComplete();
  } catch (e) {
    AppLogger.warning('[SignOut] clear onboarding flag failed: $e');
  }

  try {
    ref.read(analyticsProvider).reset();
  } catch (e) {
    AppLogger.warning('[SignOut] analytics reset failed: $e');
  }

  _resetAllModuleCaches();
  _resetPersistentFeedState(ref);

  await ref.read(authRepositoryProvider).signOut();
}

/// Drops every top-level SWR cache in the app. Safe to call multiple
/// times. Called from `signOutAndCleanup` AND defensively from the
/// `AuthNotifier` listener so a silent token expiry also clears state.
void resetAllModuleCaches() => _resetAllModuleCaches();

void _resetAllModuleCaches() {
  resetProfileCache();
  resetQuestCaches();
  resetSubmissionsCache();
  resetQotdCache();
  resetFeedCache();
  resetLeaderboardCaches();
  resetNotificationCaches();
  resetReactionState();
}

void _resetPersistentFeedState(WidgetRef ref) {
  try {
    ref.read(feedLastIndexProvider.notifier).state = 0;
    ref.read(feedSortProvider.notifier).state = 'recent';
    ref.read(feedScopeProvider.notifier).state = 'global';
  } catch (e) {
    AppLogger.warning('[SignOut] feed-state reset failed: $e');
  }
}

Future<void> _deleteFcmTokenServerSide() async {
  if (kIsWeb) return;
  if (Firebase.apps.isEmpty) return;
  final user = AppBackend.repositories.auth.currentUser;
  if (user == null) return;
  try {
    final token = await FirebaseMessaging.instance.getToken();
    if (token == null) return;
    await AppBackend.repositories.account.deleteDeviceToken(token);
    AppLogger.info('[SignOut] FCM token removed from profile');
  } catch (e) {
    AppLogger.warning('[SignOut] FCM RPC failed (continuing): $e');
  }
}
