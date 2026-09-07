import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/admin_route_names.dart';
import '../../../../core/theme/bsheel_design.dart';
import '../../../../shared/widgets/bsheel_widgets.dart';
import '../../util/caption_flags.dart';
import '../providers/moderation_controller.dart';
import '../providers/pending_submissions_provider.dart';
import '../widgets/media_section.dart';

// Screen-specific colours — not theme tokens.
const Color _mediaPanelBorder = Color(0xFF2A2A2A);
const Color _mediaPanelDeep = Color(0xFF111111);
const Color _mediaPanelSoft = Color(0xFFC9C9C9); // light text on dark panels

class PendingSubmissionsPage extends ConsumerStatefulWidget {
  const PendingSubmissionsPage({super.key});

  @override
  ConsumerState<PendingSubmissionsPage> createState() =>
      _PendingSubmissionsPageState();
}

class _PendingSubmissionsPageState
    extends ConsumerState<PendingSubmissionsPage> {
  // Which card is keyboard-active. Bound by [0, list.length - 1] each build.
  int _selectedIndex = 0;

  // Per-submission set of media indices that have been viewed. A submission
  // unlocks once `viewed.length >= submission.mediaUrls.length`.
  final Map<String, Set<int>> _viewed = <String, Set<int>>{};

  final ScrollController _scrollController = ScrollController();
  final Map<String, GlobalKey> _itemKeys = <String, GlobalKey>{};

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  bool _allMediaViewed(PendingSubmission s) {
    final required = s.mediaUrls.length;
    if (required == 0) return true; // no media → nothing to gate on
    final seen = _viewed[s.id]?.length ?? 0;
    return seen >= required;
  }

  void _markViewed(String submissionId, int index) {
    final set = _viewed.putIfAbsent(submissionId, () => <int>{});
    if (set.add(index)) {
      // Defer the rebuild — frameBuilder fires during paint and calling
      // setState directly would assert. addPostFrameCallback handles that;
      // the callback chain in MediaSection already wraps in postFrame so
      // this setState is safe to invoke synchronously here.
      if (mounted) setState(() {});
    }
  }

  void _moveSelection(int delta, int listLength) {
    if (listLength == 0) return;
    final next = (_selectedIndex + delta).clamp(0, listLength - 1);
    if (next == _selectedIndex) return;
    setState(() => _selectedIndex = next);
    _scrollSelectedIntoView();
  }

  /// Mass-approve with the same safety rails as single approvals:
  /// only submissions whose media has been fully viewed are eligible
  /// (the rest are skipped and reported), the admin confirms the count
  /// first, and one failure doesn't silently abort the rest — failures
  /// are collected and summarised in a SnackBar.
  Future<void> _approveAll(List<PendingSubmission> list) async {
    final eligible = list.where(_allMediaViewed).toList();
    final skipped = list.length - eligible.length;

    if (eligible.isEmpty) {
      _showSummarySnack(
        'Nothing to approve — view every photo/video on a submission first.',
      );
      return;
    }

    final confirmed = await _showApproveAllDialog(eligible.length, skipped);
    if (confirmed != true || !mounted) return;

    var approved = 0;
    var failed = 0;
    final controller = ref.read(moderationControllerProvider.notifier);
    for (final sub in eligible) {
      final ok = await controller.approve(sub);
      if (ok) {
        approved++;
      } else {
        failed++;
      }
    }

    if (!mounted) return;
    final parts = <String>['Approved $approved'];
    if (failed > 0) parts.add('$failed failed');
    if (skipped > 0) parts.add('$skipped skipped (media not viewed)');
    _showSummarySnack('${parts.join(' · ')}.');
  }

  Future<bool?> _showApproveAllDialog(int eligibleCount, int skippedCount) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: BsheelColors.paper,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(BsheelRadii.xl),
          side: const BorderSide(
              color: BsheelColors.line, width: BsheelBorders.thin,),
        ),
        child: Padding(
          padding: const EdgeInsets.all(QuestSpacing.lg),
          child: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.done_all_rounded,
                      color: BsheelColors.success,
                      size: 24,
                    ),
                    const SizedBox(width: QuestSpacing.sm),
                    Text(
                      'APPROVE ALL',
                      style: BsheelType.displaySm
                          .copyWith(color: BsheelColors.ink),
                    ),
                  ],
                ),
                const SizedBox(height: QuestSpacing.md),
                Text(
                  'Approve $eligibleCount '
                  '${eligibleCount == 1 ? 'submission' : 'submissions'}? '
                  'The media-viewed gate applies — only submissions whose '
                  'media you have fully viewed are included.'
                  '${skippedCount > 0 ? '\n\n$skippedCount will be skipped '
                      '(media not fully viewed).' : ''}',
                  style: BsheelType.bodySm
                      .copyWith(color: BsheelColors.inkSoft, height: 1.4),
                ),
                const SizedBox(height: QuestSpacing.lg),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: Text(
                        'CANCEL',
                        style: BsheelType.labelSm
                            .copyWith(color: BsheelColors.inkMuted),
                      ),
                    ),
                    const SizedBox(width: QuestSpacing.sm),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: BsheelColors.success,
                        foregroundColor: BsheelColors.pureWhite,
                        shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(BsheelRadii.full),
                        ),
                      ),
                      child: Text(
                        'APPROVE $eligibleCount',
                        style: BsheelType.labelSm
                            .copyWith(color: BsheelColors.pureWhite),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showSummarySnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: BsheelColors.paper,
        content: Text(
          msg,
          style: BsheelType.bodySm.copyWith(color: BsheelColors.ink),
        ),
      ),
    );
  }

  void _scrollSelectedIntoView() {
    // Run after layout so the GlobalKey has a context.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final entries = _itemKeys.entries.toList();
      if (_selectedIndex >= entries.length) return;
      final ctx = entries[_selectedIndex].value.currentContext;
      if (ctx == null) return;
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 180),
        alignment: 0.1,
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    // Realtime: new submissions appear in the queue without manual
    // refresh; status changes (approve/reject by another mod) drop
    // them out. autoDispose tears the channel down on navigation away.
    ref.watch(pendingSubmissionsRealtimeProvider);

    final submissionsAsync = ref.watch(pendingSubmissionsProvider);
    final moderationState = ref.watch(moderationControllerProvider);

    final list = submissionsAsync.maybeWhen(
      data: (subs) => subs,
      orElse: () => const <PendingSubmission>[],
    );

    // Clamp selection if the list shrank (e.g. after approve).
    if (_selectedIndex >= list.length) {
      _selectedIndex = list.isEmpty ? 0 : list.length - 1;
    }

    final selected = list.isNotEmpty ? list[_selectedIndex] : null;
    final busy = moderationState.isLoading;

    Future<void> approveSelected() async {
      if (busy || selected == null) return;
      if (!_allMediaViewed(selected)) return;
      await ref.read(moderationControllerProvider.notifier).approve(selected);
    }

    Future<void> denySelected() async {
      if (busy || selected == null) return;
      if (!_allMediaViewed(selected)) return;
      final note = await _showDenyDialog(context, selected);
      if (note == null || note.isEmpty) return;
      await ref.read(moderationControllerProvider.notifier).deny(selected, note);
    }

    void openSelected() {
      if (selected == null) return;
      context.goNamed(
        AdminRouteNames.submissionReview,
        pathParameters: {'id': selected.id},
      );
    }

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.keyA): approveSelected,
        const SingleActivator(LogicalKeyboardKey.keyD): denySelected,
        const SingleActivator(LogicalKeyboardKey.enter): openSelected,
        const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
            _moveSelection(1, list.length),
        const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
            _moveSelection(-1, list.length),
        const SingleActivator(LogicalKeyboardKey.keyJ): () =>
            _moveSelection(1, list.length),
        const SingleActivator(LogicalKeyboardKey.keyK): () =>
            _moveSelection(-1, list.length),
      },
      child: Focus(
        autofocus: true,
        child: Padding(
          padding: const EdgeInsets.all(QuestSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Header(
                submissions: list,
                busy: busy,
                onRefresh: () =>
                    ref.invalidate(pendingSubmissionsProvider),
                onApproveAll: () => _approveAll(list),
              ),
              const SizedBox(height: QuestSpacing.xs),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Oldest first. Approve/deny is locked until you view '
                      'every photo and watch every video.',
                      style: BsheelType.bodySm.copyWith(
                        color: BsheelColors.inkMuted,
                      ),
                    ),
                  ),
                  const _ShortcutsHint(),
                ],
              ),
              const SizedBox(height: QuestSpacing.lg),
              if (busy)
                LinearProgressIndicator(
                  color: BsheelColors.ink,
                  backgroundColor: BsheelColors.ink.withAlpha(30),
                ),
              if (moderationState.hasError)
                _ErrorBanner(error: moderationState.error.toString()),
              Expanded(
                child: submissionsAsync.when(
                  loading: () => const Center(
                    child: CircularProgressIndicator(
                        color: BsheelColors.ink,),
                  ),
                  error: (e, _) => Center(
                    child: Text(
                      'Error: $e',
                      style: BsheelType.bodySm.copyWith(
                        color: BsheelColors.hot,
                      ),
                    ),
                  ),
                  data: (submissions) {
                    if (submissions.isEmpty) return const _EmptyState();

                    return ListView.separated(
                      controller: _scrollController,
                      itemCount: submissions.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: QuestSpacing.sm),
                      itemBuilder: (context, i) {
                        final sub = submissions[i];
                        final key = _itemKeys.putIfAbsent(
                            sub.id, () => GlobalKey(),);
                        final viewed = _allMediaViewed(sub);
                        final viewedSet =
                            _viewed[sub.id] ?? const <int>{};
                        return KeyedSubtree(
                          key: key,
                          child: _SubmissionCard(
                            submission: sub,
                            isSelected: i == _selectedIndex,
                            allMediaViewed: viewed,
                            viewedIndices: viewedSet,
                            onTapCard: () =>
                                setState(() => _selectedIndex = i),
                            onMediaViewed: (idx) =>
                                _markViewed(sub.id, idx),
                            onApprove: (busy || !viewed)
                                ? null
                                : () => ref
                                    .read(moderationControllerProvider
                                        .notifier,)
                                    .approve(sub),
                            onDeny: (busy || !viewed)
                                ? null
                                : () async {
                                    final note =
                                        await _showDenyDialog(context, sub);
                                    if (note == null || note.isEmpty) return;
                                    await ref
                                        .read(moderationControllerProvider
                                            .notifier,)
                                        .deny(sub, note);
                                  },
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Header ───────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header({
    required this.submissions,
    required this.busy,
    required this.onRefresh,
    required this.onApproveAll,
  });

  final List<PendingSubmission> submissions;
  final bool busy;
  final VoidCallback onRefresh;
  final VoidCallback onApproveAll;

  @override
  Widget build(BuildContext context) {
    return BsheelCard(
      padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 32),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const BsheelEyebrow('Moderation · Pending'),
                const SizedBox(height: 14),
                BsheelDisplay(
                  'Review the {queue.}',
                  baseStyle: BsheelType.displayXl.copyWith(fontSize: 44),
                ),
                const SizedBox(height: 8),
                Text(
                  '${submissions.length} submissions waiting · use '
                  'A approve · D deny · ↑↓ to navigate.',
                  style: BsheelType.bodyMd
                      .copyWith(color: BsheelColors.inkSoft),
                ),
              ],
            ),
          ),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              if (submissions.length > 1)
                BsheelButton.primary(
                  label: 'APPROVE ALL (${submissions.length})',
                  icon: Icons.done_all_rounded,
                  small: true,
                  onPressed: busy ? null : onApproveAll,
                ),
              BsheelButton.ghost(
                label: 'REFRESH',
                icon: Icons.refresh_rounded,
                small: true,
                onPressed: onRefresh,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.check_circle_outline,
            size: 64,
            color: BsheelColors.success.withAlpha(102),
          ),
          const SizedBox(height: QuestSpacing.md),
          Text(
            'NO PENDING SUBMISSIONS',
            style: BsheelType.labelMd.copyWith(color: BsheelColors.ink),
          ),
          const SizedBox(height: QuestSpacing.sm),
          Text(
            'All caught up! Check back later.',
            style:
                BsheelType.bodySm.copyWith(color: BsheelColors.inkMuted),
          ),
        ],
      ),
    );
  }
}

