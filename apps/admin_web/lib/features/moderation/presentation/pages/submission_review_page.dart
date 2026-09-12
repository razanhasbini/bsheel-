import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:app_contracts/app_contracts.dart';
import 'package:app_models/app_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/backend/app_backend.dart';
import '../../../../core/router/admin_route_names.dart';
import '../../../../core/theme/bsheel_design.dart';
import '../../../../shared/widgets/bsheel_widgets.dart';
import '../../../agent_evidence/domain/evidence_wording.dart';
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
    if (widget.blockedReason != null) {
      _showBlocked();
      return;
    }

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
    if (widget.blockedReason != null) {
      _showBlocked();
      return;
    }

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

  /// Says why a decision did not happen.
  ///
  /// Both decision paths used to return silently when blocked. The button
  /// carries a small caption and is disabled, but the `A` / `R` keyboard
  /// shortcuts route here too — and a keypress that does nothing at all
  /// reads as the panel being broken, not as a rule being enforced. It is
  /// the difference between "I clicked approve and nothing happened" and
  /// knowing there is one more photo to look at.
  void _showBlocked() {
    final reason = widget.blockedReason;
    if (reason == null) return;
    _snack(context, '$reason — scroll through every photo and video first.');
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
      // The network's half of the verdict lives with the evidence, at full
      // width, not in the 346px decision rail: it carries a map and two
      // location columns, and a moderator reads it before deciding, not
      // beside the buttons.
      const SizedBox(height: 20),
      _NetworkEvidencePanel(submissionId: widget.submissionId),
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

    // coerceNullableDouble, not a cast: a moderator's queue must not white-
    // screen because a score arrived as '0.990' instead of 0.99. Nullable so
    // "never scored" stays distinguishable from a genuine 0%.
    final confidence = coerceNullableDouble(data['ai_confidence']);
    final relevance = coerceNullableDouble(data['ai_relevance']);
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
            confidence: coerceNullableDouble(item['confidence']) ?? 0,
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

/// What the network said about where the player was.
///
/// "Agent's read" above is the vision pass — what the photograph shows.
/// This is the other half of a location quest's verdict, and until now it
/// lived only on the AGENT EVIDENCE page: whether the carrier put the device
/// inside the place's radius (Location Verification), where it actually put
/// it (Location Retrieval), whether the device crossed into the geofence
/// while the quest was live, and what the agent concluded from all of it.
///
/// Fetched here rather than threaded through the detail row because it is a
/// different table with its own lifecycle: a submission can sit in the queue
/// for days before a run exists — everything submitted while automated
/// verification was paused has none — so the panel can also ask for one.
class _NetworkEvidencePanel extends StatefulWidget {
  const _NetworkEvidencePanel({required this.submissionId});

  final String submissionId;

  @override
  State<_NetworkEvidencePanel> createState() => _NetworkEvidencePanelState();
}

class _NetworkEvidencePanelState extends State<_NetworkEvidencePanel> {
  late Future<Map<String, dynamic>?> _future = _load();
  bool _queued = false;
  bool _queueing = false;
  Timer? _poll;

  Future<Map<String, dynamic>?> _load() =>
      AppBackend.repositories.admin.agentEvidenceForSubmission(
        widget.submissionId,
      );

  @override
  void didUpdateWidget(covariant _NetworkEvidencePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.submissionId != widget.submissionId) {
      _poll?.cancel();
      _queued = false;
      setState(() => _future = _load());
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _rerun() async {
    setState(() => _queueing = true);
    try {
      await AppBackend.repositories.admin.rerunAgentVerification(
        widget.submissionId,
      );
      if (!mounted) return;
      setState(() {
        _queued = true;
        _queueing = false;
      });
      // Three carrier calls and a model turn take a few seconds; re-read for
      // a minute rather than making the moderator press refresh.
      var attempts = 0;
      _poll?.cancel();
      _poll = Timer.periodic(const Duration(seconds: 5), (timer) {
        attempts += 1;
        if (!mounted || attempts > 12) {
          timer.cancel();
          return;
        }
        setState(() => _future = _load());
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _queueing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not queue the network check: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>?>(
      future: _future,
      builder: (context, snapshot) {
        final Widget body;
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          body = const LinearProgressIndicator(minHeight: 2);
        } else if (snapshot.hasError) {
          body = Row(
            children: [
              const Expanded(
                child: Text(
                  'Network evidence could not be loaded.',
                  style: BsheelType.bodySm,
                ),
              ),
              BsheelButton(
                label: 'RETRY',
                small: true,
                ghost: true,
                onPressed: () => setState(() => _future = _load()),
              ),
            ],
          );
        } else if (snapshot.data == null) {
          body = _empty();
        } else {
          body = _dossier(snapshot.data!);
        }
        return _Block(label: 'Network · where they were', child: body);
      },
    );
  }

  Widget _empty() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          _queued
              ? 'Network check queued — the worker is asking the carrier now. '
                  'This refreshes itself for a minute.'
              : 'No network check has run for this submission.',
          style: BsheelType.bodySm,
        ),
        const SizedBox(height: 6),
        Text(
          'CAMARA asks the player\'s carrier whether the device was inside the '
          'place\'s radius, where it actually was, and whether it crossed the '
          'geofence while the quest was live. It needs the account\'s '
          'carrier-verified number — a photograph alone cannot answer it.',
          style: BsheelType.bodyXs.copyWith(color: BsheelColors.inkMuted),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            BsheelButton(
              label: _queued ? 'RUN AGAIN' : 'RUN NETWORK CHECK',
              icon: Icons.cell_tower_rounded,
              small: true,
              loading: _queueing,
              onPressed: _queueing ? null : _rerun,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'If nothing appears after a minute, automated verification is '
                'paused: Settings → AI SUBMISSION VERIFICATION.',
                style: BsheelType.bodyXs.copyWith(color: BsheelColors.inkMuted),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _dossier(Map<String, dynamic> d) {
    final network = [
      for (final n in (d['network'] as List? ?? const []))
        if (n is Map) Map<String, dynamic>.from(n),
    ];
    Map<String, dynamic>? signal(String capability) {
      for (final n in network) {
        if ('${n['capability']}' == capability) return n;
      }
      return null;
    }

    Map<String, dynamic> detailOf(Map<String, dynamic>? n) =>
        n?['detail'] is Map
            ? Map<String, dynamic>.from(n!['detail'] as Map)
            : const {};

    final needsLocation = d['needsLocation'] == true;
    final placeName = d['placeName'] as String?;
    final radius = coerceNullableDouble(d['placeRadiusMeters']);
    final placeLatitude = coerceNullableDouble(d['placeLatitude']);
    final placeLongitude = coerceNullableDouble(d['placeLongitude']);
    final decision = (d['decision'] ?? '').toString();
    final confidence = coerceNullableDouble(d['confidence']);
    final reasons = [
      for (final r in (d['reasons'] as List? ?? const [])) '$r',
    ];
    final human = (d['humanReviewReason'] ?? '').toString().trim();
    final shadow = d['shadow'] == true;
    final ranAt = _when(d['ranAt']);

    // The carrier's fix for the device, when it gave one.
    final retrieval = signal('LOCATION_RETRIEVAL');
    final retrievalDetail = detailOf(retrieval);
    final coordinates = retrievalDetail['coordinates'] is Map
        ? Map<Object?, Object?>.from(retrievalDetail['coordinates'] as Map)
        : null;
    final deviceLatitude = coordinates == null
        ? null
        : coerceNullableDouble(coordinates['latitude']);
    final deviceLongitude = coordinates == null
        ? null
        : coerceNullableDouble(coordinates['longitude']);
    final accuracy = coordinates == null
        ? null
        : coerceNullableDouble(coordinates['accuracyMeters']) ??
            coerceNullableDouble(retrievalDetail['radiusMeters']);
    final distance = coordinates == null
        ? null
        : distanceFromDestination(
            coordinates: coordinates,
            placeLatitude: placeLatitude,
            placeLongitude: placeLongitude,
          );
    final verification = signal('LOCATION_VERIFICATION');
    final geofence = signal('GEOFENCING');
    final geofenceEvents = [
      for (final e in (detailOf(geofence)['events'] as List? ?? const []))
        if (e is Map) Map<String, dynamic>.from(e),
    ];

    // The one-line answer, from the network signals alone. A CONTRADICTED
    // signal is a measurement that the device was elsewhere and outranks a
    // SUPPORTED one from a weaker capability; nothing measured is UNKNOWN,
    // never "no".
    final outcomes = [for (final n in network) '${n['outcome']}'];
    final String there;
    final BsheelPillTone thereTone;
    final String thereExplained;
    final firstReason = network
        .map((n) => detailOf(n)['unavailableReason'])
        .whereType<String>()
        .cast<String?>()
        .firstWhere((r) => r != null && r.isNotEmpty, orElse: () => null);
    if (!needsLocation) {
      there = 'NOT A LOCATION QUEST';
      thereTone = BsheelPillTone.ghost;
      thereExplained =
          'This quest has no destination, so the network is not asked where '
          'the device was. The verdict rests on the media alone.';
    } else if (outcomes.contains('CONTRADICTED')) {
      there = 'NO';
      thereTone = BsheelPillTone.coral;
      thereExplained = distance != null
          ? 'The carrier put the device ${readableDistance(distance)} from '
              '${placeName ?? 'the place'}'
              '${radius == null ? '.' : ' — outside the ${radius.round()} m radius.'}'
          : 'The carrier answered that the device was not inside the '
              'place\'s radius while the quest was live.';
    } else if (outcomes.contains('SUPPORTED')) {
      there = 'YES';
      thereTone = BsheelPillTone.green;
      thereExplained = distance != null
          ? 'The carrier put the device ${readableDistance(distance)} from '
              '${placeName ?? 'the place'}'
              '${radius == null ? '.' : ' — inside the ${radius.round()} m radius.'}'
          : geofenceEvents.isNotEmpty
              ? 'The device crossed into the geofence while the quest was live.'
              : 'The carrier confirmed the device was inside the place\'s '
                  'radius.';
    } else {
      there = 'UNKNOWN';
      thereTone = BsheelPillTone.gold;
      thereExplained = firstReason != null
          ? 'The network could not be asked — '
              '${firstReason[0].toLowerCase()}${firstReason.substring(1)}.'
          : 'The network gave no usable answer for this attempt.';
    }

    final hasPlace = placeLatitude != null && placeLongitude != null;
    final hasDevice = deviceLatitude != null && deviceLongitude != null;

    Widget locationColumns() => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const BsheelLabel('Quest location'),
            const SizedBox(height: 6),
            BsheelKeyValues(
              entries: [
                BsheelKeyValue('Place', placeName ?? '—'),
                BsheelKeyValue(
                  'Coordinates',
                  hasPlace ? _coords(placeLatitude, placeLongitude) : '—',
                ),
                BsheelKeyValue(
                  'Accepted radius',
                  radius == null ? '—' : '${radius.round()} m around it',
                ),
              ],
            ),
            if (hasPlace)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => _openMap(placeLatitude, placeLongitude),
                  icon: const Icon(Icons.open_in_new_rounded, size: 14),
                  label: const Text('OPEN QUEST LOCATION IN MAPS'),
                ),
              ),
            const SizedBox(height: 10),
            const BsheelLabel('Device, according to the carrier'),
            const SizedBox(height: 6),
            BsheelKeyValues(
              entries: [
                BsheelKeyValue(
                  'Position',
                  hasDevice
                      ? _coords(deviceLatitude, deviceLongitude)
                      : 'NO FIX',
                  emphasis: hasDevice ? null : BsheelColors.inkMuted,
                ),
                BsheelKeyValue(
                  'Accuracy',
                  accuracy == null ? '—' : '± ${accuracy.round()} m',
                ),
                BsheelKeyValue(
                  'Distance to the place',
                  distance == null
                      ? '—'
                      : '${readableDistance(distance)}'
                          '${radius == null ? '' : distance <= radius ? ' · INSIDE' : ' · OUTSIDE'}',
                  emphasis: distance == null || radius == null
                      ? null
                      : distance <= radius
                          ? BsheelColors.successText
                          : BsheelColors.dangerText,
                ),
                BsheelKeyValue(
                  'Measured at',
                  _when(retrievalDetail['lastLocationTime']) ??
                      _when(retrieval?['observedAt']) ??
                      '—',
                ),
              ],
            ),
            if (hasDevice)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => _openMap(deviceLatitude, deviceLongitude),
                  icon: const Icon(Icons.open_in_new_rounded, size: 14),
                  label: const Text('OPEN DEVICE POSITION IN MAPS'),
                ),
              ),
          ],
        );

    return BsheelCard.flat(
      color: BsheelColors.card,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── The answer ───────────────────────────────────────────────
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 10,
            runSpacing: 6,
            children: [
              BsheelPill('DEVICE AT THE PLACE · $there', tone: thereTone),
              if (ranAt != null)
                Text(
                  'checked $ranAt',
                  style:
                      BsheelType.labelSm.copyWith(color: BsheelColors.inkMuted),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(thereExplained, style: BsheelType.bodyMd),

          // ── Map + the two locations ──────────────────────────────────
          if (needsLocation && hasPlace) ...[
            const SizedBox(height: 14),
            LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 640;
                final map = _MiniMap(
                  placeLatitude: placeLatitude,
                  placeLongitude: placeLongitude,
                  radiusMeters: radius ?? 250,
                  deviceLatitude: deviceLatitude,
                  deviceLongitude: deviceLongitude,
                  accuracyMeters: accuracy,
                  distanceLabel:
                      distance == null ? null : readableDistance(distance),
                  width: wide ? 320 : constraints.maxWidth,
                  height: wide ? 300 : 240,
                );
                if (wide) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      map,
                      const SizedBox(width: 16),
                      Expanded(child: locationColumns()),
                    ],
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    map,
                    const SizedBox(height: 12),
                    locationColumns(),
                  ],
                );
              },
            ),
          ],

          // ── What each network signal said ───────────────────────────
          if (needsLocation) ...[
            const SizedBox(height: 14),
            const BsheelLabel('What the network said'),
            const SizedBox(height: 6),
            if (network.isEmpty)
              Text(
                'No network signal was recorded for this run.',
                style: BsheelType.bodySm.copyWith(color: BsheelColors.inkMuted),
              ),
            for (final n in [verification, retrieval, geofence])
              if (n != null)
                _SignalCard(
                  title: _capabilityLabel('${n['capability']}'),
                  answer:
                      capabilityAnswer('${n['capability']}', '${n['outcome']}'),
                  tone: switch ('${n['outcome']}') {
                    'SUPPORTED' => BsheelPillTone.green,
                    'CONTRADICTED' => BsheelPillTone.coral,
                    _ => BsheelPillTone.ghost,
                  },
                  sentence: capabilityMeasurement(
                    capability: '${n['capability']}',
                    outcome: '${n['outcome']}',
                    detail: n['detail'],
                    placeName: placeName,
                    placeLatitude: placeLatitude,
                    placeLongitude: placeLongitude,
                  ),
                  reason: _unavailableReason(n['detail']),
                  facts: [
                    if ('${n['capability']}' == 'LOCATION_VERIFICATION') ...[
                      if (detailOf(n)['verificationResult'] != null)
                        'carrier answer: ${detailOf(n)['verificationResult']}',
                      if (coerceNullableDouble(detailOf(n)['matchRate']) !=
                          null)
                        'match rate: ${coerceNullableDouble(detailOf(n)['matchRate'])!.round()}%',
                    ],
                    if ('${n['capability']}' == 'GEOFENCING')
                      for (final e in geofenceEvents)
                        '${e['type']}${_when(e['occurredAt']) == null ? '' : ' at ${_when(e['occurredAt'])}'}',
                    if (_when(n['observedAt']) != null)
                      'observed ${_when(n['observedAt'])}',
                  ],
                ),
            for (final n in network)
              if (!['LOCATION_VERIFICATION', 'LOCATION_RETRIEVAL', 'GEOFENCING']
                  .contains('${n['capability']}'))
                _SignalCard(
                  title: _capabilityLabel('${n['capability']}'),
                  answer:
                      capabilityAnswer('${n['capability']}', '${n['outcome']}'),
                  tone: BsheelPillTone.ghost,
                  sentence: capabilityMeasurement(
                    capability: '${n['capability']}',
                    outcome: '${n['outcome']}',
                    detail: n['detail'],
                  ),
                  reason: _unavailableReason(n['detail']),
                  facts: const [],
                ),
          ],

          // ── The agent ────────────────────────────────────────────────
          const SizedBox(height: 14),
          const BsheelLabel('Agent decision'),
          const SizedBox(height: 6),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 10,
            runSpacing: 6,
            children: [
              BsheelPill(
                decision.isEmpty ? 'NO DECISION' : decision,
                tone: switch (decision) {
                  'REJECTED' => BsheelPillTone.coral,
                  'APPROVED' => BsheelPillTone.green,
                  'HUMAN_REVIEW' => BsheelPillTone.gold,
                  _ => BsheelPillTone.ghost,
                },
              ),
              if (confidence != null)
                Text(
                  '${(confidence * 100).round()}% confident',
                  style:
                      BsheelType.labelSm.copyWith(color: BsheelColors.inkSoft),
                ),
            ],
          ),
          if (reasons.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final r in reasons)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('• $r', style: BsheelType.bodySm),
              ),
          ],
          if (human.isNotEmpty) ...[
            const SizedBox(height: 8),
            BsheelCallout(human),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  shadow
                      ? 'Shadow mode — recorded, nothing applied. You decide.'
                      : 'Advisory. You decide.',
                  style:
                      BsheelType.bodyXs.copyWith(color: BsheelColors.inkMuted),
                ),
              ),
              BsheelButton(
                label: 'RE-RUN NETWORK CHECK',
                icon: Icons.cell_tower_rounded,
                small: true,
                ghost: true,
                loading: _queueing,
                onPressed: _queueing ? null : _rerun,
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _coords(double latitude, double longitude) =>
      '${latitude.toStringAsFixed(5)}, ${longitude.toStringAsFixed(5)}';

  /// A timestamp a person can read, in their own timezone. Null when the
  /// value is missing or not a date, so callers can leave the line out.
  static String? _when(Object? raw) {
    final parsed = DateTime.tryParse('$raw');
    if (raw == null || parsed == null) return null;
    final t = parsed.toLocal();
    const months = [
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
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.day} ${months[t.month - 1]} ${two(t.hour)}:${two(t.minute)}';
  }

  Future<void> _openMap(double latitude, double longitude) async {
    final uri = Uri.parse(
      'https://www.openstreetmap.org/?mlat=$latitude&mlon=$longitude'
      '#map=16/$latitude/$longitude',
    );
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
        mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the map.')),
      );
    }
  }

  /// Nokia's capability names, in words a moderator can act on. Mirrors the
  /// AGENT EVIDENCE page so the two screens never disagree about a label.
  String _capabilityLabel(String capability) => switch (capability) {
        'LOCATION_VERIFICATION' => 'WAS THE DEVICE THERE',
        'LOCATION_RETRIEVAL' => 'WHERE THE NETWORK PUT IT',
        'GEOFENCING' => 'DID IT ENTER DURING THE QUEST',
        'ADDITIONAL' => 'EXTRA NETWORK CONTEXT',
        _ => capability,
      };

  String _unavailableReason(Object? detail) {
    if (detail is! Map) return '';
    final reason = detail['unavailableReason'];
    if (reason is! String || reason.isEmpty) return '';
    return ' — ${reason[0].toLowerCase()}${reason.substring(1)}';
  }
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

