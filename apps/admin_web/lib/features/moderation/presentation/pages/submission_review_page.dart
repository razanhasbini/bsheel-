import 'dart:convert';

import 'package:app_contracts/app_contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/backend/app_backend.dart';
import '../../../../core/router/admin_route_names.dart';
import '../../../../core/theme/bsheel_design.dart';
import '../../../../shared/widgets/bsheel_widgets.dart';
import '../../util/caption_flags.dart';
import '../providers/moderation_controller.dart';
import '../providers/pending_submissions_provider.dart';
import '../widgets/inline_video.dart';

/// Full review context in one request: the submission, the author's
/// profile, the quest, and the retake flag. Media and avatar arrive signed.
///
/// Public because the queue screen renders the same review surface for
/// whichever row is selected rather than duplicating the fetch.
final submissionDetailProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>?, String>((ref, id) async {
  return AppBackend.repositories.moderation.reviewDetail(id);
});

/// Reasons worth pre-filling the note with, from the queue's own
/// enrichment. The heuristics stay where they are — this only turns them
/// into the sentences a user will read.
List<String> suggestedRejectionReasons(PendingSubmission submission) {
  return [
    if (submission.isDuplicate) 'Duplicate / re-uploaded',
    if (submission.captionFlags.contains(CaptionFlags.inappropriate))
      'Inappropriate content',
    if (submission.captionFlags.contains(CaptionFlags.spam))
      'Spam / off-topic caption',
  ];
}

/// `/moderation/review/:id` — the review surface on its own, for a
/// moderator who arrived from a notification or a link rather than from
/// the queue rail.
class SubmissionReviewPage extends ConsumerWidget {
  final String submissionId;
  const SubmissionReviewPage({super.key, required this.submissionId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(submissionDetailProvider(submissionId));

    // The queue is already fetched when a moderator arrives from it, so the
    // position counter and the author's decision history come free.
    final queue = ref.watch(pendingSubmissionsProvider).maybeWhen(
          data: (rows) => rows,
          orElse: () => const <PendingSubmission>[],
        );
    final index = queue.indexWhere((s) => s.id == submissionId);
    final queued = index >= 0 ? queue[index] : null;

    void back() => context.goNamed(AdminRouteNames.pendingSubmissions);

    return detailAsync.when(
      loading: () => const SubmissionReviewSkeleton(),
      error: (error, _) => Padding(
        padding: BsheelLayout.pagePadding,
        child: BsheelErrorState(
          title: 'The review never loaded',
          message: 'The submission did not come back, so nothing here is '
              'stale — and no decision has been recorded. $error',
          onRetry: () => ref.invalidate(submissionDetailProvider(submissionId)),
        ),
      ),
      data: (data) {
        if (data == null) {
          return Padding(
            padding: BsheelLayout.pagePadding,
            child: BsheelEmptyState(
              title: 'Not in the queue',
              message: 'This submission no longer exists — another moderator '
                  'may already have decided it.',
              actionLabel: 'Back to the queue',
              onAction: back,
            ),
          );
        }
        return SubmissionReviewSurface(
          submissionId: submissionId,
          data: data,
          position: index >= 0 ? index + 1 : null,
          queueLength: index >= 0 ? queue.length : null,
          approvedCount: queued?.userApprovedCount,
          rejectedCount: queued?.userRejectedCount,
          suggestedReasons:
              queued == null ? const [] : suggestedRejectionReasons(queued),
          approveSendsNote: true,
          onBack: back,
          onApprove: (note) => _approve(context, ref, note),
          onReject: (note) => _reject(context, ref, note),
        );
      },
    );
  }

  Future<bool> _approve(
    BuildContext context,
    WidgetRef ref,
    String note,
  ) async {
    try {
      // Atomic on the API: it re-checks the moderator's role, asserts the
      // submission is still pending under FOR UPDATE, awards XP once,
      // applies the review note and writes an audit record — one
      // transaction.
      final trimmedNote = note.trim();
      await AppBackend.repositories.moderation.approveSubmission(
        submissionId,
        '',
        note: trimmedNote.isEmpty ? null : trimmedNote,
      );

      ref.invalidate(pendingSubmissionsProvider);
      if (context.mounted) {
        _snack(context, 'Submission approved.');
        context.goNamed(AdminRouteNames.pendingSubmissions);
      }
      return true;
    } catch (error) {
      if (context.mounted) {
        _snack(context, mapModerationError(error, action: 'approve'));
      }
      return false;
    }
  }

  Future<bool> _reject(
    BuildContext context,
    WidgetRef ref,
    String note,
  ) async {
    final rejectionNote = note.trim();
    if (rejectionNote.isEmpty) {
      if (context.mounted) {
        _snack(context, 'Please provide at least one rejection reason.');
      }
      return false;
    }

    try {
      await AppBackend.repositories.moderation.rejectSubmission(
        submissionId,
        '',
        note: rejectionNote,
      );

      ref.invalidate(pendingSubmissionsProvider);
      if (context.mounted) {
        _snack(context, 'Submission rejected.');
        context.goNamed(AdminRouteNames.pendingSubmissions);
      }
      return true;
    } catch (error) {
      if (context.mounted) {
        _snack(context, mapModerationError(error, action: 'reject'));
      }
      return false;
    }
  }
}

void _snack(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      backgroundColor: BsheelColors.card,
      content: Text(message, style: BsheelType.bodySm),
    ),
  );
}

