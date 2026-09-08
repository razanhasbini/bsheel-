import 'package:app_contracts/app_contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/admin_route_names.dart';
import '../../../../core/theme/admin_layout_constants.dart';
import '../../../../core/theme/bsheel_design.dart';
import '../../../../shared/layout/admin_shell.dart';
import '../../../../shared/widgets/bsheel_widgets.dart';
import '../providers/moderation_controller.dart';
import '../providers/pending_submissions_provider.dart';
import '../widgets/media_section.dart';
import 'submission_review_page.dart';

/// `/moderation` — the queue rail beside the review surface.
///
/// The rail is the only list on the console that is genuinely a work
/// queue, so it is fixed at 300px and never scrolls the page: the
/// moderator keeps one hand on `J`/`K` and the proof stays put on the
/// right. The review surface itself is [SubmissionReviewSurface], shared
/// verbatim with `/moderation/review/:id` — the decision, the note, the
/// confirm step and the evidence layout live there and are not restated
/// here. This screen owns the queue, the selection, the keyboard, and the
/// view-every-asset gate that unlocks a decision.
class PendingSubmissionsPage extends ConsumerStatefulWidget {
  const PendingSubmissionsPage({super.key});

  @override
  ConsumerState<PendingSubmissionsPage> createState() =>
      _PendingSubmissionsPageState();
}

