import 'dart:io' show Platform;

import 'package:app_core/app_core.dart' show AppLogger;
import 'package:app_models/app_models.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Thin Dart wrapper around the native `app/live_activity` MethodChannel
/// implemented in `ios/Runner/QuestLiveActivityChannel.swift`.
///
/// Why hand-rolled (no third-party plugin): the user vetoed
/// pub.dev/npm-style dependencies for this surface. ActivityKit's API is
/// small enough that a 5-method channel covers it.
class LiveActivityService {
  static const MethodChannel _channel = MethodChannel('app/live_activity');

  /// `true` only on iOS 16.1+ devices where the user hasn't disabled Live
  /// Activities in Settings. Cheap to call — the native side just reads
  /// `ActivityAuthorizationInfo`.
  Future<bool> isSupported() async {
    if (!Platform.isIOS) return false;
    try {
      final res = await _channel.invokeMethod<dynamic>('isSupported');
      // Old-iOS path returns the sentinel "available_no".
      if (res is bool) return res;
      return false;
    } catch (e) {
      AppLogger.warning('[LiveActivity] isSupported failed: $e');
      return false;
    }
  }

  /// Start (or update in-place, if one already exists for this quest) a
  /// Live Activity for the given active quest. Returns the activity id, or
  /// `null` if the device/OS can't host one.
  Future<String?> startForQuest(UserQuestModel userQuest) async {
    if (!Platform.isIOS) return null;
    final quest = userQuest.quest;
    final expires = userQuest.expiresAt;
    // Without a deadline the Dynamic Island countdown is meaningless.
    if (quest == null || expires == null) return null;

    try {
      final res = await _channel.invokeMethod<dynamic>('start', {
        'questId': userQuest.questId,
        'questTitle': quest.title,
        'xpReward': quest.xpReward,
        'expiresAtEpochMs': expires.millisecondsSinceEpoch,
        'status': 'active',
      });
      AppLogger.info('[LiveActivity] start → $res');
      return res is String ? res : null;
    } catch (e) {
      AppLogger.warning('[LiveActivity] start failed: $e');
      return null;
    }
  }

  /// Update the existing activity for [questId] (new deadline / new
  /// status). Silently no-ops if there is no activity to update.
  Future<void> update({
    required String questId,
    required DateTime expiresAt,
    String status = 'active',
  }) async {
    if (!Platform.isIOS) return;
    try {
      await _channel.invokeMethod<dynamic>('update', {
        'questId': questId,
        'expiresAtEpochMs': expiresAt.millisecondsSinceEpoch,
        'status': status,
      });
    } catch (e) {
      AppLogger.warning('[LiveActivity] update failed: $e');
    }
  }

  /// End the activity for [questId] (called when the quest is submitted,
  /// canceled, or expires).
  Future<void> endForQuest(String questId) async {
    if (!Platform.isIOS) return;
    try {
      await _channel.invokeMethod<dynamic>('end', {'questId': questId});
      AppLogger.info('[LiveActivity] end(quest=$questId)');
    } catch (e) {
      AppLogger.warning('[LiveActivity] end failed: $e');
    }
  }

  /// Nuke everything. Used on logout and on shell-mount as a defensive
  /// cleanup for activities that lingered past a crash.
  Future<void> endAll() async {
    if (!Platform.isIOS) return;
    try {
      await _channel.invokeMethod<dynamic>('endAll');
    } catch (e) {
      AppLogger.warning('[LiveActivity] endAll failed: $e');
    }
  }
}

final liveActivityServiceProvider = Provider<LiveActivityService>((ref) {
  return LiveActivityService();
});