// ── The review surface ──────────────────────────────────────────────────

/// Queue rail → evidence → decision, left to right, so the moderator's eye
/// lands on the decision last.
///
/// Shared by `/moderation` (beside the queue rail) and
/// `/moderation/review/:id` (on its own). The host owns the decision itself
/// — the queue screen routes through [ModerationController], the standalone
/// route calls the repository — so this widget only carries the note, the
/// confirm step and the layout.
class SubmissionReviewSurface extends StatefulWidget {
  const SubmissionReviewSurface({
    super.key,
    required this.submissionId,
    required this.data,

    /// Media renderer, given the width the evidence column can spare. The
    /// queue screen passes its `MediaSection` so the view-every-asset gate
    /// keeps working; the standalone route lets this widget draw the media.
    this.mediaBuilder,
    this.position,
    this.queueLength,
    this.approvedCount,
    this.rejectedCount,
    this.reportsAgainst,
    this.suggestedReasons = const [],
    this.approveSendsNote = false,
    this.busy = false,

    /// Non-null while a decision is not allowed yet — the line is shown
    /// above the buttons and both actions are disabled.
    this.blockedReason,
    this.onApprove,
    this.onReject,
    this.onBack,
  });

  final String submissionId;
  final Map<String, dynamic> data;
  final Widget Function(BuildContext context, double maxWidth)? mediaBuilder;
  final int? position;
  final int? queueLength;
  final int? approvedCount;
  final int? rejectedCount;
  final int? reportsAgainst;
  final List<String> suggestedReasons;
  final bool approveSendsNote;
  final bool busy;
  final String? blockedReason;
  final Future<bool> Function(String note)? onApprove;
  final Future<bool> Function(String note)? onReject;
  final VoidCallback? onBack;

  @override
  State<SubmissionReviewSurface> createState() =>
      SubmissionReviewSurfaceState();
}

class SubmissionReviewSurfaceState extends State<SubmissionReviewSurface> {
  static const List<String> _reasons = [
    'Proof unclear',
    'Intent mismatch',
    'Unsafe',
    'Duplicate',
  ];

  final TextEditingController _note = TextEditingController();
  bool _isActioning = false;

  @override
  void initState() {
    super.initState();
    _prefillNote();
  }

