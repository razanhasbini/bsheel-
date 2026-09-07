import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mixpanel_flutter/mixpanel_flutter.dart';
import 'package:app_core/app_core.dart';
import '../config/env.dart';

final analyticsProvider = Provider<AnalyticsService>((ref) {
  return AnalyticsService.instance;
});

class AnalyticsService {
  AnalyticsService._();
  static final instance = AnalyticsService._();

  Mixpanel? _mixpanel;

  /// Migration 0142 / M18-LOW: gates Mixpanel init + every track / identify
  /// call. Default is FALSE — `init()` becomes a no-op until
  /// [setConsent] flips this to true (e.g. via the onboarding consent
  /// prompt, or when [currentProfileProvider] reports a non-null
  /// `analytics_consent_at`). Once granted in a session, stays granted.
  bool _consentGranted = false;

  /// Whether the user has granted analytics consent in this session.
  /// Read-only — flip via [setConsent].
  bool get hasConsent => _consentGranted;

  Future<void> init() async {
    // Intentionally a no-op pre-consent. We do NOT initialize Mixpanel
    // here. Bootstrap can still call this safely; the real init happens
    // inside [setConsent] once the user accepts the analytics opt-in.
    if (kIsWeb) {
      AppLogger.info('[Analytics] Skipping Mixpanel on web');
      return;
    }
    AppLogger.info('[Analytics] init() — waiting for consent before Mixpanel');
  }

  /// Set the consent state. When [granted] flips from false → true,
  /// Mixpanel is lazily initialized. When set to false, Mixpanel is
  /// reset and further calls become no-ops (matches GDPR opt-out).
  ///
  /// Call from the analytics-consent prompt OR from a Riverpod listener
  /// that watches `currentProfileProvider.analyticsConsentAt`.
  Future<void> setConsent(bool granted) async {
    if (_consentGranted == granted) return;
    _consentGranted = granted;
    if (!granted) {
      // Revoke: reset identity + drop the instance so further calls
      // are pure no-ops. The Mixpanel SDK doesn't expose a "destroy"
      // but `reset()` clears the distinct_id, and our gate stops new
      // sends.
      _mixpanel?.reset();
      AppLogger.info('[Analytics] Consent revoked — Mixpanel disabled');
      return;
    }
    if (kIsWeb) return;
    if (_mixpanel != null) {
      AppLogger.info('[Analytics] Consent re-granted on existing instance');
      return;
    }
    const token = Env.mixpanelToken;
    if (token.isEmpty) {
      AppLogger.info('[Analytics] Mixpanel token not set — staying disabled');
      return;
    }
    _mixpanel = await Mixpanel.init(token, trackAutomaticEvents: true);
    AppLogger.info('[Analytics] Mixpanel initialized after consent');
  }

  /// Identify the user after login/signup. No-op pre-consent.
  void identify(String userId, {String? username}) {
    if (!_consentGranted) return;
    _mixpanel?.identify(userId);
  }

  /// Reset identity on logout. Always safe to call; idempotent.
  void reset() => _mixpanel?.reset();

  /// Track a named event with optional properties. No-op pre-consent.
  void track(String event, [Map<String, dynamic>? properties]) {
    if (!_consentGranted) return;
    _mixpanel?.track(event, properties: properties);
  }

  // ── Convenience methods for the events that matter most ──

  void questAssigned(String questId, String category, String difficulty) {
    track('quest_assigned', {
      'quest_id': questId,
      'category': category,
      'difficulty': difficulty,
    });
  }

  void questCompleted(String questId, int xpEarned) {
    track('quest_completed', {
      'quest_id': questId,
      'xp_earned': xpEarned,
    });
  }

  void questExpired(String questId) {
    track('quest_expired', {'quest_id': questId});
  }

  void submissionApproved(String submissionId) {
    track('submission_approved', {'submission_id': submissionId});
  }

  void proofSubmitted(String userQuestId, int mediaCount) {
    track('proof_submitted', {
      'user_quest_id': userQuestId,
      'media_count': mediaCount,
    });
  }

  void feedViewed() => track('feed_viewed');

  void postShared(String postId) {
    track('post_shared', {'post_id': postId});
  }

  void profileShared(String userId) {
    track('profile_shared', {'user_id': userId});
  }

  // ── User journey ──

  void signup() => track('signup');

  void onboardingCompleted(String username) => track('onboarding_completed');

  // ── Quest behavior ──

  void questOptionsViewed(int count) {
    track('quest_options_viewed', {'options_count': count});
  }

  void questOptionPicked(String questId, String difficulty) {
    track('quest_option_picked', {
      'quest_id': questId,
      'difficulty': difficulty,
    });
  }

  // ── Social engagement ──

  void reactionAdded(String submissionId, String reactionType) {
    track('reaction_added', {
      'submission_id': submissionId,
      'reaction_type': reactionType,
    });
  }

  void commentAdded(String postId) {
    track('comment_added', {'post_id': postId});
  }

  void followAdded(String targetUserId) {
    track('follow_added', {'target_user_id': targetUserId});
  }

  void unfollowed(String targetUserId) {
    track('unfollowed', {'target_user_id': targetUserId});
  }

  void feedScrolled(int postCount) {
    track('feed_scrolled', {'posts_visible': postCount});
  }

  // ── Retention ──

  void appOpened() => track('app_opened');

  void notificationTapped(String type) {
    track('notification_tapped', {'notification_type': type});
  }

  // ── Collab ──

  void collabGroupCreated(String questId, String mode) {
    track('collab_group_created', {'quest_id': questId, 'mode': mode});
  }

  void collabGroupJoined(String questId, String mode) {
    track('collab_group_joined', {'quest_id': questId, 'mode': mode});
  }

  void collabVoteCast(String groupId) {
    track('collab_vote_cast', {'group_id': groupId});
  }

  void collabQuestAbandoned(String questId) {
    track('collab_quest_abandoned', {'quest_id': questId});
  }
}