/// One network signal, as a card: the question, the answer in the
/// capability's own words, the measurement sentence, and the small facts
/// behind it (carrier verdict, match rate, geofence events, timestamps).
class _SignalCard extends StatelessWidget {
  const _SignalCard({
    required this.title,
    required this.answer,
    required this.tone,
    required this.sentence,
    required this.reason,
    required this.facts,
  });

  final String title;
  final String answer;
  final BsheelPillTone tone;
  final String sentence;

  /// Already prefixed with " — " (or empty), from `_unavailableReason`.
  final String reason;
  final List<String> facts;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: BsheelColors.surface,
        borderRadius: BorderRadius.circular(BsheelRadii.card),
        border: const Border.fromBorderSide(BsheelBorders.inkSide),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 4,
            children: [
              Text(title, style: BsheelType.labelSm),
              BsheelPill(answer, tone: tone, small: true),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${sentence[0].toUpperCase()}${sentence.substring(1)}$reason.',
            style: BsheelType.bodySm,
          ),
          if (facts.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              facts.join(' · '),
              style: BsheelType.monoSm.copyWith(color: BsheelColors.inkMuted),
            ),
          ],
        ],
      ),
    );
  }
}

/// The quest's place and the carrier's fix for the device, on real map
/// tiles, at a zoom that shows both.
///
/// Drawn from OpenStreetMap tiles arranged by hand rather than through a map
/// widget: the admin console has no map dependency, and a moderator needs a
/// glance, not a pannable map. The place's accepted radius and the fix's
/// accuracy are drawn to scale, so "3 km away from a 400 m circle" is
/// something the eye can weigh before the numbers are read.
class _MiniMap extends StatelessWidget {
  const _MiniMap({
    required this.placeLatitude,
    required this.placeLongitude,
    required this.radiusMeters,
    required this.width,
    required this.height,
    this.deviceLatitude,
    this.deviceLongitude,
    this.accuracyMeters,
    this.distanceLabel,
  });

