import 'package:app_core/app_core.dart';
import 'package:app_models/app_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/analytics_service.dart';
import '../../../../core/utils/account_lock_guard.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../comments/application/mention_controller.dart';
import '../../../comments/presentation/widgets/comment_composer.dart';
import '../../../comments/presentation/widgets/comments_section.dart';
import '../../../comments/presentation/widgets/mention_picker.dart';
import '../providers/post_realtime_provider.dart';

/// Slides up an Instagram-style comments bottom sheet for [submissionId] —
/// the way the reels feed opened comments in the legacy app, so the post
/// stays visible (and its video paused) underneath.
///
/// Drag the handle to grow the sheet from 50% up to 98% of the screen.
/// Tapping REPLY on a comment focuses the input with the reply target
/// shown as a chip above it. Posting, mentions and notification fan-out
/// all go through the same [CommentComposer] + repository path as the full
/// comments page, so the two can never drift.
Future<void> showCommentsSheet(
  BuildContext context, {
  required String submissionId,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: QuestColors.pureBlack.withAlpha(120),
    useSafeArea: true,
    // Mount above the bottom-nav shell so the input bar isn't hidden
    // behind the floating nav pill.
    useRootNavigator: true,
    builder: (_) => _CommentsSheet(submissionId: submissionId),
  );
}

class _CommentsSheet extends ConsumerStatefulWidget {
  const _CommentsSheet({required this.submissionId});
  final String submissionId;

  @override
  ConsumerState<_CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends ConsumerState<_CommentsSheet> {
  final _controller = MentionTextEditingController();
  final _focus = FocusNode();
  final _draggable = DraggableScrollableController();
  bool _submitting = false;
  CommentModel? _replyingTo;

  // Shared @-mention plumbing (debounce, suggestion queries, insert logic)
  // lives in MentionInputController; this sheet only renders the picker.
  late final MentionInputController _mention;

  @override
  void initState() {
    super.initState();
    // Whenever the user starts typing, expand the sheet to full-screen so
    // they can read comments while writing instead of staring at a small
    // window above the keyboard.
    _focus.addListener(_onFocusChange);
    _mention = MentionInputController(
      textController: _controller,
      focusNode: _focus,
      ref: ref,
      onSuggestionsChanged: () {
        if (mounted) setState(() {});
      },
    );
  }

  void _onFocusChange() {
    if (!_focus.hasFocus) return;
    if (!_draggable.isAttached) return;
    if (_draggable.size < 0.94) {
      _draggable.animateTo(
        0.98,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  void dispose() {
    _mention.dispose();
    _focus.removeListener(_onFocusChange);
    _controller.dispose();
    _focus.dispose();
    _draggable.dispose();
    super.dispose();
  }

  void _onReplyTap(CommentModel comment) {
    setState(() => _replyingTo = comment);
    // Focus the input and grow the sheet so the keyboard + input + replied
    // comment all fit comfortably.
    Future.microtask(() {
      if (!mounted) return;
      _focus.requestFocus();
      if (_draggable.isAttached && _draggable.size < 0.85) {
        _draggable.animateTo(0.92,
            duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
      }
    });
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
    HapticFeedback.selectionClick();
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
    // Live updates: refresh comments + counts when anyone reacts/comments
    // on this post, so a user reading comments never sees a stale list.
    ref.watch(postRealtimeProvider(widget.submissionId));
    final ink = QuestColors.text(context);
    final l = AppLocalizations.of(context)!;
    final keyboard = MediaQuery.of(context).viewInsets.bottom;
    final count = ref.watch(commentsProvider(widget.submissionId)).maybeWhen(
          data: (comments) =>
              comments.fold<int>(0, (sum, c) => sum + 1 + c.replies.length),
          orElse: () => 0,
        );

    return DraggableScrollableSheet(
      controller: _draggable,
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.98,
      snap: true,
      snapSizes: const [0.5, 0.7, 0.98],
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            // Plain cream sheet — no chunky ink border around the top.
            // Comments-as-modal lives on a flat surface so nothing competes
            // with the conversation itself.
            color: QuestColors.osBg,
            borderRadius: BorderRadius.vertical(
                top: Radius.circular(QuestSpacing.radiusMd)),
          ),
          child: Column(
            children: [
              // Drag handle — short pill, low contrast.
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 6),
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: ink.withAlpha(45),
                    borderRadius: BorderRadius.circular(QuestSpacing.radiusPip),
                  ),
                ),
              ),
              // Header — single centred title; the drag handle and the
              // barrier tap dismiss the sheet, so there is no close button.
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                child: Center(
                  child: Text(
                    count > 0 ? '${l.comments} · $count' : l.comments,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: QuestTypography.osHeadlineSmall.copyWith(
                      color: ink,
                      fontSize: 15,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
              ),
              // Hairline divider.
              Container(height: 0.5, color: ink.withAlpha(30)),
              // Comments list — scrollable. Tapping anywhere here dismisses
              // the keyboard so the user can read while scrolling.
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => FocusScope.of(context).unfocus(),
                  child: SingleChildScrollView(
                    controller: scrollController,
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    child: CommentsSection(
                      submissionId: widget.submissionId,
                      onReplyTap: _onReplyTap,
                    ),
                  ),
                ),
              ),
              // Input bar (incl. reply chip + @-mention suggestions panel).
              // A modal sheet is not a Scaffold, so the keyboard inset is
              // applied here rather than by resizeToAvoidBottomInset.
              Padding(
                padding: EdgeInsets.only(bottom: keyboard),
                child: CommentComposer(
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
              ),
            ],
          ),
        );
      },
    );
  }
}