  @override
  void didUpdateWidget(SubmissionReviewSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A different submission is a different decision: never carry a note
    // written about one submission over to the next one.
    if (oldWidget.submissionId != widget.submissionId) {
      _note.clear();
      _prefillNote();
    }
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  void _prefillNote() {
    if (widget.suggestedReasons.isEmpty) return;
    _note.text = widget.suggestedReasons.map((r) => '• $r').join('\n');
  }

  void _appendReason(String reason) {
    final bullet = '• $reason';
    final lines = _note.text
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    if (lines.contains(bullet)) return;
    lines.add(bullet);
    _note.text = lines.join('\n');
  }

  bool get _busy => widget.busy || _isActioning;

  bool get _appealed => widget.data['appealed'] == true;

  bool get _pending =>
      (widget.data['status'] ?? '').toString() == SubmissionStatus.pending;

  int get _questXp => (widget.data['quest_xp_reward'] as num?)?.toInt() ?? 0;

  /// Approve, with the confirm step. Public so the queue screen's `A`
  /// shortcut runs exactly the same flow as the button.
  Future<void> approve() async {
    final handler = widget.onApprove;
    if (handler == null || _busy || !_pending) return;
    if (widget.blockedReason != null) return;

    final note = _note.text.trim();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => BsheelDialog(
        title: 'Approve submission',
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$_questXp XP is awarded once and the author is notified. '
              'Approving cannot be undone from this screen.',
              style: BsheelType.bodySm.copyWith(color: BsheelColors.inkSoft),
            ),
            if (widget.approveSendsNote && note.isNotEmpty) ...[
              const SizedBox(height: 12),
              BsheelCard.flat(
                color: BsheelColors.surface,
                child: Text(note, style: BsheelType.bodySm),
              ),
              const SizedBox(height: 8),
              const BsheelLabel('Sent to the author'),
            ],
          ],
        ),
        actions: [
          BsheelButton.ghost(
            label: 'Cancel',
            small: true,
            onPressed: () => Navigator.pop(ctx, false),
          ),
          BsheelButton.positive(
            label: 'Approve',
            small: true,
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isActioning = true);
    final ok = await handler(note);
    if (!mounted) return;
    setState(() => _isActioning = false);
    if (ok) _note.clear();
  }

  /// Reject, with the confirm step and the re-rejection warning.
  Future<void> reject() async {
    final handler = widget.onReject;
    if (handler == null || _busy || !_pending) return;
    if (widget.blockedReason != null) return;

    final note = _note.text.trim();
    if (note.isEmpty) {
      _showNoteRequired();
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => BsheelDialog(
        title: _appealed ? 'Re-reject submission' : 'Reject submission',
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _appealed
                  ? 'This is a second review. A re-rejection is final — the '
                      'author cannot appeal again.'
                  : 'The author sees these reasons and may appeal once.',
              style: BsheelType.bodySm.copyWith(color: BsheelColors.inkSoft),
            ),
            const SizedBox(height: 12),
            BsheelCard.flat(
              color: BsheelColors.surface,
              child: Text(note, style: BsheelType.bodySm),
            ),
          ],
        ),
        actions: [
          BsheelButton.ghost(
            label: 'Cancel',
            small: true,
            onPressed: () => Navigator.pop(ctx, false),
          ),
          BsheelButton.coral(
            label: _appealed ? 'Re-reject' : 'Reject',
            small: true,
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isActioning = true);
    final ok = await handler(note);
    if (!mounted) return;
    setState(() => _isActioning = false);
    if (ok) _note.clear();
  }