  final double placeLatitude;
  final double placeLongitude;
  final double radiusMeters;
  final double? deviceLatitude;
  final double? deviceLongitude;
  final double? accuracyMeters;
  final String? distanceLabel;
  final double width;
  final double height;

  static const double _tile = 256;

  static double _x(double longitude, int zoom) =>
      (longitude + 180) / 360 * (1 << zoom) * _tile;

  static double _y(double latitude, int zoom) {
    final r = latitude * math.pi / 180;
    return (1 - math.log(math.tan(r) + 1 / math.cos(r)) / math.pi) /
        2 *
        (1 << zoom) *
        _tile;
  }

  /// Ground metres per pixel at this latitude and zoom (Web Mercator).
  static double _metresPerPixel(double latitude, int zoom) =>
      156543.03392 * math.cos(latitude * math.pi / 180) / (1 << zoom);

  /// The tightest zoom at which both markers, the accepted radius and the
  /// accuracy ring fit inside the frame with some air around them.
  int _zoom() {
    final hasDevice = deviceLatitude != null && deviceLongitude != null;
    for (var zoom = 17; zoom >= 2; zoom--) {
      final mpp = _metresPerPixel(placeLatitude, zoom);
      final radiusPx = radiusMeters / mpp;
      if (!hasDevice) {
        if (radiusPx * 2 <= math.min(width, height) * 0.6) return zoom;
        continue;
      }
      final dx = (_x(deviceLongitude!, zoom) - _x(placeLongitude, zoom)).abs();
      final dy = (_y(deviceLatitude!, zoom) - _y(placeLatitude, zoom)).abs();
      final ring = (accuracyMeters ?? 0) / mpp;
      final pad = math.max(radiusPx, ring) + 28;
      if (dx + 2 * pad <= width && dy + 2 * pad <= height) return zoom;
    }
    return 2;
  }

