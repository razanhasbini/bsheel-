import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/backend/app_backend.dart';
import '../../util/caption_flags.dart';

class PendingSubmission {
  final String id;
  final String userId;
  final String userQuestId;
  final String mediaUrl;
  final String mediaType;
  final String? caption;
  final String status;
  final DateTime submittedAt;
  final String? username;
  final String? displayName;
  final String? questTitle;
  final String? appealNote;
  final bool appealed;

  // Enrichment fields. None of these are persisted — they're computed by the
  // provider after the base fetch and surfaced to the UI as warning badges
  // ("DUPLICATE", "SPAM", "INAPPROPRIATE") or trust hints ("✓3 / ✗1").
  final int userApprovedCount;
  final int userRejectedCount;
  final bool isDuplicate;
  final List<String> captionFlags;

  const PendingSubmission({
    required this.id,
    required this.userId,
    required this.userQuestId,
    required this.mediaUrl,
    required this.mediaType,
    this.caption,
    required this.status,
    required this.submittedAt,
    this.username,
    this.displayName,
    this.questTitle,
    this.appealNote,
    this.appealed = false,
    this.userApprovedCount = 0,
    this.userRejectedCount = 0,
    this.isDuplicate = false,
    this.captionFlags = const [],
  });

  /// Parsed list of media URLs. `media_url` may be either a bare URL or a
  /// JSON-encoded array — older submissions are bare strings; newer multi-
  /// asset uploads are arrays. Always returns at least an empty list.
  List<String> get mediaUrls {
    final raw = mediaUrl.trim();
    if (raw.isEmpty) return const [];
    if (raw.startsWith('[')) {
      try {
        return (jsonDecode(raw) as List)
            .map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty)
            .toList();
      } catch (_) {
        // Fall through to bare-string handling.
      }
    }
    return [raw];
  }

  bool get isVideo {
    if (mediaType == 'video') return true;
    if (mediaUrls.isEmpty) return false;
    final first = mediaUrls.first.toLowerCase();
    return first.endsWith('.mp4') ||
        first.endsWith('.mov') ||
        first.endsWith('.webm') ||
        first.endsWith('.m4v');
  }

  PendingSubmission copyWith({
    String? mediaUrl,
    int? userApprovedCount,
    int? userRejectedCount,
    bool? isDuplicate,
    List<String>? captionFlags,
  }) {
    return PendingSubmission(
      id: id,
      userId: userId,
      userQuestId: userQuestId,
      mediaUrl: mediaUrl ?? this.mediaUrl,
      mediaType: mediaType,
      caption: caption,
      status: status,
      submittedAt: submittedAt,
      username: username,
      displayName: displayName,
      questTitle: questTitle,
      appealNote: appealNote,
      appealed: appealed,
      userApprovedCount: userApprovedCount ?? this.userApprovedCount,
      userRejectedCount: userRejectedCount ?? this.userRejectedCount,
      isDuplicate: isDuplicate ?? this.isDuplicate,
      captionFlags: captionFlags ?? this.captionFlags,
    );
  }

  /// The review-queue endpoint returns flat joined columns plus the
  /// server-computed reviewer context.
  factory PendingSubmission.fromJson(Map<String, dynamic> json) {
    return PendingSubmission(
      id: (json['id'] ?? '').toString(),
      userId: (json['user_id'] ?? '').toString(),
      userQuestId: (json['user_quest_id'] ?? '').toString(),
      mediaUrl: (json['media_url'] ?? '').toString(),
      mediaType: (json['media_type'] ?? 'image').toString(),
      caption: json['caption'] as String?,
      status: (json['status'] ?? 'pending').toString(),
      submittedAt: DateTime.parse(json['submitted_at'].toString()),
      username: json['username'] as String?,
      displayName: json['display_name'] as String?,
      questTitle: json['quest_title'] as String?,
      appealNote: json['appeal_note'] as String?,
      appealed: json['appealed'] == true,
      userApprovedCount: (json['user_approved_count'] as num?)?.toInt() ?? 0,
      userRejectedCount: (json['user_rejected_count'] as num?)?.toInt() ?? 0,
      isDuplicate: json['is_duplicate'] == true,
    );
  }
}

final pendingSubmissionsProvider =
    FutureProvider.autoDispose<List<PendingSubmission>>((ref) async {
  // Oldest-first: anything left rotting at the top of the queue is what is
  // most likely to leak past the review SLA. The counts and the duplicate
  // flag are computed by the API in the same query, so the client no longer
  // fetches every submission for every user in the queue to derive them.
  final rows = await AppBackend.repositories.moderation.reviewQueue();
  return rows.map((row) {
    final submission = PendingSubmission.fromJson(row);
    // Caption heuristics are presentation-level text rules, so they stay
    // here rather than in the database.
    return submission.copyWith(
      captionFlags: CaptionFlags.compute(submission.caption),
    );
  }).toList();
});

/// Realtime feed for the moderation queue. Any insert/update on
/// `submissions` invalidates the pending list, so a new submission
/// pops in for the on-call moderator without manual refresh.
///
/// Page-scoped — watch from the pending submissions page; the channel
/// is torn down when the moderator navigates away.
final pendingSubmissionsRealtimeProvider = Provider.autoDispose<void>((ref) {
  final realtime = AppBackend.repositories.realtime;
  final subscription = realtime.events
      .where((event) => event.type.startsWith('submission.'))
      .listen((_) {
    if (kDebugMode) {
      debugPrint('[Realtime] submission event → refresh moderation queue');
    }
    ref.invalidate(pendingSubmissionsProvider);
  });
  unawaited(() async {
    try {
      await realtime.connect();
    } catch (error) {
      if (kDebugMode) {
        debugPrint('[Realtime] Moderation queue connection failed: $error');
      }
    }
  }());
  ref.onDispose(() => unawaited(subscription.cancel()));
});
