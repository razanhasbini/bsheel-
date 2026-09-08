import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../comments/presentation/widgets/comments_section.dart';
import 'feed_post_details_provider.dart';
import 'feed_provider.dart';
import '../../../../core/backend/app_backend.dart';

/// Subscribes to Postgres changes on `reactions` and `comments` rows whose
/// `submission_id` equals [submissionId], and invalidates the providers
/// that drive the post detail UI whenever a change comes in.
///
/// This is what makes another user's vote or comment appear without the
/// viewer having to close + reopen the app. Watch it from any widget that
/// shows live counts/comments for a single post (the post details page,
/// the comments sheet on the reels feed). The channel is torn down via
/// `autoDispose` once nothing watches it.
final postRealtimeProvider =
    Provider.autoDispose.family<void, String>((ref, submissionId) {
  void invalidateCounts() {
    ref.invalidate(feedPostDetailsProvider(submissionId));
  }

  void invalidateCountsAndComments() {
    ref.invalidate(feedPostDetailsProvider(submissionId));
    ref.invalidate(commentsProvider(submissionId));
  }

  final realtime = AppBackend.repositories.realtime;
  final subscription = realtime.events.where((event) {
    return event.data['submissionId'] == submissionId;
  }).listen((event) {
    if (event.type == 'social.comment.changed') {
      invalidateCountsAndComments();
    } else if (event.type == 'social.reaction.changed' ||
        event.type.startsWith('submission.')) {
      invalidateCounts();
    }
  });
  var subscribed = false;
  unawaited(() async {
    try {
      await realtime.connect();
      realtime.subscribeToPost(submissionId);
      subscribed = true;
    } catch (error) {
      if (kDebugMode) {
        debugPrint('[Realtime] Post connection failed: $error');
      }
    }
  }());
  ref.onDispose(() {
    if (subscribed) {
      try {
        realtime.unsubscribeFromPost(submissionId);
      } on Object {
        // The shared socket may already be reconnecting or signed out.
      }
    }
    unawaited(subscription.cancel());
  });
});

/// Page-scoped realtime for the FEED tab. Watches:
///   * `submissions` — new approved posts appear without pull-to-refresh,
///     deletions/visibility changes drop them out
///   * `reactions` and `saved_posts` (no per-post filter — covers every
///     post in the current feed window)
///
/// Counts on cards refresh by invalidating `feedPostDetailsProvider` for
/// the affected submission. The list itself only invalidates on
/// submission-row events (cheaper than re-fetching on every reaction).
///
/// Watch this from [FeedPage] so the channel is torn down when the user
/// leaves the feed tab.
final feedRealtimeProvider = Provider.autoDispose<void>((ref) {
  final realtime = AppBackend.repositories.realtime;
  final subscription = realtime.events.listen((event) {
    final submissionId = event.data['submissionId'];
    if (event.type.startsWith('submission.')) {
      ref.invalidate(feedProvider);
      if (submissionId is String) {
        ref.invalidate(feedPostDetailsProvider(submissionId));
      }
    } else if (event.type == 'social.reaction.changed' &&
        submissionId is String) {
      ref.invalidate(feedPostDetailsProvider(submissionId));
    }
  });
  unawaited(() async {
    try {
      await realtime.connect();
    } catch (error) {
      if (kDebugMode) {
        debugPrint('[Realtime] Feed connection failed: $error');
      }
    }
  }());
  ref.onDispose(() => unawaited(subscription.cancel()));
});