  @override
  Widget build(BuildContext context) {
    final zoom = _zoom();
    final hasDevice = deviceLatitude != null && deviceLongitude != null;
    final centreLatitude =
        hasDevice ? (placeLatitude + deviceLatitude!) / 2 : placeLatitude;
    final centreLongitude =
        hasDevice ? (placeLongitude + deviceLongitude!) / 2 : placeLongitude;
    final cx = _x(centreLongitude, zoom), cy = _y(centreLatitude, zoom);
    final left = cx - width / 2, top = cy - height / 2;
    final tiles = 1 << zoom;
    final firstX = (left / _tile).floor(),
        lastX = ((left + width) / _tile).floor();
    final firstY = (top / _tile).floor(),
        lastY = ((top + height) / _tile).floor();
    final mpp = _metresPerPixel(placeLatitude, zoom);

    Offset at(double latitude, double longitude) =>
        Offset(_x(longitude, zoom) - left, _y(latitude, zoom) - top);
    final place = at(placeLatitude, placeLongitude);
    final device = hasDevice ? at(deviceLatitude!, deviceLongitude!) : null;

    return ClipRRect(
      borderRadius: BorderRadius.circular(BsheelRadii.card),
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: BsheelColors.surface,
          border: const Border.fromBorderSide(BsheelBorders.inkSide),
          borderRadius: BorderRadius.circular(BsheelRadii.card),
        ),
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            for (var tx = firstX; tx <= lastX; tx++)
              for (var ty = firstY; ty <= lastY; ty++)
                if (ty >= 0 && ty < tiles)
                  Positioned(
                    left: tx * _tile - left,
                    top: ty * _tile - top,
                    width: _tile,
                    height: _tile,
                    child: Image.network(
                      'https://tile.openstreetmap.org/$zoom/'
                      '${((tx % tiles) + tiles) % tiles}/$ty.png',
                      fit: BoxFit.fill,
                      gaplessPlayback: true,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    ),
                  ),
            Positioned.fill(
              child: CustomPaint(
                painter: _MiniMapPainter(
                  place: place,
                  radiusPx: radiusMeters / mpp,
                  device: device,
                  accuracyPx:
                      accuracyMeters == null ? 0 : accuracyMeters! / mpp,
                ),
              ),
            ),
            if (device != null && distanceLabel != null)
              Positioned(
                left: ((place.dx + device.dx) / 2 - 44).clamp(4, width - 92),
                top: ((place.dy + device.dy) / 2 - 24).clamp(4, height - 28),
                child: BsheelPill(distanceLabel!,
                    tone: BsheelPillTone.ink, small: true),
              ),
            Positioned(
              left: 8,
              bottom: 6,
              child: Row(
                children: [
                  _legendDot(BsheelColors.violet),
                  const SizedBox(width: 4),
                  Text('quest',
                      style: BsheelType.labelSm.copyWith(fontSize: 9)),
                  const SizedBox(width: 10),
                  _legendDot(BsheelColors.sky),
                  const SizedBox(width: 4),
                  Text(hasDevice ? 'device (carrier)' : 'device: no fix',
                      style: BsheelType.labelSm.copyWith(fontSize: 9)),
                ],
              ),
            ),
            Positioned(
              right: 6,
              bottom: 4,
              child: Text(
                '© OpenStreetMap',
                style: BsheelType.labelSm
                    .copyWith(fontSize: 8, color: BsheelColors.inkMuted),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _legendDot(Color color) => Container(
        width: 9,
        height: 9,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: BsheelColors.ink, width: 1.5),
        ),
      );
}

class _MiniMapPainter extends CustomPainter {
  const _MiniMapPainter({
    required this.place,
    required this.radiusPx,
    required this.device,
    required this.accuracyPx,
  });

