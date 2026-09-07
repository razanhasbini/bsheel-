import 'dart:convert';

import 'package:app_repositories/app_repositories.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_contracts/supabase_contracts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/providers/supabase_provider.dart';
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

  factory PendingSubmission.fromJson(Map<String, dynamic> json) {
    final profile = json[Tables.profiles] as Map<String, dynamic>?;
    final userQuest = json[Tables.userQuests] as Map<String, dynamic>?;
    final quest = userQuest?[Tables.quests] as Map<String, dynamic>?;

    return PendingSubmission(
      id: (json[SubmissionColumns.id] ?? '').toString(),
      userId: (json[SubmissionColumns.userId] ?? '').toString(),
      userQuestId: (json[SubmissionColumns.userQuestId] ?? '').toString(),
      mediaUrl: (json[SubmissionColumns.mediaUrl] ?? '').toString(),
      mediaType: (json[SubmissionColumns.mediaType] ?? 'image').toString(),
      caption: json[SubmissionColumns.caption] as String?,
      status: (json[SubmissionColumns.status] ?? 'pending').toString(),
      submittedAt: DateTime.parse(
        json[SubmissionColumns.submittedAt].toString(),
      ),
      username: profile?[ProfileColumns.username] as String?,
      displayName: profile?[ProfileColumns.displayName] as String?,
      questTitle: quest?[QuestColumns.title] as String?,
      appealNote: json[SubmissionColumns.appealNote] as String?,
      appealed: json[SubmissionColumns.appealed] == true,
    );
  }
}

final pendingSubmissionsProvider =
    FutureProvider.autoDispose<List<PendingSubmission>>((ref) async {
  final client = ref.watch(supabaseClientProvider);

  // Oldest-first: anything left rotting at the top of the queue is what's
  // most likely to leak past the user's expected review SLA.
  final raw = await client
      .from(Tables.submissions)
      .select(
        '*, profiles!submissions_user_id_fkey(${ProfileColumns.username}, ${ProfileColumns.displayName}), ${Tables.userQuests}(*, ${Tables.quests}(${QuestColumns.title}))',
      )
      .eq(SubmissionColumns.status, SubmissionStatus.pending)
      .order(SubmissionColumns.submittedAt, ascending: true);

  final pending = (raw as List)
      .map((e) => PendingSubmission.fromJson(Map<String, dynamic>.from(e)))
      .toList();

  if (pending.isEmpty) return pending;

  // Enrich in two batched queries keyed by the set of users who appear in the
  // current pending list — avoids N+1 round-trips when the queue grows.
  final userIds = pending.map((s) => s.userId).toSet().toList();

  final history = await client
      .from(Tables.submissions)
      .select('${SubmissionColumns.userId}, ${SubmissionColumns.status}, '
          '${SubmissionColumns.mediaUrl}, ${SubmissionColumns.caption}')
      .inFilter(SubmissionColumns.userId, userIds);

  final approvedByUser = <String, int>{};
  final rejectedByUser = <String, int>{};
  // Per user, the set of media URLs and captions that have previously been
  // rejected. A pending submission whose URL or (non-trivial) caption matches
  // one of these is flagged as a likely re-upload of something already denied.
  final rejectedUrlsByUser = <String, Set<String>>{};
  final rejectedCaptionsByUser = <String, Set<String>>{};

  for (final row in history as List) {
    final m = Map<String, dynamic>.from(row);
    final uid = (m[SubmissionColumns.userId] ?? '').toString();
    final status = (m[SubmissionColumns.status] ?? '').toString();

    if (status == SubmissionStatus.approved) {
      approvedByUser[uid] = (approvedByUser[uid] ?? 0) + 1;
    } else if (status == SubmissionStatus.rejected) {
      rejectedByUser[uid] = (rejectedByUser[uid] ?? 0) + 1;

      final url = (m[SubmissionColumns.mediaUrl] ?? '').toString().trim();
      if (url.isNotEmpty) {
        rejectedUrlsByUser.putIfAbsent(uid, () => <String>{}).add(url);
      }
      final cap = (m[SubmissionColumns.caption] as String?)?.trim() ?? '';
      if (cap.length >= 8) {
        rejectedCaptionsByUser
            .putIfAbsent(uid, () => <String>{})
            .add(cap.toLowerCase());
      }
    }
  }

  final enriched = pending.map((s) {
    final priorUrls = rejectedUrlsByUser[s.userId] ?? const <String>{};
    final priorCaptions = rejectedCaptionsByUser[s.userId] ?? const <String>{};
    final cap = (s.caption ?? '').trim();
    final isDuplicate = priorUrls.contains(s.mediaUrl.trim()) ||
        (cap.length >= 8 && priorCaptions.contains(cap.toLowerCase()));

    return s.copyWith(
      userApprovedCount: approvedByUser[s.userId] ?? 0,
      userRejectedCount: rejectedByUser[s.userId] ?? 0,
      isDuplicate: isDuplicate,
      captionFlags: CaptionFlags.compute(s.caption),
    );
  }).toList();

  return Future.wait(
    enriched.map((s) async {
      return s.copyWith(
        mediaUrl: await SignedMediaUrls.signJsonOrSingle(client, s.mediaUrl),
      );
    }),
  );
});

/// Realtime feed for the moderation queue. Any insert/update on
/// `submissions` invalidates the pending list, so a new submission
/// pops in for the on-call moderator without manual refresh.
///
/// Page-scoped — watch from the pending submissions page; the channel
/// is torn down when the moderator navigates away.
final pendingSubmissionsRealtimeProvider = Provider.autoDispose<void>((ref) {
  final client = Supabase.instance.client;

  final channel = client.channel('admin_pending_submissions')
    ..onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: Tables.submissions,
      callback: (_) {
        if (kDebugMode) {
          debugPrint(
            '[Realtime] submissions change → refresh moderation queue',
          );
        }
        ref.invalidate(pendingSubmissionsProvider);
      },
    )
    ..subscribe();

  ref.onDispose(() {
    client.removeChannel(channel);
  });
});
