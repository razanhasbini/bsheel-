import 'package:app_contracts/app_contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/backend/app_backend.dart';
import '../../../../core/theme/bsheel_design.dart';
import '../../../../shared/layout/admin_shell.dart';
import '../../../../shared/widgets/bsheel_widgets.dart';

/// Every report, newest first. `status: all` rather than `pending`, so the
/// filter chips can switch view without a second round trip.
final reportsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  return AppBackend.repositories.admin.reports(status: 'all', limit: 100);
});

/// `/reports` — one card per report, evidence on the left and the two
/// actions on the right.
///
/// Reports arrive one row per reporter, so three people flagging the same
/// post are three rows. The card therefore states how many reports it
/// stands for, counted over the fetched page: a moderator deciding whether
/// something is worth removing needs to know it was three people and not
/// one. The most-reported open target is the only card with a coloured
/// shadow — it is the one item on the page that needs attention.
///
/// `reason` is free text on the way in (`reports.reason`, 1–500 chars),
/// not a category enum, so the coloured pill carries what the row *is*
/// (post, comment, account) and the reporter's own words are the sentence
/// underneath. Inventing a severity taxonomy the database does not hold
/// would put a label on the card that nothing could keep true.
class ReportsPage extends ConsumerStatefulWidget {
  const ReportsPage({super.key});