  final Offset place;
  final double radiusPx;
  final Offset? device;
  final double accuracyPx;

  @override
  void paint(Canvas canvas, Size size) {
    // The accepted radius, to scale: where the player had to be.
    canvas.drawCircle(
      place,
      math.max(radiusPx, 6),
      Paint()..color = BsheelColors.violet.withAlpha(60),
    );
    canvas.drawCircle(
      place,
      math.max(radiusPx, 6),
      Paint()
        ..color = BsheelColors.violet
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    final d = device;
    if (d != null) {
      // Where the carrier put the device, with its accuracy ring, and the
      // gap between the two.
      if (accuracyPx > 4) {
        canvas.drawCircle(
            d, accuracyPx, Paint()..color = BsheelColors.sky.withAlpha(50));
        canvas.drawCircle(
          d,
          accuracyPx,
          Paint()
            ..color = BsheelColors.sky
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,
        );
      }
      canvas.drawLine(
        place,
        d,
        Paint()
          ..color = BsheelColors.ink
          ..strokeWidth = 2,
      );
      _pin(canvas, d, BsheelColors.sky);
    }
    _pin(canvas, place, BsheelColors.violet);
  }

  void _pin(Canvas canvas, Offset at, Color color) {
    canvas.drawCircle(at, 9, Paint()..color = BsheelColors.ink);
    canvas.drawCircle(at, 7, Paint()..color = color);
    canvas.drawCircle(at, 2.5, Paint()..color = BsheelColors.card);
  }

  @override
  bool shouldRepaint(_MiniMapPainter old) =>
      old.place != place ||
      old.radiusPx != radiusPx ||
      old.device != device ||
      old.accuracyPx != accuracyPx;
}