  void _showNoteRequired() {
    _snack(
      context,
      'Add at least one reason — the author is shown them as bullet points.',
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Below this the evidence and the decision rail cannot both hold
        // their minimums, so they stack in one scroll instead.
        final stacked = constraints.maxWidth < 900;

        if (stacked) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(22, 20, 22, 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: _evidence(),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.fromLTRB(22, 18, 22, 22),
                        decoration: const BoxDecoration(
                          color: BsheelColors.surface,
                          border: Border(top: BsheelBorders.inkSide),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            ..._reviewerContext(),
                            const SizedBox(height: 16),
                            _decisionBlock(),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Evidence — flexes, scrolls, 2px ink rule against the rail.
                  Expanded(
                    child: DecoratedBox(
                      decoration: const BoxDecoration(
                        border: Border(right: BsheelBorders.inkSide),
                      ),
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(22, 20, 22, 24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: _evidence(),
                        ),
                      ),
                    ),
                  ),
                  // Decision rail — the context sits beside the buttons, and
                  // the buttons never leave the fold.
                  Container(
                    width: 346,
                    color: BsheelColors.surface,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.fromLTRB(22, 20, 22, 14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: _reviewerContext(),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(22, 0, 22, 20),
                          child: _decisionBlock(),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  // ── Header ────────────────────────────────────────────────────────────

  Widget _header() {
    final data = widget.data;
    final questTitle = (data['quest_title'] ?? 'Unknown quest').toString();
    final username = (data['username'] ?? '').toString();
    final level = (data['level'] as num?)?.toInt() ?? 1;
    final category = (data['quest_category'] ?? '').toString();
    final status = (data['status'] ?? '').toString();
    final collabMode = data['collab_mode']?.toString();

    final meta = <String>[
      _shortId(widget.submissionId),
      if (username.isNotEmpty) username,
      'LVL $level',
      if (_appealed) '2ND REVIEW (APPEALED)',
    ].join(' · ');

    return Container(
      padding: const EdgeInsets.fromLTRB(22, 15, 22, 15),
      decoration: const BoxDecoration(
        color: BsheelColors.surface,
        border: Border(bottom: BsheelBorders.inkSide),
      ),
      child: Row(
        children: [
          if (widget.onBack != null) ...[
            BsheelIconButton(
              icon: Icons.arrow_back_rounded,
              size: 40,
              tooltip: 'Back to the queue',
              onTap: widget.onBack,
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  questTitle,
                  style: BsheelType.displaySm,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Text(
                  meta,
                  style: BsheelType.labelMd,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Wrap(
              spacing: 8,
              runSpacing: 6,
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (data['is_retake'] == true)
                  const BsheelPill('retake', tone: BsheelPillTone.sky),
                if (collabMode != null)
                  BsheelPill(
                    collabMode == CollabMode.versus ? 'versus' : 'collab',
                  ),
                if (!_pending && status.isNotEmpty)
                  BsheelPill.status(status, small: false),
                if (category.isNotEmpty) BsheelTag.category(category),
                if (widget.position != null && widget.queueLength != null)
                  Text(
                    '${widget.position} / ${widget.queueLength}',
                    style: BsheelType.monoSm,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Evidence column ───────────────────────────────────────────────────

  List<Widget> _evidence() {
    final data = widget.data;
    final caption = (data['caption'] as String?)?.trim();
    final appealNote = (data['appeal_note'] as String?)?.trim();
    final questDesc = (data['quest_description'] ?? '').toString().trim();
    final difficulty = (data['quest_difficulty'] ?? '').toString();
    final submittedAt = DateTime.tryParse(
      data['submitted_at']?.toString() ?? '',
    );
    final firstDecision = _firstDecision();

    return [
      LayoutBuilder(
        builder: (context, constraints) =>
            widget.mediaBuilder?.call(context, constraints.maxWidth) ??
            _defaultMedia(),
      ),
      if (caption != null && caption.isNotEmpty) ...[
        const SizedBox(height: 16),
        _Block(
          label: 'Caption',
          child: Text(caption, style: BsheelType.bodyMd),
        ),
      ],
      if (_appealed) ...[
        const SizedBox(height: 16),
        _Block(
          label: 'Appeal text',
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: BsheelColors.accent,
              borderRadius: BorderRadius.circular(BsheelRadii.md),
              border: const Border.fromBorderSide(BsheelBorders.inkSide),
            ),
            child: Text(
              appealNote == null || appealNote.isEmpty
                  ? 'The author appealed without writing anything.'
                  : '"$appealNote"',
              style: BsheelType.bodyMd.copyWith(
                color: BsheelColors.onAccent(BsheelColors.accent),
              ),
            ),
          ),
        ),
      ],
      if (firstDecision != null) ...[
        const SizedBox(height: 16),
        _Block(
          label: 'First decision',
          child: Text(
            firstDecision,
            style: BsheelType.bodySm.copyWith(color: BsheelColors.inkSoft),
          ),
        ),
      ],
      if (questDesc.isNotEmpty) ...[
        const SizedBox(height: 16),
        _Block(
          label: 'Quest brief',
          child: Text(
            questDesc,
            style: BsheelType.bodySm.copyWith(color: BsheelColors.inkSoft),
          ),
        ),
      ],
      const SizedBox(height: 16),
      Text(
        [
          if (submittedAt != null) 'SUBMITTED ${_stamp(submittedAt)}',
          if (submittedAt != null)
            'WAITING ${bsheelWaiting(submittedAt.toIso8601String())}',
          if (difficulty.isNotEmpty) difficulty,
          '$_questXp XP',
        ].join(' · ').toUpperCase(),
        style: BsheelType.labelSm,
      ),
    ];
  }

  /// Media for the standalone route. The queue screen overrides this with
  /// its own `MediaSection`, which carries the view-every-asset gate.
  Widget _defaultMedia() {
    final urls = _mediaUrls((widget.data['media_url'] ?? '').toString());
    final mediaType = (widget.data['media_type'] ?? MediaType.image).toString();

    if (urls.isEmpty) {
      return const BsheelMediaPlaceholder(
        label: 'No proof media',
        height: 240,
        depth: 5,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < urls.length; i++) ...[
          if (i != 0) const SizedBox(height: 12),
          if (_isVideoUrl(urls[i]) ||
              (mediaType == MediaType.video && urls.length == 1))
            InlineVideo(url: urls[i])
          else
            _ProofImage(url: urls[i]),
        ],
      ],
    );
  }

  /// The first rejection, stated inline so nobody has to leave the page.
  ///
  /// Appealing NULLs `reviewed_by` / `review_note` / `reviewed_at` on the
  /// submission (see `submissions.repository.ts#appeal`), so on a second
  /// review the reasons are genuinely no longer in this payload — say that
  /// rather than draw an empty block.
  String? _firstDecision() {
    final note = (widget.data['review_note'] as String?)?.trim();
    final at = DateTime.tryParse(widget.data['reviewed_at']?.toString() ?? '');
    final by = (widget.data['reviewed_by'] ?? '').toString();

    final reasons = note == null || note.isEmpty
        ? null
        : note
            .split('\n')
            .map((line) => line.replaceFirst('•', '').trim())
            .where((line) => line.isNotEmpty)
            .join(', ');

    if (at != null || reasons != null) {
      final line = StringBuffer('Rejected');
      if (at != null) line.write(' ${_stamp(at)}');
      if (by.isNotEmpty) line.write(' by moderator ${_shortId(by)}');
      if (reasons != null) line.write(' — $reasons');
      line.write('.');
      return line.toString();
    }

    if (_appealed) {
      return 'Rejected once before this appeal. The reasons the author was '
          'given are cleared from the submission when they appeal, so their '
          'appeal text above is the only record left on it.';
    }
    return null;
  }

  // ── Decision rail ─────────────────────────────────────────────────────

  List<Widget> _reviewerContext() {
    final approved = widget.approvedCount;
    final rejected = widget.rejectedCount;
    final decided = (approved ?? 0) + (rejected ?? 0);
    final rate = approved == null || decided == 0
        ? '—'
        : '${(approved * 100 / decided).round()}%';

    return [
      _Block(
        label: 'Reviewer context',
        child: BsheelKeyValues(
          entries: [
            BsheelKeyValue('Approval rate', rate),
            BsheelKeyValue('Prior rejections', rejected?.toString() ?? '—'),
            BsheelKeyValue(
              'Reports against',
              widget.reportsAgainst?.toString() ?? '—',
            ),
            BsheelKeyValue(
              'Appeal',
              _appealed ? 'SPENT' : 'UNUSED',
              emphasis: _appealed ? BsheelColors.dangerText : null,
            ),
          ],
        ),
      ),
      ..._agentRead(),
      const SizedBox(height: 16),
      _Block(
        label: 'Reason (optional)',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            BsheelFilterChips(
              filters: [
                for (final reason in _reasons) BsheelFilter(reason, reason),
              ],
              // Nothing latches: a chip appends its line to the note, and
              // the note is the record.
              selected: '',
              onChanged: _appendReason,
            ),
            const SizedBox(height: 8),
            BsheelField(
              controller: _note,
              hint: 'Why is this being rejected?',
              maxLines: 4,
              enabled: _pending && widget.onReject != null,
            ),
          ],
        ),
      ),
    ];
  }

  /// What the verification agent concluded, if it has finished (#47).
  ///
  /// Advisory, and the rail says so: a moderator decides. It is here because
  /// the agent runs in shadow mode by default, and shadow mode is only worth
  /// anything if a person can see what the agent would have done while they
  /// decide independently. Without this the verdict existed only in SQL.
  ///
  /// Nothing is drawn until there is a verdict. An empty "agent" panel on
  /// every submission would train reviewers to ignore the region.
  List<Widget> _agentRead() {
    final data = widget.data;
    final verdict = (data['ai_verdict'] ?? '').toString();
    if (verdict.isEmpty) return const [];

    final confidence = (data['ai_confidence'] as num?)?.toDouble();
    final relevance = (data['ai_relevance'] as num?)?.toDouble();
    final rationale = (data['ai_rationale'] ?? '').toString().trim();
    final escalation = (data['ai_escalation_reason'] ?? '').toString().trim();
    final observations = _observations(data['ai_content_evidence']);

    return [
      const SizedBox(height: 16),
      _Block(
        label: "Agent's read",
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            BsheelKeyValues(
              entries: [
                BsheelKeyValue(
                  'Verdict',
                  switch (verdict) {
                    'pass' => 'CONSISTENT',
                    'fail' => 'CONTRADICTED',
                    _ => 'COULD NOT TELL',
                  },
                  emphasis: verdict == 'fail' ? BsheelColors.dangerText : null,
                ),
                // Labelled as two different questions on purpose. Confidence
                // is how sure the agent is of its verdict; relevance is how
                // much the media has to do with the quest. A reader who
                // conflates them will read a confident "this is a cat, not a
                // sunrise" as a confident approval.
                BsheelKeyValue('Verdict confidence', _percent(confidence)),
                BsheelKeyValue(
                  'Media relevance',
                  // "Not assessed" is not zero, and the difference matters:
                  // no photograph can show "spend an hour with no phone", so
                  // for those quests the agent deliberately does not score
                  // relevance and a low number would be a lie about the
                  // player rather than a fact about the media.
                  relevance == null ? 'NOT ASSESSED' : _percent(relevance),
                ),
              ],
            ),
            if (rationale.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(rationale, style: BsheelType.bodySm),
            ],
            if (observations.isNotEmpty) ...[
              const SizedBox(height: 10),
              const BsheelLabel('What it looked for'),
              const SizedBox(height: 6),
              for (final observation in observations) ...[
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      BsheelPill(
                        observation.present ? 'SEEN' : 'ABSENT',
                        tone: observation.present
                            ? BsheelPillTone.green
                            : BsheelPillTone.ghost,
                        small: true,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          observation.label,
                          style: BsheelType.bodySm,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        _percent(observation.confidence),
                        style: BsheelType.monoSm,
                      ),
                    ],
                  ),
                ),
              ],
            ],
            if (escalation.isNotEmpty) ...[
              const SizedBox(height: 8),
              BsheelCallout(escalation),
            ],
            const SizedBox(height: 8),
            Text(
              'Advisory. You decide.',
              style: BsheelType.bodyXs.copyWith(color: BsheelColors.inkMuted),
            ),
          ],
        ),
      ),
    ];
  }

  /// Parses the stored observation list, tolerating anything malformed.
  ///
  /// The column is jsonb written by the analyzer, so a row from an older
  /// build or a hand-run fixture must render as "no observations" rather
  /// than throw inside a moderator's queue.
  List<_Observation> _observations(Object? raw) {
    if (raw is! Map) return const [];
    final list = raw['observations'];
    if (list is! List) return const [];
    return [
      for (final item in list)
        if (item is Map && (item['label'] as String?)?.isNotEmpty == true)
          _Observation(
            label: item['label'].toString(),
            present: item['present'] == true,
            confidence: (item['confidence'] as num?)?.toDouble() ?? 0,
          ),
    ];
  }

  static String _percent(double? value) =>
      value == null ? '—' : '${(value * 100).round()}%';

  Widget _decisionBlock() {
    if (!_pending) {
      final status = (widget.data['status'] ?? '').toString();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BsheelCard.flat(
            color: BsheelColors.card,
            child: Text(
              'This submission has already been $status.',
              style: BsheelType.bodySm.copyWith(color: BsheelColors.inkSoft),
            ),
          ),
          if (widget.onBack != null) ...[
            const SizedBox(height: 9),
            BsheelButton.ghost(
              label: 'Back to the queue',
              expand: true,
              onPressed: widget.onBack,
            ),
          ],
        ],
      );
    }

    final blocked = widget.blockedReason;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (blocked != null) ...[
          Text(
            blocked.toUpperCase(),
            textAlign: TextAlign.center,
            style: BsheelType.labelSm.copyWith(color: BsheelColors.accentText),
          ),
          const SizedBox(height: 9),
        ],
        BsheelButton.positive(
          label: 'Approve · +$_questXp XP',
          expand: true,
          loading: _busy,
          onPressed: widget.onApprove == null || blocked != null || _busy
              ? null
              : approve,
        ),
        const SizedBox(height: 9),
        BsheelButton.coral(
          label: 'Reject',
          expand: true,
          onPressed: widget.onReject == null || blocked != null || _busy
              ? null
              : reject,
        ),
        if (_appealed) ...[
          const SizedBox(height: 9),
          Text(
            'RE-REJECTION IS FINAL — NO FURTHER APPEALS',
            textAlign: TextAlign.center,
            style: BsheelType.labelSm.copyWith(color: BsheelColors.dangerText),
          ),
        ],
      ],
    );
  }
}

