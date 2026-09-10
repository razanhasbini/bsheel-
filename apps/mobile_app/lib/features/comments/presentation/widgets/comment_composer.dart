import 'package:flutter/material.dart';
import 'package:app_core/app_core.dart';
import 'package:app_models/app_models.dart';

import 'mention_picker.dart';

/// The comment composer, drawn identically at the bottom of
/// `10-comments.jpg` and `20-post-detail.jpg`.
///
/// Read off the render: a warm surface band with a 2px ink rule along its
/// top, a white `r13` field with a 2px ink border and **no** shadow, and a
/// violet `r13` send square with a 3px hard shadow and a white arrow. White
/// on violet is the one accent pairing that takes white.
///
/// Shared rather than open-coded per screen — it was two different bars
/// before (a soft `r18` hairline pill in the sheet, a chunky `r14` gold
/// send button on the detail page) for one control.
class CommentComposer extends StatefulWidget {
  const CommentComposer({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.submitting,
    required this.onSend,
    this.replyingTo,
    this.onCancelReply,
    this.mentionSuggestions = const [],
    this.mentionLoading = false,
    this.mentionQuery = '',
    this.onMentionTap,
    this.hint,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool submitting;
  final VoidCallback onSend;
  final CommentModel? replyingTo;
  final VoidCallback? onCancelReply;
  final List<MentionCandidate> mentionSuggestions;
  final bool mentionLoading;
  final String mentionQuery;
  final ValueChanged<MentionCandidate>? onMentionTap;
  final String? hint;

  @override
  State<CommentComposer> createState() => _CommentComposerState();
}

class _CommentComposerState extends State<CommentComposer> {
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
    if (mounted) setState(() {});
  }

  bool get _hasText => widget.controller.text.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    const ink = QuestColors.osTextPrimary;
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;
    final safeBottom = MediaQuery.of(context).viewPadding.bottom;
    final replyName = widget.replyingTo == null
        ? null
        : (widget.replyingTo!.displayName.isNotEmpty
            ? widget.replyingTo!.displayName
            : widget.replyingTo!.username);
    final canSend = _hasText && !widget.submitting;

    return Container(
      padding: EdgeInsets.fromLTRB(
        14,
        12,
        14,
        12 + (viewInsets > 0 ? 0 : safeBottom * 0.4),
      ),
      decoration: const BoxDecoration(
        color: QuestColors.osSurface,
        border: Border(top: BorderSide(color: ink, width: 2)),
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
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'REPLYING TO $replyName'.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: QuestTypography.osLabelSmall.copyWith(
                        color: QuestColors.osPrimary,
                        fontSize: 10,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Semantics(
                    button: true,
                    label: 'CANCEL REPLY',
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: widget.onCancelReply,
                      child: const SizedBox(
                        width: QuestSpacing.minTouchTarget,
                        height: 28,
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: Icon(
                            Icons.close_rounded,
                            size: 18,
                            color: QuestColors.osPrimary,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Container(
                  constraints: const BoxConstraints(
                    minHeight: QuestSpacing.minTouchTarget,
                  ),
                  decoration: BoxDecoration(
                    color: QuestColors.osCard,
                    borderRadius:
                        BorderRadius.circular(QuestSpacing.radiusPanel),
                    border: Border.all(color: ink, width: 2),
                  ),
                  child: TextField(
                    controller: widget.controller,
                    focusNode: widget.focusNode,
                    style: QuestTypography.osBodyMedium.copyWith(color: ink),
                    cursorColor: QuestColors.osPrimary,
                    maxLength: 500,
                    maxLines: 4,
                    minLines: 1,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => widget.onSend(),
                    decoration: InputDecoration(
                      hintText: replyName != null
                          ? 'Reply…'
                          : (widget.hint ?? 'Add a comment...'),
                      hintStyle: QuestTypography.osBodyMedium.copyWith(
                        color: QuestColors.osTextMuted,
                      ),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      isDense: true,
                      filled: false,
                      counterText: '',
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 13,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Semantics(
                button: true,
                label: 'SEND COMMENT',
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  // The render draws the send square violet whether or not
                  // there is anything to send, so an empty tap puts the
                  // caret in the field instead of doing nothing at all.
                  onTap: canSend
                      ? widget.onSend
                      : () => widget.focusNode.requestFocus(),
                  child: Container(
                    width: QuestSpacing.minTouchTarget,
                    height: QuestSpacing.minTouchTarget,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      color: QuestColors.osPrimary,
                      borderRadius: BorderRadius.all(
                          Radius.circular(QuestSpacing.radiusPanel)),
                      border: Border.fromBorderSide(
                        BorderSide(color: ink, width: 2),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: ink,
                          offset: Offset(3, 3),
                          blurRadius: 0,
                        ),
                      ],
                    ),
                    child: widget.submitting
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                QuestColors.onAccent(QuestColors.osPrimary),
                              ),
                            ),
                          )
                        : Icon(
                            Icons.arrow_upward_rounded,
                            size: 20,
                            // White on violet — the one accent pairing that
                            // takes white, from the helper not by hand.
                            color: QuestColors.onAccent(QuestColors.osPrimary),
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