  @override
  ConsumerState<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends ConsumerState<ReportsPage> {
  static const String _fPending = 'pending';
  static const String _fActioned = 'actioned';
  static const String _fDismissed = 'dismissed';
  static const String _fAll = 'all';

  String _filter = _fPending;

  @override
  Widget build(BuildContext context) {
    final reportsAsync = ref.watch(reportsProvider);
    final loaded = reportsAsync.valueOrNull;
    final untriaged = loaded?.where((r) => _status(r) == _fPending).length ?? 0;

    return AdminPage(
      title: 'Reports',
      // Plain, as drawn. The queue depth belongs on the sidebar badge,
      // which is already coral; colouring the count here too would put
      // three shades of alarm on one page for the same fact.
      meta: loaded == null ? null : '$untriaged untriaged',
      actions: [
        BsheelIconButton(
          icon: Icons.refresh_rounded,
          tooltip: 'Refresh the reports',
          onTap: () => ref.invalidate(reportsProvider),
        ),
      ],
      subheader: BsheelFilterChips(
        selected: _filter,
        onChanged: (v) => setState(() => _filter = v),
        filters: [
          BsheelFilter(
            _fPending,
            'Untriaged',
            count: loaded == null ? null : untriaged,
            ground: BsheelColors.accent,
          ),
          BsheelFilter(
            _fActioned,
            'Actioned',
            count: loaded?.where((r) => _status(r) == _fActioned).length,
          ),
          BsheelFilter(
            _fDismissed,
            'Dismissed',
            count: loaded?.where((r) => _status(r) == _fDismissed).length,
          ),
          BsheelFilter(
            _fAll,
            'All',
            count: loaded?.length,
          ),
        ],
      ),
      child: reportsAsync.when(
        loading: () => const BsheelLoadingList(rows: 3, rowHeight: 112),
        error: (e, _) => BsheelErrorState(
          title: 'Reports didn’t load',
          message: 'The report queue didn’t come back. Nothing was removed '
              'and nothing was dismissed — this page only reads until you '
              'press one of the buttons. $e',
          onRetry: () => ref.invalidate(reportsProvider),
        ),
        data: (reports) {
          if (reports.isEmpty) {
            return const BsheelEmptyState.allClear(
              message: 'Nobody has reported anything. Reports land here the '
                  'moment a user files one, newest first.',
            );
          }

          final counts = _countsByTarget(reports);
          final visible = _filter == _fAll
              ? reports
              : reports.where((r) => _status(r) == _filter).toList();

          if (visible.isEmpty) {
            return BsheelEmptyState(
              title: 'Nothing in this view',
              message: 'No report has this status. The rest of the queue is '
                  'still there under ALL.',
              actionLabel: 'Show every report',
              onAction: () => setState(() => _filter = _fAll),
            );
          }

          // The one coloured shadow: the open report standing for the most
          // people. Read off the counts rather than off the sort order, so
          // it is a claim about the data and not about the query.
          String? loudest;
          var loudestCount = 0;
          for (final r in visible) {
            if (_status(r) != _fPending) continue;
            final key = _targetKey(r);
            final n = counts[key] ?? 1;
            if (n > loudestCount) {
              loudestCount = n;
              loudest = _reportId(r);
            }
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < visible.length; i++) ...[
                _ReportCard(
                  data: visible[i],
                  reportCount: counts[_targetKey(visible[i])] ?? 1,
                  needsAttention: _reportId(visible[i]) == loudest,
                  onReview: (status) => _review(visible[i], status),
                  onRemovePost: () => _confirmRemovePost(visible[i]),
                  onBan: () => _confirmBan(visible[i]),
                ),
                if (i != visible.length - 1) const SizedBox(height: 14),
              ],
            ],
          );
        },
      ),
    );
  }

  // ── Row reading ────────────────────────────────────────────────────

  static String _status(Map<String, dynamic> r) =>
      (r['status'] ?? _fPending).toString();

  static String _reportId(Map<String, dynamic> r) => (r['id'] ?? '').toString();

  /// What the report points at. Two rows with the same key are the same
  /// thing reported by two different people.
  static String _targetKey(Map<String, dynamic> r) =>
      '${r['reported_type']}:${r['reported_id']}';

  /// How many reports each target carries, across the fetched page.
  static Map<String, int> _countsByTarget(List<Map<String, dynamic>> rows) {
    final out = <String, int>{};
    for (final r in rows) {
      final key = _targetKey(r);
      out[key] = (out[key] ?? 0) + 1;
    }
    return out;
  }

  // ── Actions ────────────────────────────────────────────────────────

  Future<void> _review(Map<String, dynamic> r, String status) async {
    try {
      await AppBackend.repositories.admin.reviewReport(
        _reportId(r),
        status: status,
      );
      ref.invalidate(reportsProvider);
      _toast(
        status == _fDismissed
            ? 'Report dismissed. The content is untouched.'
            : 'Report marked $status.',
      );
    } catch (e) {
      _toast('Nothing changed — the report is still open. $e');
    }
  }

  /// Taking a post down is the one action on this page a user will notice,
  /// so it names what happens and collects the reason that gets recorded.
  Future<void> _confirmRemovePost(Map<String, dynamic> r) async {
    final submissionId = (r['reported_id'] ?? '').toString();
    if (submissionId.isEmpty) return;
    final owner = (r['reported_username'] ?? 'the author').toString();

    final noteController = TextEditingController(
      text: (r['reason'] ?? '').toString(),
    );
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => BsheelDialog(
        title: 'Remove this post?',
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'The post leaves the feed immediately and @$owner cannot '
              'restore it themselves. Their XP for the quest is unaffected. '
              'The takedown is recorded against your account.',
              style: BsheelType.bodySm,
            ),
            const SizedBox(height: 14),
            BsheelField(
              controller: noteController,
              label: 'Reason on the record',
              hint: 'Why this post is coming down…',
              maxLines: 3,
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
            label: 'Remove post',
            small: true,
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );
    final reason = noteController.text.trim();
    noteController.dispose();
    if (confirmed != true || !mounted) return;

    try {
      await AppBackend.repositories.admin.removePost(
        submissionId,
        reason.isEmpty ? 'Removed while actioning a content report' : reason,
      );
      await _review(r, _fActioned);
      _toast('Post removed and the report marked actioned.');
    } catch (e) {
      _toast('Nothing was removed — the post is still up. $e');
    }
  }

  Future<void> _confirmBan(Map<String, dynamic> r) async {
    final userId = r['reported_user_id']?.toString();
    if (userId == null || userId.isEmpty) return;
    final username = (r['reported_username'] ?? userId).toString();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => BsheelDialog(
        title: 'Ban this account?',
        content: Text(
          'Ban @$username? Their account is locked immediately and they '
          'cannot use the app until it is unbanned. The report is marked '
          'actioned. Both actions are audited.',
          style: BsheelType.bodySm,
        ),
        actions: [
          BsheelButton.ghost(
            label: 'Cancel',
            small: true,
            onPressed: () => Navigator.pop(ctx, false),
          ),
          BsheelButton.coral(
            label: 'Ban account',
            small: true,
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await AppBackend.repositories.admin.setAccountStatus(
        userId,
        'banned',
        'Banned while actioning content report ${_reportId(r)}',
      );
      await _review(r, _fActioned);
      _toast('@$username is banned and the report is marked actioned.');
    } catch (e) {
      _toast('Nothing changed — the account is untouched. $e');
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}

// ── Card ──────────────────────────────────────────────────────────────

/// One report: thumbnail, what it is, who filed it, what they said, and
/// the actions. Same shape as an appeal card, because it is the same job.
class _ReportCard extends StatelessWidget {
  const _ReportCard({
    required this.data,
    required this.reportCount,
    required this.needsAttention,
    required this.onReview,
    required this.onRemovePost,
    required this.onBan,
  });

  final Map<String, dynamic> data;
  final int reportCount;
  final bool needsAttention;
  final ValueChanged<String> onReview;
  final VoidCallback onRemovePost;
  final VoidCallback onBan;

  /// The design's thumbnail is 80px square with an 11px corner.
  static const double _thumbSize = 80;

  @override
  Widget build(BuildContext context) {
    final type = (data['reported_type'] ?? '').toString();
    final status = (data['status'] ?? 'pending').toString();
    final pending = status == 'pending';
    final reason = (data['reason'] ?? '').toString().trim();
    final reporter = ((data[EmbedKeys.profiles]
                as Map<String, dynamic>?)?[ProfileColumns.username] ??
            'someone')
        .toString();
    final target = (data['reported_username'] ?? '').toString();
    final isSubmission = type == 'submission';

    // A submission report gets the stripe placeholder — the reports read
    // carries no media key, so there is nothing to sign and nothing to
    // show. A comment or account report has no image at all, so it gets a
    // labelled block instead of a fake one.
    final thumb = isSubmission
        ? const BsheelMediaPlaceholder(
            label: '',
            width: _thumbSize,
            height: _thumbSize,
            radius: BsheelRadii.md,
          )
        : Container(
            width: _thumbSize,
            height: _thumbSize,
            decoration: BoxDecoration(
              color: BsheelColors.lavender,
              borderRadius: BorderRadius.circular(BsheelRadii.md),
              border: const Border.fromBorderSide(BsheelBorders.inkSide),
            ),
            alignment: Alignment.center,
            child: BsheelLabel(
              type == 'comment' ? 'COMMENT' : 'USER',
              color: BsheelColors.ink,
              size: 9,
            ),
          );

    final evidence = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 9,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            BsheelPill(
              _typeLabel(type),
              // Gold while it waits on a person, jade once actioned, and
              // a dashed outline once dismissed — the colour says what is
              // left to do, not what kind of thing it is.
              tone: switch (status) {
                'actioned' => BsheelPillTone.green,
                'dismissed' => BsheelPillTone.ghost,
                _ => BsheelPillTone.gold,
              },
              dashed: status == 'dismissed',
              small: true,
            ),
            Text(
              [
                '$reportCount ${reportCount == 1 ? "REPORT" : "REPORTS"}',
                '${_typeLabel(type)} ${_targetLabel()}',
              ].join(' · '),
              style: BsheelType.labelMd.copyWith(letterSpacing: 0.6),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          target.isEmpty
              ? 'Reported by @$reporter'
              : '${_typeLabel(type).toLowerCase() == "user" ? "Account" : _typeLabel(type)} '
                  'by @$target — reported by @$reporter',
          style: BsheelType.bodyMdBold,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 6),
        Text(
          reason.isEmpty
              ? 'They filed the report without writing a reason, so the '
                  'content itself is all there is to go on.'
              : reason,
          // The reporter's own words, so normal case and body colour.
          style: BsheelType.bodySm.copyWith(color: BsheelColors.inkSoft),
          maxLines: 4,
          overflow: TextOverflow.ellipsis,
        ),
        if (!pending) ...[
          const SizedBox(height: 6),
          Text(
            'ALREADY $status'.toUpperCase(),
            style: BsheelType.labelSm,
          ),
        ],
      ],
    );

    final decision = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Removal is only offered where there is a post to remove.
        if (pending && isSubmission) ...[
          BsheelButton.coral(
            label: 'Remove post',
            expand: true,
            small: true,
            onPressed: onRemovePost,
          ),
          const SizedBox(height: 8),
        ],
        if (pending) ...[
          BsheelButton.ghost(
            label: 'Dismiss',
            expand: true,
            small: true,
            onPressed: () => onReview('dismissed'),
          ),
          if (data['reported_user_id'] != null) ...[
            const SizedBox(height: 8),
            BsheelLink('Ban the account',
                align: TextAlign.center, onTap: onBan),
          ],
        ] else
          BsheelButton.ghost(
            label: 'Reopen',
            expand: true,
            small: true,
            onPressed: () => onReview('pending'),
          ),
      ],
    );

    return BsheelCard(
      radius: BsheelRadii.lg,
      depth: needsAttention ? 5 : 0,
      shadowColor: BsheelColors.danger,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Below this the thumbnail, the reason and a 190px button column
          // cannot all hold their minimums, so the decision drops under
          // the evidence rather than clipping the reporter's words.
          if (constraints.maxWidth < 560) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    thumb,
                    const SizedBox(width: 14),
                    Expanded(child: evidence),
                  ],
                ),
                const SizedBox(height: 14),
                decision,
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              thumb,
              const SizedBox(width: 14),
              Expanded(child: evidence),
              const SizedBox(width: 14),
              SizedBox(width: 190, child: decision),
            ],
          );
        },
      ),
    );
  }

  /// `submission` is the database's word; a moderator says "post".
  static String _typeLabel(String type) => switch (type) {
        'submission' => 'POST',
        'comment' => 'COMMENT',
        'user' => 'USER',
        _ => 'REPORT',
      };

  /// The target as a moderator would quote it: a username where there is
  /// one, otherwise the short id of the thing.
  String _targetLabel() {
    final username = (data['reported_username'] ?? '').toString().trim();
    if (username.isNotEmpty && data['reported_type'] == 'user') {
      return username;
    }
    final id = (data['reported_id'] ?? '').toString().replaceAll('-', '');
    if (id.isEmpty) return '—';
    return (id.length <= 6 ? id : id.substring(0, 6)).toUpperCase();
  }
}