// ── Pieces ──────────────────────────────────────────────────────────────

/// Mono label above a block of evidence or a panel.
/// One thing the agent says it looked for, and whether it found it.
class _Observation {
  const _Observation({
    required this.label,
    required this.present,
    required this.confidence,
  });

  final String label;
  final bool present;
  final double confidence;
}

class _Block extends StatelessWidget {
  const _Block({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        BsheelLabel(label),
        const SizedBox(height: 6),
        child,
      ],
    );
  }
}

/// One proof photo, framed. The signed URL is used verbatim.
class _ProofImage extends StatelessWidget {
  const _ProofImage({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 220, maxHeight: 480),
      decoration: BoxDecoration(
        color: BsheelColors.surface,
        borderRadius: BorderRadius.circular(BsheelRadii.lg),
        border: const Border.fromBorderSide(BsheelBorders.inkSide),
        boxShadow: BsheelShadows.lg,
      ),
      clipBehavior: Clip.antiAlias,
      child: Image.network(
        url,
        fit: BoxFit.contain,
        loadingBuilder: (_, child, progress) => progress == null
            ? child
            : const BsheelSkeleton(height: 220, radius: BsheelRadii.lg),
        errorBuilder: (_, __, ___) => const BsheelMediaPlaceholder(
          label: 'Proof unavailable',
          height: 220,
        ),
      ),
    );
  }
}

