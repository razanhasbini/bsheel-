import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:app_core/app_core.dart';
import 'package:app_models/app_models.dart';
import 'package:app_repositories/app_repositories.dart';
import 'package:shared_ui/shared_ui.dart';
import '../../../../design/bs_widgets.dart';
import '../../../../core/providers/auth_session_provider.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/backend/app_backend.dart';
import '../../../../core/utils/account_lock_guard.dart';
import '../../../../l10n/app_localizations.dart';

// ── Public providers (used by page to invalidate after posting) ──────────────

/// Single source of truth for the comments repository instance. Pages
/// should consume this rather than constructing a repository
/// inline (the same anti-pattern was tripping up tests + future repo
/// caching tweaks). ARC-008.
final commentsRepositoryProvider = Provider<CommentsRepository>((ref) {
  return AppBackend.repositories.comments;
});

final commentsProvider = FutureProvider.autoDispose
    .family<List<CommentModel>, String>((ref, submissionId) async {
  final repo = ref.watch(commentsRepositoryProvider);
  try {
    return await repo.getComments(submissionId);
  } catch (e, st) {
    if (kDebugMode) {
      debugPrint('[Comments] ERROR loading $submissionId: $e\n$st');
    }
    rethrow;
  }
});

/// Callback type for when the user taps "Reply" on a comment.
typedef OnReplyTap = void Function(CommentModel comment);

// ── Pure list display widget ──────────────────────────────────────────────────

class CommentsSection extends ConsumerWidget {
  final String submissionId;
  final OnReplyTap? onReplyTap;

  const CommentsSection({
    super.key,
    required this.submissionId,
    this.onReplyTap,
  });

  // Delegates to the shared formatter so every surface (mobile,
  // admin, comments, feed, notifications) shows the same string for
  // the same timestamp. ARC-020.
  String _timeAgo(DateTime dt) => timeAgo(dt);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final commentsAsync = ref.watch(commentsProvider(submissionId));

    return commentsAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ),
      error: (e, __) {
        if (kDebugMode) debugPrint('[Comments] Widget showing error: $e');
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(
            AppLocalizations.of(context)!.couldNotLoadComments,
            style: QuestTypography.bodySmall.copyWith(
              color: QuestColors.textDim(context),
            ),
          ),
        );
      },
      data: (comments) {
        if (comments.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              AppLocalizations.of(context)!.noCommentsYet,
              style: QuestTypography.bodySmall.copyWith(
                color: QuestColors.textDim(context),
              ),
            ),
          );
        }

        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: comments.length,
          itemBuilder: (_, i) => _CommentThread(
            comment: comments[i],
            timeAgo: _timeAgo,
            onReplyTap: onReplyTap,
          ),
        );
      },
    );
  }
}

// ── Single comment + its replies ────────────────────────────────────────────

class _CommentThread extends StatelessWidget {
  const _CommentThread({
    required this.comment,
    required this.timeAgo,
    this.onReplyTap,
  });

  final CommentModel comment;
  final String Function(DateTime) timeAgo;
  final OnReplyTap? onReplyTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _CommentTile(
          comment: comment,
          timeAgo: timeAgo,
          onReplyTap: onReplyTap,
        ),
        if (comment.replies.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 36),
            child: Column(
              children: comment.replies
                  .map((reply) => _CommentTile(
                        comment: reply,
                        timeAgo: timeAgo,
                        onReplyTap: onReplyTap,
                        isReply: true,
                      ))
                  .toList(),
            ),
          ),
      ],
    );
  }
}

// ── Single comment row ──────────────────────────────────────────────────────

class _CommentTile extends ConsumerWidget {
  const _CommentTile({
    required this.comment,
    required this.timeAgo,
    this.onReplyTap,
    this.isReply = false,
  });