// ── Submission card ──────────────────────────────────────────────────────────

class _SubmissionCard extends StatelessWidget {
  const _SubmissionCard({
    required this.submission,
    required this.isSelected,
    required this.allMediaViewed,
    required this.viewedIndices,
    required this.onMediaViewed,
    required this.onApprove,
    required this.onDeny,
    required this.onTapCard,
  });

  final PendingSubmission submission;
  final bool isSelected;
  final bool allMediaViewed;
  final Set<int> viewedIndices;
  final void Function(int index) onMediaViewed;
  final VoidCallback? onApprove;
  final VoidCallback? onDeny;
  final VoidCallback onTapCard;

  static const Duration _staleAfter = Duration(hours: 24);

  bool get _isStale =>
      DateTime.now().difference(submission.submittedAt) > _staleAfter;

  @override
  Widget build(BuildContext context) {
    final name = submission.displayName ?? submission.username ?? 'Unknown';

    final flags = <Widget>[];
    if (submission.isDuplicate) {
      flags.add(const _FlagBadge(
        label: 'DUPLICATE',
        color: BsheelColors.hot,
        icon: Icons.content_copy,
      ),);
    }
    for (final f in submission.captionFlags) {
      flags.add(_FlagBadge(
        label: f,
        color: f == CaptionFlags.inappropriate
            ? BsheelColors.hot
            : BsheelColors.pureWhite,
        icon: f == CaptionFlags.inappropriate
            ? Icons.warning_amber_rounded
            : Icons.report_gmailerrorred,
      ),);
    }
    if (_isStale) {
      flags.add(const _FlagBadge(
        label: 'STALE',
        color: BsheelColors.hot,
        icon: Icons.schedule,
      ),);
    }

    final hasHistory =
        submission.userApprovedCount + submission.userRejectedCount > 0;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: _mediaPanelDeep,
        border: Border.all(
          color: isSelected
              ? BsheelColors.pureWhite.withAlpha(160)
              : _mediaPanelBorder,
          width: BsheelBorders.thin,
        ),
        borderRadius: BorderRadius.circular(BsheelRadii.lg),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(BsheelRadii.lg),
        onTap: onTapCard,
        child: Padding(
          padding: const EdgeInsets.all(QuestSpacing.lg),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              MediaSection(
                submission: submission,
                viewedIndices: viewedIndices,
                onMediaViewed: onMediaViewed,
              ),
              const SizedBox(width: QuestSpacing.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 16,
                          backgroundColor:
                              BsheelColors.pureWhite.withAlpha(30),
                          child: Text(
                            name.isNotEmpty ? name[0].toUpperCase() : '?',
                            style: BsheelType.labelSm.copyWith(
                              color: BsheelColors.pureWhite,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        const SizedBox(width: QuestSpacing.sm),
                        Flexible(
                          child: Text(
                            name,
                            style: BsheelType.bodyMdBold.copyWith(
                              color: BsheelColors.pureWhite,
                              fontSize: 15,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (hasHistory) ...[
                          const SizedBox(width: QuestSpacing.sm),
                          _UserHistoryChip(
                            approved: submission.userApprovedCount,
                            rejected: submission.userRejectedCount,
                          ),
                        ],
                        if (isSelected) ...[
                          const SizedBox(width: QuestSpacing.sm),
                          _ActivePill(),
                        ],
                      ],
                    ),
                    if (submission.questTitle != null) ...[
                      const SizedBox(height: QuestSpacing.sm),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: QuestSpacing.sm,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          borderRadius:
                              BorderRadius.circular(BsheelRadii.full),
                          border: Border.all(
                            color: _mediaPanelBorder,
                          ),
                        ),
                        child: Text(
                          submission.questTitle!,
                          style: BsheelType.labelSm.copyWith(
                            color: _mediaPanelSoft,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ],
                    if (flags.isNotEmpty) ...[
                      const SizedBox(height: QuestSpacing.sm),
                      Wrap(
                        spacing: QuestSpacing.sm,
                        runSpacing: QuestSpacing.xs,
                        children: flags,
                      ),
                    ],
                    if (submission.appealed) ...[
                      const SizedBox(height: QuestSpacing.md),
                      _AppealBanner(note: submission.appealNote),
                    ],
                    if (submission.caption != null &&
                        submission.caption!.isNotEmpty) ...[
                      const SizedBox(height: QuestSpacing.md),
                      Text(
                        submission.caption!,
                        style: BsheelType.bodyMd.copyWith(
                          color: _mediaPanelSoft,
                          height: 1.4,
                        ),
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: QuestSpacing.md),
                    Text(
                      'Submitted ${_formatTime(submission.submittedAt)}',
                      style: BsheelType.labelSm.copyWith(
                        color: _isStale
                            ? BsheelColors.hot
                            : BsheelColors.inkMuted,
                        fontSize: 11,
                        fontWeight: _isStale ? FontWeight.w500 : null,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: QuestSpacing.lg),
              SizedBox(
                width: 130,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!allMediaViewed) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: QuestSpacing.sm,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: BsheelColors.pureWhite.withAlpha(25),
                          borderRadius:
                              BorderRadius.circular(BsheelRadii.md),
                          border: Border.all(
                            color: BsheelColors.pureWhite.withAlpha(120),
                          ),
                        ),
                        child: Text(
                          'VIEW ALL\nMEDIA FIRST',
                          textAlign: TextAlign.center,
                          style: BsheelType.labelSm.copyWith(
                            color: BsheelColors.pureWhite,
                            fontSize: 9,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 0.8,
                            height: 1.2,
                          ),
                        ),
                      ),
                      const SizedBox(height: QuestSpacing.sm),
                    ],
                    ElevatedButton.icon(
                      onPressed: onApprove,
                      icon: const Icon(Icons.check, size: 16),
                      label: Text(
                        'APPROVE',
                        style: BsheelType.labelSm.copyWith(
                          color: BsheelColors.pureWhite,
                          fontSize: 11,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: BsheelColors.success,
                        foregroundColor: BsheelColors.pureWhite,
                        disabledBackgroundColor:
                            BsheelColors.success.withAlpha(50),
                        disabledForegroundColor: Colors.white54,
                        shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(BsheelRadii.full),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: QuestSpacing.md,
                          vertical: QuestSpacing.md,
                        ),
                      ),
                    ),
                    const SizedBox(height: QuestSpacing.sm),
                    OutlinedButton.icon(
                      onPressed: onDeny,
                      icon: const Icon(Icons.close, size: 16),
                      label: Text(
                        'DENY',
                        style: BsheelType.labelSm.copyWith(
                          color: BsheelColors.hot,
                          fontSize: 11,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: BsheelColors.hot,
                        side: const BorderSide(
                          color: BsheelColors.hot,
                          width: BsheelBorders.thin,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(BsheelRadii.full),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: QuestSpacing.md,
                          vertical: QuestSpacing.md,
                        ),
                      ),
                    ),
                    const SizedBox(height: QuestSpacing.sm),
                    OutlinedButton.icon(
                      onPressed: () => context.goNamed(
                        AdminRouteNames.submissionReview,
                        pathParameters: {'id': submission.id},
                      ),
                      icon: const Icon(Icons.open_in_new, size: 14),
                      label: Text(
                        'OPEN',
                        style: BsheelType.labelSm.copyWith(
                          color: BsheelColors.inkMuted,
                          fontSize: 11,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: BsheelColors.inkMuted,
                        side: const BorderSide(
                          color: _mediaPanelBorder,
                          width: BsheelBorders.thin,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(BsheelRadii.full),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

// ── Deny dialog (chip-based reasons + optional custom note) ──────────────────

Future<String?> _showDenyDialog(
    BuildContext context, PendingSubmission sub,) async {
  return showDialog<String>(
    context: context,
    builder: (_) => _DenyDialog(submission: sub),
  );
}

class _DenyDialog extends StatefulWidget {
  const _DenyDialog({required this.submission});
  final PendingSubmission submission;

  @override
  State<_DenyDialog> createState() => _DenyDialogState();
}

class _DenyDialogState extends State<_DenyDialog> {
  static const List<String> _commonReasons = [
    'Not the actual quest',
    "Doesn't show the activity clearly",
    'Low quality / unclear media',
    'Appears staged or faked',
    'Inappropriate content',
    'Duplicate / re-uploaded',
    'Spam / off-topic caption',
  ];

  final Set<String> _selected = <String>{};
  final TextEditingController _customController = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.submission.isDuplicate) {
      _selected.add('Duplicate / re-uploaded');
    }
    final cFlags = widget.submission.captionFlags;
    if (cFlags.contains(CaptionFlags.inappropriate)) {
      _selected.add('Inappropriate content');
    }
    if (cFlags.contains(CaptionFlags.spam)) {
      _selected.add('Spam / off-topic caption');
    }
  }

  @override
  void dispose() {
    _customController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final custom = _customController.text.trim();
    final canSubmit = _selected.isNotEmpty || custom.isNotEmpty;

    return BsheelDialog(
      title: 'DENY SUBMISSION',
      backgroundColor: _mediaPanelDeep,
      titleStyle:
          BsheelType.displaySm.copyWith(color: BsheelColors.pureWhite),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Pick one or more reasons. Users see these as bullet points.',
              style: BsheelType.bodySm
                  .copyWith(color: BsheelColors.inkMuted),
            ),
            const SizedBox(height: QuestSpacing.md),
            Wrap(
              spacing: QuestSpacing.sm,
              runSpacing: QuestSpacing.sm,
              children: _commonReasons.map((reason) {
                final on = _selected.contains(reason);
                return FilterChip(
                  label: Text(
                    reason,
                    style: BsheelType.labelSm.copyWith(
                      color: BsheelColors.pureWhite,
                      fontSize: 11,
                    ),
                  ),
                  selected: on,
                  showCheckmark: false,
                  backgroundColor: BsheelColors.ink,
                  selectedColor: BsheelColors.hot,
                  side: BorderSide(
                    color: on ? BsheelColors.hot : _mediaPanelBorder,
                    width: BsheelBorders.thin,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(BsheelRadii.full),
                  ),
                  onSelected: (v) => setState(() {
                    if (v) {
                      _selected.add(reason);
                    } else {
                      _selected.remove(reason);
                    }
                  }),
                );
              }).toList(),
            ),
            const SizedBox(height: QuestSpacing.md),
            BsheelTextField(
              controller: _customController,
              label: 'OTHER (OPTIONAL)',
              onChanged: (_) => setState(() {}),
              maxLines: 3,
              style: BsheelType.bodyMd
                  .copyWith(color: BsheelColors.pureWhite),
              labelStyle: BsheelType.labelSm
                  .copyWith(color: BsheelColors.inkMuted),
              fillColor: BsheelColors.pureBlack,
              borderColor: _mediaPanelBorder,
              focusedBorderColor: BsheelColors.pureWhite,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            'CANCEL',
            style:
                BsheelType.labelSm.copyWith(color: BsheelColors.inkMuted),
          ),
        ),
        ElevatedButton(
          onPressed: canSubmit ? _submit : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: BsheelColors.hot,
            foregroundColor: BsheelColors.pureWhite,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(BsheelRadii.full),
            ),
          ),
          child: Text(
            'DENY',
            style: BsheelType.labelSm.copyWith(color: BsheelColors.pureWhite),
          ),
        ),
      ],
    );
  }

  void _submit() {
    final lines = <String>[];
    for (final r in _commonReasons) {
      if (_selected.contains(r)) lines.add('• $r');
    }
    final custom = _customController.text.trim();
    if (custom.isNotEmpty) lines.add('• $custom');
    Navigator.pop(context, lines.join('\n'));
  }
}

// ── Small UI atoms ───────────────────────────────────────────────────────────

class _AppealBanner extends StatelessWidget {
  const _AppealBanner({required this.note});
  final String? note;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(QuestSpacing.md),
      decoration: BoxDecoration(
        color: BsheelColors.pureWhite.withAlpha(20),
        borderRadius: BorderRadius.circular(BsheelRadii.md),
        border: Border.all(
          color: BsheelColors.pureWhite.withAlpha(100),
          width: BsheelBorders.thin,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.gavel, size: 16, color: BsheelColors.pureWhite),
              const SizedBox(width: QuestSpacing.sm),
              Text(
                'APPEAL — PREVIOUSLY REJECTED',
                style: BsheelType.labelSm.copyWith(
                  color: BsheelColors.pureWhite,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
          if (note != null && note!.isNotEmpty) ...[
            const SizedBox(height: QuestSpacing.sm),
            Text(
              '"${note!}"',
              style: BsheelType.bodySm.copyWith(
                color: BsheelColors.pureWhite.withAlpha(220),
                fontStyle: FontStyle.italic,
                height: 1.4,
              ),
              maxLines: 5,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}

class _ActivePill extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: QuestSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: BsheelColors.pureWhite.withAlpha(30),
        borderRadius: BorderRadius.circular(BsheelRadii.full),
        border: Border.all(color: BsheelColors.pureWhite.withAlpha(120)),
      ),
      child: Text(
        'ACTIVE',
        style: BsheelType.labelSm.copyWith(
          color: BsheelColors.pureWhite,
          fontSize: 9,
          letterSpacing: 1.2,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class _ShortcutsHint extends StatelessWidget {
  const _ShortcutsHint();

  @override
  Widget build(BuildContext context) {
    return DefaultTextStyle(
      style: BsheelType.labelSm.copyWith(
        color: BsheelColors.inkMuted,
        fontSize: 10,
        letterSpacing: 0.5,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _kbd('↑↓'),
          const Text(' nav   '),
          _kbd('A'),
          const Text(' approve   '),
          _kbd('D'),
          const Text(' deny   '),
          _kbd('↵'),
          const Text(' open'),
        ],
      ),
    );
  }

  Widget _kbd(String c) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 2),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: BsheelColors.ink,
        border: Border.all(color: _mediaPanelBorder),
        borderRadius: BorderRadius.circular(BsheelRadii.lg),
      ),
      child: Text(
        c,
        style: const TextStyle(
          color: BsheelColors.pureWhite,
          fontFamily: 'monospace',
          fontSize: 10,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class _FlagBadge extends StatelessWidget {
  const _FlagBadge({
    required this.label,
    required this.color,
    required this.icon,
  });

  final String label;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: QuestSpacing.sm, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(BsheelRadii.full),
        border: Border.all(color: color.withAlpha(120)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: BsheelType.labelSm.copyWith(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w500,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }
}

class _UserHistoryChip extends StatelessWidget {
  const _UserHistoryChip({required this.approved, required this.rejected});

  final int approved;
  final int rejected;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: QuestSpacing.sm, vertical: 2),
      decoration: BoxDecoration(
        color: BsheelColors.ink,
        borderRadius: BorderRadius.circular(BsheelRadii.full),
        border: Border.all(color: _mediaPanelBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check, size: 11, color: BsheelColors.success),
          const SizedBox(width: 2),
          Text(
            '$approved',
            style: BsheelType.labelSm.copyWith(
              color: BsheelColors.success,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: QuestSpacing.sm),
          const Icon(Icons.close, size: 11, color: BsheelColors.hot),
          const SizedBox(width: 2),
          Text(
            '$rejected',
            style: BsheelType.labelSm.copyWith(
              color: BsheelColors.hot,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.error});
  final String error;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: QuestSpacing.md),
      padding: const EdgeInsets.all(QuestSpacing.md),
      decoration: BoxDecoration(
        color: BsheelColors.hot.withAlpha(20),
        borderRadius: BorderRadius.circular(BsheelRadii.md),
        border: Border.all(
          color: BsheelColors.hot.withAlpha(100),
          width: BsheelBorders.thin,
        ),
      ),
      child: Text(
        error,
        style: BsheelType.bodySm.copyWith(color: BsheelColors.hot),
      ),
    );
  }
}
