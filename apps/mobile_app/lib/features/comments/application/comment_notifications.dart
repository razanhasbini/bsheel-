import 'package:app_core/app_core.dart';
import 'package:app_models/app_models.dart'
    show FeedPostModel, ProfileModel;
import 'package:supabase_contracts/supabase_contracts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/notification_sender.dart';
import '../presentation/widgets/mention_picker.dart' show MentionCandidate;

/// Shared comment-notification pipeline for every comment surface
/// (comments sheet + post-detail page). Comment notifications are
/// entirely client-driven (no DB trigger), so every surface that can
/// post a comment must fire these itself — previously each widget kept
/// its own near-identical copy, which already caused one production bug.

String _commenterName(ProfileModel? commenterProfile) =>
    commenterProfile != null && commenterProfile.displayName.isNotEmpty
        ? commenterProfile.displayName
        : commenterProfile?.username ?? 'Someone';

/// Resolves every `@handle` present in [body] to a [ProfileModel],
/// keyed by user id.
Future<Map<String, ProfileModel>> resolveMentionedUsers(
  SupabaseClient client,
  String body, {
  Map<String, MentionCandidate> selectedMentions = const {},
}) async {
  final mentioned = <String, ProfileModel>{};
  final lowerBody = body.toLowerCase();

  // Anything the user picked from the dropdown that's still present in
  // the body counts immediately — no DB hit needed.
  for (final candidate in selectedMentions.values) {
    if (lowerBody.contains('@${candidate.profile.username.toLowerCase()}')) {
      mentioned[candidate.profile.id] = candidate.profile;
    }
  }

  // Also catch typed-by-hand mentions (no dropdown pick). ARC-009:
  // resolve every unhandled handle in ONE round-trip rather than
  // looping per-handle with sequential ilikes.
  // Unicode-aware: matches Arabic, Arabizi (e.g. `@Tayseer`), and
  // any other letter/digit class — previously this was ASCII-only,
  // so Arabic-username mentions silently dropped from notifications.
  final unresolved = RegExp(r'@([\p{L}\p{N}_]{3,30})', unicode: true)
      .allMatches(body)
      .map((m) => m.group(1)!.toLowerCase())
      .toSet()
      .where(
          (u) => !mentioned.values.any((p) => p.username.toLowerCase() == u))
      .toList();
  if (unresolved.isNotEmpty) {
    // Use case-insensitive OR-ilike instead of exact-match inFilter so
    // a `@TaySEER` mention resolves to the user stored as `Tayseer`.
    // Strip whitespace, parens, commas, AND backslashes — PostgREST
    // .or() treats those as syntax / escape and a stray `\b` would
    // either error or quietly fail to match.
    final clauses = unresolved
        .map((u) => u.replaceAll(RegExp(r'[\s\\(),]'), ''))
        .where((u) => u.isNotEmpty)
        .map((u) => '${ProfileColumns.username}.ilike.$u')
        .join(',');
    if (clauses.isNotEmpty) {
      final rows = await client.from(Tables.profiles).select().or(clauses);
      for (final row in rows as List<dynamic>) {
        final profile = ProfileModel.fromJson(
          Map<String, dynamic>.from(row as Map),
        );
        mentioned[profile.id] = profile;
      }
    }
  }
  return mentioned;
}

/// Notify the post owner (new_comment) and prior thread participants
/// (comment_reply) about a fresh comment on [submissionId].
///
/// Pass the ids of mentioned users as [excludedUserIds] so nobody gets
/// both a thread notification and a mention notification for the same
/// comment. [logContext] keeps each surface's original log tag (e.g.
/// `CommentsSheet` / `PostDetails`) so log triage stays unchanged.
Future<void> sendCommentThreadNotifications({
  required SupabaseClient client,
  required String submissionId,
  required String body,
  required ProfileModel? commenterProfile,
  Set<String> excludedUserIds = const {},
  required String logContext,
}) async {
  try {
    final submission = await client
        .from(Tables.submissions)
        .select(SubmissionColumns.userId)
        .eq(SubmissionColumns.id, submissionId)
        .single();
    final ownerId = submission[SubmissionColumns.userId] as String;
    final commenterName = _commenterName(commenterProfile);
    final currentUserId = client.auth.currentUser?.id;
    final truncated = body.length > 50 ? '${body.substring(0, 50)}…' : body;

    if (!excludedUserIds.contains(ownerId) && ownerId != currentUserId) {
      await sendNotificationToUser(
        targetUserId: ownerId,
        title: '$commenterName dropped a comment. 💬',
        body: '"$truncated"',
        type: NotificationType.newComment,
        referenceId: submissionId,
      );
    }

    final previousComments = await client
        .from(Tables.comments)
        .select(CommentColumns.userId)
        .eq(CommentColumns.submissionId, submissionId);

    final alreadyNotified = <String>{
      ownerId,
      if (currentUserId != null) currentUserId,
      ...excludedUserIds,
    };
    for (final row in previousComments as List<dynamic>) {
      final participantId = row[CommentColumns.userId] as String;
      if (alreadyNotified.contains(participantId)) continue;
      alreadyNotified.add(participantId);
      await sendNotificationToUser(
        targetUserId: participantId,
        title: '$commenterName jumped into the thread. 🧵',
        body: '"$truncated"',
        type: NotificationType.commentReply,
        referenceId: submissionId,
      );
    }
  } catch (e) {
    AppLogger.error('[$logContext] Failed to send notifications', e);
  }
}

/// Notify every user in [mentioned] that they were @-mentioned in a
/// comment on [submissionId].
///
/// [post] enriches the copy with the quest title / owner name when the
/// caller has it loaded ("On {owner}'s post \"{title}\": …"); with no
/// post the copy degrades gracefully to "On someone's post: …".
/// [ellipsis] preserves each surface's exact legacy truncation copy
/// (the sheet historically used `…`, the detail page `...`).
Future<void> sendMentionNotifications({
  required SupabaseClient client,
  required String submissionId,
  required String body,
  required ProfileModel? commenterProfile,
  required Map<String, ProfileModel> mentioned,
  FeedPostModel? post,
  String ellipsis = '…',
}) async {
  if (mentioned.isEmpty) return;
  try {
    final currentUserId = client.auth.currentUser?.id;
    final commenterName = _commenterName(commenterProfile);
    final truncated =
        body.length > 50 ? '${body.substring(0, 50)}$ellipsis' : body;
    final postTitle = post?.questTitle.trim();
    final hasTitle = postTitle != null && postTitle.isNotEmpty;
    final postOwnerName = post == null
        ? 'someone'
        : post.displayName.isNotEmpty
            ? post.displayName
            : post.username;

    // ARC-010: fire notifications in parallel rather than awaiting
    // each in turn — a 5-mention comment used to take 5× the round-
    // trip time before the input bar reactivated.
    await Future.wait(mentioned.values.where((p) => p.id != currentUserId).map(
      (profile) {
        final ownerLabel = post?.userId == profile.id
            ? 'your post'
            : "$postOwnerName's post";
        final mentionBody = hasTitle
            ? 'On $ownerLabel "$postTitle": "$truncated"'
            : 'On $ownerLabel: "$truncated"';
        return sendNotificationToUser(
          targetUserId: profile.id,
          title: '$commenterName pulled you in. 📣',
          body: mentionBody,
          type: NotificationType.mention,
          referenceId: submissionId,
        );
      },
    ));
  } catch (e) {
    AppLogger.error('[Mentions] Failed to send mention notifications', e);
  }
}
