import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app_core/app_core.dart';
import 'package:app_models/app_models.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../../core/services/analytics_service.dart';
import '../../../../core/utils/account_lock_guard.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../feed/presentation/providers/post_realtime_provider.dart';
import '../../application/mention_controller.dart';
import '../widgets/comment_composer.dart';
import '../widgets/mention_picker.dart';
import '../widgets/comments_section.dart';

/// Opens the comments screen for [submissionId].
///
/// `export/mobile/10-comments.jpg` is a full screen — status bar at the top,
/// a back button, and `COMMENTS · 23` as the page title — not the draggable
/// half-height sheet the feed used to open. It is pushed rather than routed
/// so the feed keeps its scroll position underneath, and on the root
/// navigator so the composer is never hidden behind the floating nav pill.
Future<void> openCommentsPage(
  BuildContext context, {
  required String submissionId,
}) {
  return Navigator.of(context, rootNavigator: true).push<void>(
    PageRouteBuilder<void>(
      transitionDuration: const Duration(milliseconds: 220),
      reverseTransitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (_, __, ___) => CommentsPage(submissionId: submissionId),
      transitionsBuilder: (_, animation, __, child) {
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 1),
            end: Offset.zero,
          ).animate(
            CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
          ),
          child: child,
        );
      },
    ),
  );
}

class CommentsPage extends ConsumerStatefulWidget {
  const CommentsPage({super.key, required this.submissionId});

  final String submissionId;

  @override
  ConsumerState<CommentsPage> createState() => _CommentsPageState();
}

class _CommentsPageState extends ConsumerState<CommentsPage> {
  final _controller = MentionTextEditingController();
  final _focus = FocusNode();
  bool _submitting = false;
  CommentModel? _replyingTo;

  // Shared @-mention plumbing (debounce, suggestion queries, insert logic)
  // lives in MentionInputController; this page only renders the picker.
  late final MentionInputController _mention;

  @override
  void initState() {
    super.initState();
    _mention = MentionInputController(
      textController: _controller,
      focusNode: _focus,
      ref: ref,
      onSuggestionsChanged: () {
        if (mounted) setState(() {});
      },
    );
  }

  @override
  void dispose() {
    _mention.dispose();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onReplyTap(CommentModel comment) {
    setState(() => _replyingTo = comment);
    _focus.requestFocus();
  }

  Future<void> _send() async {
    // Tap-while-submitting: nudge rather than swallow, so the user knows
    // the tap registered instead of wondering whether it was lost.
    if (_submitting) {
      HapticFeedback.lightImpact();
      return;
    }
    final body = _controller.text.trim();
    if (body.isEmpty) return;
    if (guardAccountAction(context, ref)) return;

    final parentId = _replyingTo?.id;
    setState(() => _submitting = true);
    try {
      await ref
          .read(commentsRepositoryProvider)
          .addComment(widget.submissionId, body, parentId: parentId);
      ref.read(analyticsProvider).commentAdded(widget.submissionId);
      _controller.clear();
      _mention.clearSelectedMentions();
      _focus.unfocus();
      setState(() => _replyingTo = null);
      ref.invalidate(commentsProvider(widget.submissionId));
      await ref.read(commentsProvider(widget.submissionId).future);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(content: Text(mapDbError(e, action: 'post comment'))),
        );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Live updates: refresh the list when anyone comments or reacts on this
    // post, so a reader never sits on a stale thread.
    ref.watch(postRealtimeProvider(widget.submissionId));
    final l = AppLocalizations.of(context)!;
    final count = ref.watch(commentsProvider(widget.submissionId)).maybeWhen(
          data: (comments) =>
              comments.fold<int>(0, (sum, c) => sum + 1 + c.replies.length),
          orElse: () => 0,
        );

    return Scaffold(
      backgroundColor: QuestColors.osBg,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
              child: Row(
                children: [
                  ArcadeBackButton(onTap: () => Navigator.of(context).pop()),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      count > 0 ? '${l.comments} · $count' : l.comments,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: QuestTypography.osDisplaySmall.copyWith(
                        fontSize: 22,
                        height: 1.1,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => FocusScope.of(context).unfocus(),
                child: SingleChildScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(14, 4, 14, 16),
                  child: CommentsSection(
                    submissionId: widget.submissionId,
                    onReplyTap: _onReplyTap,
                  ),
                ),
              ),
            ),
            CommentComposer(
              controller: _controller,
              focusNode: _focus,
              submitting: _submitting,
              onSend: _send,
              replyingTo: _replyingTo,
              onCancelReply: () => setState(() => _replyingTo = null),
              hint: l.addComment,
              mentionSuggestions: _mention.suggestions,
              mentionLoading: _mention.loading,
              mentionQuery: _mention.query,
              onMentionTap: _mention.insertMention,
            ),
          ],
        ),
      ),
    );
  }
}