/// Loading state shaped like the surface itself, so nothing jumps when the
/// review arrives. No spinner.
class SubmissionReviewSkeleton extends StatelessWidget {
  const SubmissionReviewSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(22, 15, 22, 15),
          decoration: const BoxDecoration(
            color: BsheelColors.surface,
            border: Border(bottom: BsheelBorders.inkSide),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              BsheelSkeleton(height: 22, widthFactor: 0.6),
              SizedBox(height: 8),
              BsheelSkeleton(height: 12, widthFactor: 0.3),
            ],
          ),
        ),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Expanded(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border(right: BsheelBorders.inkSide),
                  ),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(22, 20, 22, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        BsheelSkeleton(height: 240, radius: BsheelRadii.lg),
                        SizedBox(height: 16),
                        BsheelSkeleton.line(),
                        SizedBox(height: 9),
                        BsheelSkeleton(height: 40),
                      ],
                    ),
                  ),
                ),
              ),
              Container(
                width: 346,
                color: BsheelColors.surface,
                padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    BsheelSkeleton.line(),
                    SizedBox(height: 9),
                    BsheelSkeleton(height: 150, radius: BsheelRadii.card),
                    Spacer(),
                    BsheelSkeleton(height: 50),
                    SizedBox(height: 9),
                    BsheelSkeleton(height: 50),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Helpers ─────────────────────────────────────────────────────────────

const List<String> _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// `12 Mar 18:04` — the stamp the design draws.
String _stamp(DateTime when) {
  final local = when.toLocal();
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '${local.day} ${_months[local.month - 1]} $hour:$minute';
}

/// First six characters of a uuid, which is what a moderator reads out.
String _shortId(String id) {
  final clean = id.replaceAll('-', '');
  if (clean.isEmpty) return '—';
  return clean.substring(0, clean.length < 6 ? clean.length : 6).toUpperCase();
}

/// `media_url` is either a bare URL or a JSON array of them.
List<String> _mediaUrls(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return const [];
  if (trimmed.startsWith('[')) {
    try {
      return (jsonDecode(trimmed) as List)
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList();
    } catch (_) {
      // Fall through to bare-string handling.
    }
  }
  return [trimmed];
}

bool _isVideoUrl(String url) {
  final lower = url.toLowerCase();
  return lower.endsWith('.mp4') ||
      lower.endsWith('.mov') ||
      lower.endsWith('.webm') ||
      lower.endsWith('.m4v');
}
