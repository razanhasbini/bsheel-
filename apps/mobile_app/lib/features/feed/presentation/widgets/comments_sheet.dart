import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app_core/app_core.dart';
import 'package:app_models/app_models.dart';

import '../../../../design/bs_widgets.dart';
import '../../../../core/services/analytics_service.dart';
import '../../../../core/utils/account_lock_guard.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../comments/application/mention_controller.dart';
import '../../../comments/presentation/widgets/comments_section.dart';
import '../../../comments/presentation/widgets/mention_picker.dart';
import '../providers/post_realtime_provider.dart';

/// Slides up an Instagram-style comments bottom sheet for [submissionId].
///
/// Drag the handle to grow the sheet from 50% up to 95% of the screen.
/// Tapping "REPLY" on a comment focuses the input with the reply target
/// shown as a chip above it.
Future<void> showCommentsSheet(
  BuildContext context, {
  required String submissionId,
}) {
  final animController = AnimationController(
    duration: const Duration(milliseconds: 210),
    reverseDuration: const Duration(milliseconds: 170),
    vsync: Navigator.of(context),
  );
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: QuestColors.pureBlack.withAlpha(120),
    useSafeArea: true,
    // Mount above the bottom-nav shell so the input bar isn't hidden
    // behind the floating nav pill.
    useRootNavigator: true,
    transitionAnimationController: animController,
    builder: (sheetCtx) => _CommentsSheet(submissionId: submissionId),
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

  // ── @-mention picker state ────────────────────────────────────────
  // Shared plumbing (debounce, queries, insert logic) lives in
  // MentionInputController; this widget only renders the picker.
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

  void _cancelReply() {
    setState(() => _replyingTo = null);
  }

  Future<void> _send() async {
    // Tap-while-submitting (e.g. keyboard "send" key fired again before
    // we finish): give an explicit nudge instead of swallowing silently
    // so the user knows their tap was registered, not lost.
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
      final repo = ref.read(commentsRepositoryProvider);
      await repo.addComment(widget.submissionId, body, parentId: parentId);
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
          SnackBar(content: Text('Could not post comment: $e')),
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
            // Comments-as-modal in Instagram lives on a flat surface so
            // nothing competes with the conversation itself.
            color: QuestColors.osBg,
            borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
          ),
          child: Column(
            children: [
              // Drag handle — Instagram-style short pill, low contrast.
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 6),
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: ink.withAlpha(45),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              // Header — single centered "Comments" title; no actions on
              // the right (drag handle + barrier-tap dismiss the sheet,
              // matching IG which doesn't render an explicit close button).
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                child: Center(
                  child: Text(
                    l.comments,
                    style: QuestTypography.headlineSmall.copyWith(
                      color: ink,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.1,
                    ),
                  ),
                ),
              ),
              // Hairline divider — soft 12% black, 0.5px on devices that
              // support sub-pixel borders so it reads exactly like IG.
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
              // Input bar (incl. reply chip + @-mention suggestions panel)
              _SheetInputBar(
                controller: _controller,
                focusNode: _focus,
                submitting: _submitting,
                bottomPad: keyboard,
                replyingTo: _replyingTo,
                onCancelReply: _cancelReply,
                onSend: _send,
                mentionSuggestions: _mention.suggestions,
                mentionLoading: _mention.loading,
                mentionQuery: _mention.query,
                onMentionTap: _mention.insertMention,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SheetInputBar extends StatefulWidget {
  const _SheetInputBar({
    required this.controller,
    required this.focusNode,
    required this.submitting,
    required this.bottomPad,
    required this.onSend,
    required this.replyingTo,
    required this.onCancelReply,
    required this.mentionSuggestions,
    required this.mentionLoading,
    required this.mentionQuery,
    required this.onMentionTap,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool submitting;
  final double bottomPad;
  final VoidCallback onSend;
  final CommentModel? replyingTo;
  final VoidCallback onCancelReply;
  final List<MentionCandidate> mentionSuggestions;
  final bool mentionLoading;
  final String mentionQuery;
  final ValueChanged<MentionCandidate> onMentionTap;

  @override
  State<_SheetInputBar> createState() => _SheetInputBarState();
}

class _SheetInputBarState extends State<_SheetInputBar> {
  // Single fixed set, matches the row Instagram surfaces above the comment
  // input when the keyboard isn't focused. Tap to insert at the caret.
  static const _quickEmojis = [
    '❤️',
    '🙌',
    '🔥',
    '👏🏻',
    '😢',
    '😍',
    '😮',
    '😂',
  ];

  bool get _hasText => widget.controller.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    super.dispose();
  }

  void _onTextChanged() {
    // Only rebuild for the empty→non-empty transition so we don't churn
    // for every keystroke.
    if (mounted) setState(() {});
  }

  void _insertEmoji(String emoji) {
    HapticFeedback.selectionClick();
    final ctrl = widget.controller;
    final sel = ctrl.selection;
    final text = ctrl.text;
    if (sel.start < 0 || sel.end < 0) {
      ctrl.text = '$text$emoji';
      ctrl.selection = TextSelection.collapsed(offset: ctrl.text.length);
      return;
    }
    final newText = text.replaceRange(sel.start, sel.end, emoji);
    ctrl.value = ctrl.value.copyWith(
      text: newText,
      selection: TextSelection.collapsed(offset: sel.start + emoji.length),
      composing: TextRange.empty,
    );
  }

  @override
  Widget build(BuildContext context) {
    final ink = QuestColors.text(context);
    final l = AppLocalizations.of(context)!;
    final replyName = widget.replyingTo == null
        ? null
        : (widget.replyingTo!.displayName.isNotEmpty
            ? widget.replyingTo!.displayName
            : widget.replyingTo!.username);
    final canPost = _hasText && !widget.submitting;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOut,
      padding: EdgeInsets.fromLTRB(
          12, 8, 12, (widget.bottomPad > 0 ? 12 : 10) + widget.bottomPad),
      decoration: BoxDecoration(
        color: QuestColors.bg(context),
        border: Border(top: BorderSide(color: ink.withAlpha(25), width: 0.5)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.mentionLoading || widget.mentionSuggestions.isNotEmpty)
            MentionSuggestionsPanel(
              suggestions: widget.mentionSuggestions,
              loading: widget.mentionLoading,
              query: widget.mentionQuery,
              onTap: widget.onMentionTap,
            ),
          if (replyName != null)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: ink.withAlpha(10),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(Icons.reply_rounded,
                      size: 14, color: ink.withAlpha(160)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Replying to $replyName',
                      style: QuestTypography.labelSmall.copyWith(
                        color: ink.withAlpha(170),
                        fontSize: 12,
                        letterSpacing: 0.1,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  GestureDetector(
                    onTap: widget.onCancelReply,
                    behavior: HitTestBehavior.opaque,
                    child: BsMinTouch(
                      child: Icon(Icons.close_rounded,
                          size: 16, color: ink.withAlpha(140)),
                    ),
                  ),
                ],
              ),
            ),
          // Quick-emoji row — only when the input is empty and there's no
          // reply-target / mention picker competing for space, like IG.
          if (!_hasText &&
              replyName == null &&
              widget.mentionSuggestions.isEmpty &&
              !widget.mentionLoading)
            Padding(
              padding: const EdgeInsets.only(bottom: 8, top: 2),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  for (final e in _quickEmojis)
                    GestureDetector(
                      onTap: () => _insertEmoji(e),
                      behavior: HitTestBehavior.opaque,
                      child: BsMinTouch(
                        minWidth: 34,
                        child: Text(e, style: const TextStyle(fontSize: 24)),
                      ),
                    ),
                ],
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    // Soft pill — hairline outline like IG's "Add a
                    // comment…" field, no chunky ink border.
                    color: QuestColors.cardBg(context),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: ink.withAlpha(35), width: 0.7),
                  ),
                  child: TextField(
                    controller: widget.controller,
                    focusNode: widget.focusNode,
                    style: QuestTypography.bodyMedium.copyWith(color: ink),
                    cursorColor: QuestColors.osPrimary,
                    maxLength: 500,
                    maxLines: 4,
                    minLines: 1,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => widget.onSend(),
                    decoration: InputDecoration(
                      hintText: replyName != null ? 'Reply…' : l.addComment,
                      hintStyle: QuestTypography.bodyMedium.copyWith(
                        color: QuestColors.textDim(context),
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      counterText: '',
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              // Text-only "Post" action — only visible when something is
              // there to send. Mirrors IG's blue "Post" affordance.
              AnimatedSize(
                duration: const Duration(milliseconds: 140),
                curve: Curves.easeOut,
                alignment: Alignment.centerLeft,
                child: !canPost && !widget.submitting
                    ? const SizedBox(width: 0, height: kMinTouchTarget)
                    : GestureDetector(
                        onTap: widget.submitting ? null : widget.onSend,
                        behavior: HitTestBehavior.opaque,
                        child: Container(
                          constraints: const BoxConstraints(
                              minWidth: kMinTouchTarget,
                              minHeight: kMinTouchTarget),
                          alignment: Alignment.center,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 8),
                          child: widget.submitting
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                        QuestColors.osPrimary),
                                  ),
                                )
                              : Text(
                                  'Post',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: QuestTypography.labelLarge.copyWith(
                                    color: QuestColors.osPrimary,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                    letterSpacing: 0.1,
                                  ),
                                ),
                        ),
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