class _PendingSubmissionsPageState
    extends ConsumerState<PendingSubmissionsPage> {
  /// Rail width from the design frame.
  static const double _railWidth = 300;

  /// Below this the rail and the surface cannot both hold their minimums,
  /// so the rail takes the whole page until a submission is picked.
  static const double _twoPaneMin = 940;

  /// Queue filters. `all` and `flagged` are rail-local views over the
  /// pending set rather than statuses — the flags are client-side
  /// heuristics — so only the appeal key comes from the contract.
  static const String _fAll = 'all';
  static const String _fAppeals = SubmissionColumns.appealed;
  static const String _fFlagged = 'flagged';

  static const List<String> _videoExtensions = [
    '.mp4',
    '.mov',
    '.webm',
    '.m4v',
  ];

  String _filter = _fAll;

  /// Selected submission, by id rather than index: the queue re-sorts and
  /// shrinks under realtime, and an index would silently point at whatever
  /// slid into its place.
  String? _selectedId;

  /// Per-submission set of media indices that have been viewed. A
  /// submission unlocks once `viewed.length >= submission.mediaUrls.length`.
  final Map<String, Set<int>> _viewed = <String, Set<int>>{};

  final ScrollController _railScroll = ScrollController();
  final Map<String, GlobalKey> _itemKeys = <String, GlobalKey>{};

  /// The live review surface, so `A` and `R` run exactly the flow the
  /// buttons run — including the confirm dialog and the note.
  final GlobalKey<SubmissionReviewSurfaceState> _surfaceKey =
      GlobalKey<SubmissionReviewSurfaceState>();

  @override
  void dispose() {
    _railScroll.dispose();
    super.dispose();
  }

  // ── Queue derivation ──────────────────────────────────────────────────

  bool _isFlagged(PendingSubmission s) =>
      s.isDuplicate || s.captionFlags.isNotEmpty;

  List<PendingSubmission> _visible(List<PendingSubmission> all) =>
      switch (_filter) {
        _fAppeals => all.where((s) => s.appealed).toList(),
        _fFlagged => all.where(_isFlagged).toList(),
        _ => all,
      };

  /// The submission the surface is showing. On a wide window the queue
  /// always has a selection — an empty right pane beside a full rail is
  /// just a wasted screen — but on a narrow one nothing is picked until
  /// the moderator picks it, because the rail is the whole page.
  PendingSubmission? _resolve(List<PendingSubmission> list, bool twoPane) {
    if (list.isEmpty) return null;
    final index = list.indexWhere((s) => s.id == _selectedId);
    if (index >= 0) return list[index];
    return twoPane ? list.first : null;
  }

  String? _thumbUrl(PendingSubmission s) {
    for (final url in s.mediaUrls) {
      final lower = url.toLowerCase();
      if (!_videoExtensions.any(lower.endsWith)) return url;
    }
    return null;
  }

  // ── The view-every-asset gate ─────────────────────────────────────────

  bool _allMediaViewed(PendingSubmission s) {
    final required = s.mediaUrls.length;
    if (required == 0) return true; // no media → nothing to gate on
    final seen = _viewed[s.id]?.length ?? 0;
    return seen >= required;
  }

  void _markViewed(String submissionId, int index) {
    final set = _viewed.putIfAbsent(submissionId, () => <int>{});
    if (set.add(index)) {
      // The callback chain in MediaSection already defers to a post-frame
      // callback, so calling setState synchronously here is safe.
      if (mounted) setState(() {});
    }
  }

  // ── Selection and keyboard ────────────────────────────────────────────

  void _select(PendingSubmission s) {
    if (_selectedId == s.id) return;
    setState(() => _selectedId = s.id);
  }

  void _move(int delta, List<PendingSubmission> list) {
    if (list.isEmpty) return;
    final current = list.indexWhere((s) => s.id == _selectedId);
    final base = current >= 0 ? current : 0;
    final next = (base + delta).clamp(0, list.length - 1);
    if (list[next].id == _selectedId) return;
    setState(() => _selectedId = list[next].id);
    _scrollSelectedIntoView();
  }

  void _scrollSelectedIntoView() {
    // Run after layout so the GlobalKey has a context.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final id = _selectedId;
      if (id == null) return;
      final ctx = _itemKeys[id]?.currentContext;
      if (ctx == null) return;
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 180),
        alignment: 0.1,
        curve: Curves.easeOut,
      );
    });
  }

  /// True while the caret is in a text field. Without this the rejection
  /// note the moderator is typing would fire decisions letter by letter —
  /// every `a` an approval, every `r` a rejection.
  bool get _typing {
    final ctx = FocusManager.instance.primaryFocus?.context;
    if (ctx == null) return false;
    if (ctx.widget is EditableText) return true;
    return ctx.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  KeyEventResult _onKey(KeyEvent event, List<PendingSubmission> list) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (_typing) return KeyEventResult.ignored;

    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.keyJ ||
        key == LogicalKeyboardKey.arrowDown) {
      _move(1, list);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyK || key == LogicalKeyboardKey.arrowUp) {
      _move(-1, list);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyA) {
      _surfaceKey.currentState?.approve();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyR) {
      _surfaceKey.currentState?.reject();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter) {
      final id = _selectedId;
      if (id != null) {
        context.goNamed(
          AdminRouteNames.submissionReview,
          pathParameters: {'id': id},
        );
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // ── Decisions ─────────────────────────────────────────────────────────

  Future<bool> _approve(PendingSubmission s) =>
      ref.read(moderationControllerProvider.notifier).approve(s);

  Future<bool> _reject(PendingSubmission s, String note) =>
      ref.read(moderationControllerProvider.notifier).deny(s, note);

  /// Mass-approve with the same safety rails as single approvals: only
  /// submissions whose media has been fully viewed are eligible (the rest
  /// are skipped and reported), the moderator confirms the count first,
  /// and one failure doesn't silently abort the rest — failures are
  /// collected and summarised.
  Future<void> _approveAll(List<PendingSubmission> list) async {
    final eligible = list.where(_allMediaViewed).toList();
    final skipped = list.length - eligible.length;

    if (eligible.isEmpty) {
      _summary(
        'Nothing to approve — open a submission and view every photo and '
        'video on it first.',
      );
      return;
    }

    final confirmed = await _confirmApproveAll(eligible.length, skipped);
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
    _summary('${parts.join(' · ')}.');
  }

  Future<bool?> _confirmApproveAll(int eligible, int skipped) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => BsheelDialog(
        title: 'Approve all',
        content: Text(
          'Approve $eligible ${eligible == 1 ? 'submission' : 'submissions'}? '
          'XP is awarded once each and every author is notified. The '
          'view-every-asset gate still applies.'
          '${skipped > 0 ? '\n\n$skipped will be skipped — their media has '
              'not been fully viewed.' : ''}',
          style: BsheelType.bodySm.copyWith(color: BsheelColors.inkSoft),
        ),
        actions: [
          BsheelButton.ghost(
            label: 'Cancel',
            small: true,
            onPressed: () => Navigator.pop(ctx, false),
          ),
          BsheelButton.positive(
            label: 'Approve $eligible',
            small: true,
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );
  }

  void _summary(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: BsheelColors.card,
        content: Text(message, style: BsheelType.bodySm),
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Realtime: new submissions appear in the queue without manual
    // refresh; status changes (a decision by another moderator) drop them
    // out. autoDispose tears the channel down on navigation away.
    ref.watch(pendingSubmissionsRealtimeProvider);

    final queueAsync = ref.watch(pendingSubmissionsProvider);
    final moderation = ref.watch(moderationControllerProvider);
    final busy = moderation.isLoading;

    final all = queueAsync.valueOrNull ?? const <PendingSubmission>[];
    final list = _visible(all);
    final stale = all
        .where((s) => bsheelIsStale(s.submittedAt.toIso8601String()))
        .length;

    // Measured here rather than in a LayoutBuilder: the surface's detail
    // provider has to be watched during build, and a layout callback runs
    // after it. The shell keeps the sidebar beside the page above the
    // tablet breakpoint, so that width is not the page's.
    final windowWidth = MediaQuery.sizeOf(context).width;
    final pageWidth =
        windowWidth >= AdminLayoutConstants.tabletBreakpoint
            ? windowWidth - BsheelLayout.sidebarWidth
            : windowWidth;
    final twoPane = pageWidth >= _twoPaneMin;

    final selected = _resolve(list, twoPane);
    final detailAsync = selected == null
        ? null
        : ref.watch(submissionDetailProvider(selected.id));

    return AdminPage(
      title: 'Moderation',
      meta: stale > 0
          ? '${all.length} waiting · $stale stale'
          : '${all.length} waiting',
      metaColor: stale > 0 ? BsheelColors.dangerText : null,
      scrollable: false,
      padding: EdgeInsets.zero,
      actions: [
        if (list.length > 1)
          BsheelButton.positive(
            label: 'Approve all',
            icon: Icons.done_all_rounded,
            small: true,
            onPressed: busy ? null : () => _approveAll(list),
          ),
        BsheelIconButton(
          icon: Icons.refresh_rounded,
          tooltip: 'Refresh the queue',
          onTap: () => ref.invalidate(pendingSubmissionsProvider),
        ),
      ],
      child: Focus(
        autofocus: true,
        onKeyEvent: (_, event) => _onKey(event, list),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (moderation.hasError)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                child: BsheelCallout.danger(
                  moderation.error.toString(),
                  trailing: BsheelButton.ghost(
                    label: 'Reload',
                    small: true,
                    onPressed: () =>
                        ref.invalidate(pendingSubmissionsProvider),
                  ),
                ),
              ),
            Expanded(
              child: !twoPane
                  // Narrow: the rail is the page until a submission is
                  // picked, then the surface is, with a way back.
                  ? (selected == null || detailAsync == null
                      ? _rail(
                          queueAsync: queueAsync,
                          all: all,
                          list: list,
                          selected: null,
                          fullWidth: true,
                        )
                      : _surface(
                          selected: selected,
                          detailAsync: detailAsync,
                          list: list,
                          busy: busy,
                          onBack: () => setState(() => _selectedId = null),
                        ))
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _rail(
                          queueAsync: queueAsync,
                          all: all,
                          list: list,
                          selected: selected,
                          fullWidth: false,
                        ),
                        Expanded(
                          child: selected == null || detailAsync == null
                              ? _nothingSelected(queueAsync, list)
                              : _surface(
                                  selected: selected,
                                  detailAsync: detailAsync,
                                  list: list,
                                  busy: busy,
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

  // ── Queue rail ────────────────────────────────────────────────────────

  Widget _rail({
    required AsyncValue<List<PendingSubmission>> queueAsync,
    required List<PendingSubmission> all,
    required List<PendingSubmission> list,
    required PendingSubmission? selected,
    required bool fullWidth,
  }) {
    return Container(
      width: fullWidth ? null : _railWidth,
      decoration: BoxDecoration(
        color: BsheelColors.surface,
        border: fullWidth
            ? null
            : const Border(right: BsheelBorders.inkSide),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header — the count, then the three views of the queue.
          Container(
            padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
            decoration: const BoxDecoration(
              border: Border(bottom: BsheelBorders.inkSide),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'PENDING REVIEW · ${list.length}',
                  style: BsheelType.labelMd,
                ),
                const SizedBox(height: 4),
                BsheelFilterChips(
                  selected: _filter,
                  onChanged: (v) => setState(() => _filter = v),
                  filters: [
                    const BsheelFilter(_fAll, 'All'),
                    BsheelFilter(
                      _fAppeals,
                      'Appeals',
                      count: all.where((s) => s.appealed).length,
                    ),
                    BsheelFilter(
                      _fFlagged,
                      'Flagged',
                      count: all.where(_isFlagged).length,
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(child: _railBody(queueAsync, all, list, selected)),
          // Footer — the shortcuts, stated where the hand already is.
          Container(
            padding: const EdgeInsets.fromLTRB(16, 11, 16, 11),
            decoration: const BoxDecoration(
              border: Border(top: BsheelBorders.inkSide),
            ),
            child: const Text(
              'J / K MOVE · A APPROVE · R REJECT',
              style: BsheelType.labelSm,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _railBody(
    AsyncValue<List<PendingSubmission>> queueAsync,
    List<PendingSubmission> all,
    List<PendingSubmission> list,
    PendingSubmission? selected,
  ) {
    return queueAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(12),
        child: BsheelLoadingList(rows: 5, rowHeight: 68),
      ),
      error: (error, _) => Padding(
        padding: const EdgeInsets.all(12),
        child: BsheelErrorState(
          title: 'The queue didn’t load',
          message: 'The pending list didn’t come back. Nothing was lost — '
              'no decision has been recorded. $error',
          onRetry: () => ref.invalidate(pendingSubmissionsProvider),
        ),
      ),
      data: (_) {
        if (list.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(12),
            child: all.isEmpty
                ? BsheelEmptyState.allClear(
                    message: 'Nothing is waiting on a moderator. Newly '
                        'submitted proof lands here on its own.',
                    actionLabel: 'Open the history',
                    onAction: () => context.goNamed(
                      AdminRouteNames.submissionHistory,
                    ),
                  )
                : BsheelEmptyState(
                    title: 'Nothing in this view',
                    message: 'No pending submission matches this filter — '
                        'the rest of the queue is still waiting.',
                    actionLabel: 'Show the whole queue',
                    onAction: () => setState(() => _filter = _fAll),
                  ),
          );
        }

        return ListView.separated(
          controller: _railScroll,
          padding: const EdgeInsets.all(12),
          itemCount: list.length,
          separatorBuilder: (_, __) => const SizedBox(height: 9),
          itemBuilder: (context, i) {
            final s = list[i];
            final key = _itemKeys.putIfAbsent(s.id, () => GlobalKey());
            return KeyedSubtree(
              key: key,
              child: _QueueCard(
                submission: s,
                thumbUrl: _thumbUrl(s),
                flagged: _isFlagged(s),
                selected: s.id == selected?.id,
                onTap: () => _select(s),
              ),
            );
          },
        );
      },
    );
  }

  // ── Review surface ────────────────────────────────────────────────────

  Widget _surface({
    required PendingSubmission selected,
    required AsyncValue<Map<String, dynamic>?> detailAsync,
    required List<PendingSubmission> list,
    required bool busy,
    VoidCallback? onBack,
  }) {
    final index = list.indexWhere((s) => s.id == selected.id);

    return detailAsync.when(
      loading: () => const SubmissionReviewSkeleton(),
      error: (error, _) => Padding(
        padding: BsheelLayout.pagePadding,
        child: BsheelErrorState(
          title: 'The review didn’t load',
          message: 'This submission’s detail didn’t come back, so nothing '
              'here is stale — and no decision has been recorded. $error',
          onRetry: () =>
              ref.invalidate(submissionDetailProvider(selected.id)),
        ),
      ),
      data: (data) {
        if (data == null) {
          return Padding(
            padding: BsheelLayout.pagePadding,
            child: BsheelEmptyState(
              title: 'Already decided',
              message: 'This submission is no longer in the queue — another '
                  'moderator may have just decided it.',
              actionLabel: 'Refresh the queue',
              onAction: () => ref.invalidate(pendingSubmissionsProvider),
            ),
          );
        }

        final gated = !_allMediaViewed(selected);

        return SubmissionReviewSurface(
          key: _surfaceKey,
          submissionId: selected.id,
          data: data,
          // MediaSection carries the view-every-asset gate, so the queue
          // draws the evidence rather than letting the surface do it.
          mediaBuilder: (context, maxWidth) => MediaSection(
            submission: selected,
            viewedIndices: _viewed[selected.id] ?? const <int>{},
            onMediaViewed: (i) => _markViewed(selected.id, i),
            maxWidth: maxWidth,
          ),
          position: index >= 0 ? index + 1 : null,
          queueLength: index >= 0 ? list.length : null,
          approvedCount: selected.userApprovedCount,
          rejectedCount: selected.userRejectedCount,
          suggestedReasons: suggestedRejectionReasons(selected),
          busy: busy,
          blockedReason: gated ? 'View all media first' : null,
          onApprove: (_) => _approve(selected),
          onReject: (note) => _reject(selected, note),
          onBack: onBack,
        );
      },
    );
  }

  Widget _nothingSelected(
    AsyncValue<List<PendingSubmission>> queueAsync,
    List<PendingSubmission> list,
  ) {
    if (queueAsync.isLoading) return const SubmissionReviewSkeleton();
    return Padding(
      padding: BsheelLayout.pagePadding,
      child: BsheelEmptyState(
        title: 'Nothing selected',
        message: 'Pick a submission from the queue to see its proof, the '
            'author’s record and the decision.',
        actionLabel: list.isEmpty ? null : 'Review the oldest',
        onAction: list.isEmpty ? null : () => _select(list.first),
      ),
    );
  }
}

// ── Queue card ──────────────────────────────────────────────────────────

/// One rail row: thumbnail, who, which quest, how long it has waited.
///
/// The selected row is the only card on the page carrying a coloured
/// shadow — it is the one item that needs attention, and everything else
/// in the rail is flat.
class _QueueCard extends StatelessWidget {
  const _QueueCard({
    required this.submission,
    required this.thumbUrl,
    required this.flagged,
    required this.selected,
    required this.onTap,
  });

  final PendingSubmission submission;
  final String? thumbUrl;
  final bool flagged;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final name =
        submission.displayName ?? submission.username ?? 'Unknown author';
    final iso = submission.submittedAt.toIso8601String();
    final stale = bsheelIsStale(iso);

    final body = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        BsheelThumb(url: thumbUrl),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // A long display name plus both markers will not hold one
              // line in a 300px rail, so they wrap instead of clipping.
              Wrap(
                spacing: 6,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    name,
                    style: BsheelType.titleMd,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (submission.appealed)
                    const BsheelPill(
                      'appeal',
                      tone: BsheelPillTone.gold,
                      small: true,
                    ),
                  if (flagged)
                    const BsheelPill(
                      'flagged',
                      tone: BsheelPillTone.coral,
                      small: true,
                    ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                submission.questTitle ?? 'Quest unavailable',
                style: BsheelType.bodyXs,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                'WAITING ${bsheelWaiting(iso)}'.toUpperCase(),
                style: BsheelType.labelMd.copyWith(
                  color:
                      stale ? BsheelColors.dangerText : BsheelColors.inkMuted,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );

    if (selected) {
      return BsheelCard(
        padding: const EdgeInsets.all(11),
        depth: 4,
        shadowColor: BsheelColors.primary,
        onTap: onTap,
        child: body,
      );
    }
    return BsheelCard.flat(
      padding: const EdgeInsets.all(11),
      onTap: onTap,
      child: body,
    );
  }
}