  final CommentModel comment;
  final String Function(DateTime) timeAgo;
  final OnReplyTap? onReplyTap;
  final bool isReply;

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    if (guardAccountAction(context, ref)) return;
    // UX-107: long-press → confirm dialog → delete via repo. RLS keeps
    // the destructive action safe even if the UI lets a non-owner tap.
    final confirmed = await showBsheelConfirm(
      context,
      title: 'Delete comment?',
      message: 'This can\'t be undone.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(commentsRepositoryProvider).deleteComment(comment.id);
      ref.invalidate(commentsProvider(comment.submissionId));
    } catch (e) {
      messenger
        ..clearSnackBars()
        ..showSnackBar(
            SnackBar(content: Text(mapDbError(e, action: 'delete comment'))));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name =
        comment.displayName.isNotEmpty ? comment.displayName : comment.username;
    final isMine = ref.watch(authSessionProvider)?.id == comment.userId;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // UX-107: long-press own comment → confirm + delete.
        onLongPress: isMine ? () => _confirmDelete(context, ref) : null,
        // PR-#32: tapping the row opens the commenter's profile.
        onTap: () => context.pushNamed(
          RouteNames.userProfile,
          pathParameters: {'userId': comment.userId},
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PixelAvatar(
              imageUrl: comment.avatarUrl,
              username: comment.username,
              size: isReply ? 22 : 28,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      // Main: shrink-to-fit the author name so long handles
                      // don't push the timestamp off the row.
                      Flexible(
                        child: FitText(
                          name,
                          minFontSize: 9,
                          style: QuestTypography.labelSmall.copyWith(
                            color: QuestColors.text(context),
                            fontSize: isReply ? 11 : 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          timeAgo(comment.createdAt),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: QuestTypography.labelSmall.copyWith(
                            color: QuestColors.text(context).withAlpha(120),
                            fontSize: 9,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  _MentionText(
                    text: comment.body,
                    isReply: isReply,
                  ),
                  if (onReplyTap != null && !isReply)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => onReplyTap!(comment),
                        child: BsMinTouch(
                          minWidth: 56,
                          child: Text(
                            'REPLY',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: QuestTypography.labelSmall.copyWith(
                              color: QuestColors.textDim(context),
                              fontSize: 10,
                              letterSpacing: 1,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MentionText extends ConsumerStatefulWidget {
  const _MentionText({
    required this.text,
    required this.isReply,
  });

  final String text;
  final bool isReply;

  @override
  ConsumerState<_MentionText> createState() => _MentionTextState();
}

class _MentionTextState extends ConsumerState<_MentionText> {
  final List<TapGestureRecognizer> _recognizers = [];

  @override
  void dispose() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    super.dispose();
  }

  void _resetRecognizers() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  Future<void> _openMentionProfile(String username) async {
    try {
      // Exact username lookup — search is fuzzy and must not decide where
      // an @mention navigates.
      final profile =
          await AppBackend.repositories.profiles.getProfileByUsername(username);
      if (!mounted) return;
      if (profile == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('@$username was not found')),
        );
        return;
      }
      final userId = profile.id;
      if (userId.isEmpty) return;
      context.pushNamed(
        RouteNames.userProfile,
        pathParameters: {'userId': userId},
      );
    } catch (e) {
      AppLogger.error('[Mentions] Failed to open profile for @$username', e);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open profile')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    _resetRecognizers();
    final baseStyle = QuestTypography.bodySmall.copyWith(
      color: QuestColors.text(context),
      height: 1.4,
      fontSize: widget.isReply ? 12 : null,
    );
    final mentionStyle = baseStyle.copyWith(
      color: QuestColors.osPrimary,
      fontWeight: FontWeight.w800,
    );
    final spans = <TextSpan>[];
    // Unicode-aware so Arabic/Arabizi @mentions render as tappable
    // pills instead of falling back to plain text.
    final mentionRegex = RegExp(r'@([\p{L}\p{N}_]{3,30})', unicode: true);
    var cursor = 0;

    for (final match in mentionRegex.allMatches(widget.text)) {
      if (match.start > cursor) {
        spans.add(TextSpan(text: widget.text.substring(cursor, match.start)));
      }
      final recognizer = TapGestureRecognizer()
        ..onTap = () => _openMentionProfile(match.group(1)!);
      _recognizers.add(recognizer);
      spans.add(
        TextSpan(
          text: widget.text.substring(match.start, match.end),
          style: mentionStyle,
          recognizer: recognizer,
        ),
      );
      cursor = match.end;
    }

    if (cursor < widget.text.length) {
      spans.add(TextSpan(text: widget.text.substring(cursor)));
    }

    return RichText(
      text: TextSpan(style: baseStyle, children: spans),
    );
  }
}
