import 'dart:convert';

import 'package:app_contracts/app_contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/backend/app_backend.dart';
import '../../../../core/router/admin_route_names.dart';
import '../../../../core/theme/bsheel_design.dart';
import '../../../../shared/layout/admin_shell.dart';
import '../../../../shared/widgets/bsheel_widgets.dart';

/// Submissions awaiting a second review after the user appealed: pending
/// AND already appealed, oldest first so the longest wait is actioned next.
final appealsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  return AppBackend.repositories.moderation.listSubmissionsForAdmin(
    status: 'pending',
    appealed: true,
    order: 'asc',
  );
});

/// The appeals desk. Every user gets exactly one appeal per submission, so
/// upholding a rejection here ends the conversation — the page says that
/// once at the top and then puts the appeal text in front of the decision
/// rather than behind a link.
///
/// The longest-waiting appeal is the only card with a coral shadow: it is
/// the one item on the page that needs attention.
class AppealsPage extends ConsumerWidget {
  const AppealsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appealsAsync = ref.watch(appealsProvider);

    return AdminPage(
      title: 'Appeals',
      meta: 'Every user gets exactly one',
      child: appealsAsync.when(
        loading: () => const BsheelLoadingList(rows: 3, rowHeight: 120),
        error: (e, _) => BsheelErrorState(
          title: 'Appeals didn’t load',
          message: 'The appeals queue didn’t come back. Nothing was '
              'overturned and nothing was upheld — no decision has been '
              'recorded. $e',
          onRetry: () => ref.invalidate(appealsProvider),
        ),
        data: (appeals) {
          if (appeals.isEmpty) {
            return BsheelEmptyState.allClear(
              message: 'No appeal is waiting on a second look. The '
                  'moderation queue is where the next decision is.',
              actionLabel: 'Open the queue',
              onAction: () =>
                  context.goNamed(AdminRouteNames.pendingSubmissions),
            );
          }

          final oldest = _oldestIndex(appeals);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const BsheelCallout.warning(
                'A re-rejection is final and cannot be undone. Read the '
                'appeal text before deciding — the user cannot write a '
                'second one.',
              ),
              const SizedBox(height: 14),
              for (var i = 0; i < appeals.length; i++) ...[
                _AppealCard(
                  data: appeals[i],
                  // One coral shadow, on the appeal that has waited longest.
                  needsAttention: i == oldest,
                ),
                if (i != appeals.length - 1) const SizedBox(height: 14),
              ],
            ],
          );
        },
      ),
    );
  }

  /// The appeal that has waited longest. The provider already asks for
  /// oldest-first, but the marked card is a claim about the data, so it is
  /// read off the timestamps rather than off the sort order.
  static int _oldestIndex(List<Map<String, dynamic>> appeals) {
    var best = 0;
    DateTime? bestAt;
    for (var i = 0; i < appeals.length; i++) {
      final at = DateTime.tryParse(
        (appeals[i][SubmissionColumns.submittedAt] ?? '').toString(),
      );
      if (at == null) continue;
      if (bestAt == null || at.isBefore(bestAt)) {
        bestAt = at;
        best = i;
      }
    }
    return best;
  }
}

class _AppealCard extends ConsumerStatefulWidget {
  const _AppealCard({required this.data, required this.needsAttention});

  final Map<String, dynamic> data;
  final bool needsAttention;

  @override
  ConsumerState<_AppealCard> createState() => _AppealCardState();
}

class _AppealCardState extends ConsumerState<_AppealCard> {
  bool _overturning = false;
  bool _upholding = false;

  bool get _busy => _overturning || _upholding;

  String get _id => widget.data[SubmissionColumns.id].toString();

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final username = _text(data[ProfileColumns.username], 'unknown');
    final questTitle = _text(data['quest_title'], 'Unknown quest');
    final appealNote = _text(data[SubmissionColumns.appealNote], '');
    final submittedAt = data[SubmissionColumns.submittedAt]?.toString();

    return BsheelCard(
      radius: BsheelRadii.lg,
      shadowColor:
          widget.needsAttention ? BsheelColors.danger : BsheelColors.ink,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BsheelThumb(
            url: _firstMediaUrl,
            size: 88,
            radius: BsheelRadii.md,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(
                        username,
                        style: BsheelType.titleMd,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 9),
                    Flexible(
                      child: Text(
                        '${_shortId(data[SubmissionColumns.id])} · '
                        'WAITING ${bsheelWaiting(submittedAt).toUpperCase()}',
                        style: BsheelType.labelSm,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(questTitle, style: BsheelType.bodySmMedium),
                const SizedBox(height: 6),
                Text(
                  appealNote.isEmpty
                      ? 'They appealed without writing anything. The media '
                          'and the caption are all there is to go on.'
                      : '“$appealNote”',
                  style: BsheelType.bodySm.copyWith(
                    color: BsheelColors.inkSoft,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          SizedBox(
            width: 200,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                BsheelButton.positive(
                  label: 'Overturn · approve',
                  expand: true,
                  loading: _overturning,
                  onPressed: _busy ? null : _confirmOverturn,
                ),
                const SizedBox(height: 8),
                BsheelButton.coral(
                  label: 'Uphold · final',
                  expand: true,
                  loading: _upholding,
                  onPressed: _busy ? null : _confirmUphold,
                ),
                const SizedBox(height: 8),
                BsheelLink(
                  'Open full review',
                  align: TextAlign.center,
                  onTap: _busy
                      ? null
                      : () => context.goNamed(
                            AdminRouteNames.submissionReview,
                            pathParameters: {'id': _id},
                          ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Decisions ─────────────────────────────────────────────────────

  /// Overturning is reversible in practice — the submission can be
  /// re-reviewed — but it awards XP, so it still asks first.
  Future<void> _confirmOverturn() async {
    final username = _text(widget.data[ProfileColumns.username], 'this user');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => BsheelDialog(
        title: 'Overturn this rejection?',
        content: Text(
          'The submission is approved, @$username is awarded the quest XP '
          'and the post becomes visible. The earlier rejection stays in the '
          'audit trail.',
          style: BsheelType.bodySm,
        ),
        actions: [
          BsheelButton.ghost(
            label: 'Cancel',
            small: true,
            onPressed: () => Navigator.pop(ctx, false),
          ),
          BsheelButton.positive(
            label: 'Overturn · approve',
            small: true,
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _overturning = true);
    try {
      // The API resolves the acting moderator from the token, re-checks the
      // role, asserts the submission is still pending and awards XP once —
      // all in one transaction.
      await AppBackend.repositories.moderation.approveSubmission(
        _id,
        '',
        note: 'Appeal overturned on review.',
      );
      ref.invalidate(appealsProvider);
      _toast('Appeal overturned — the submission is approved.');
    } catch (e) {
      _toast('Nothing was changed — the appeal is still open. $e');
    } finally {
      if (mounted) setState(() => _overturning = false);
    }
  }

  /// Upholding is the one irreversible decision on this page, so the
  /// dialog says so and collects the reason the user will read.
  Future<void> _confirmUphold() async {
    final username = _text(widget.data[ProfileColumns.username], 'this user');
    final noteController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => BsheelDialog(
        title: 'Uphold — this is final',
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '@$username has already used their one appeal. Upholding the '
              'rejection closes this submission for good — they cannot '
              'write a second appeal.',
              style: BsheelType.bodySm,
            ),
            const SizedBox(height: 14),
            BsheelField(
              controller: noteController,
              label: 'Reason they will read',
              hint: 'Why the rejection stands…',
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
            label: 'Uphold · final',
            small: true,
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );
    final note = noteController.text.trim();
    noteController.dispose();
    if (confirmed != true || !mounted) return;

    setState(() => _upholding = true);
    try {
      await AppBackend.repositories.moderation.rejectSubmission(
        _id,
        '',
        note: note.isEmpty ? null : note,
      );
      ref.invalidate(appealsProvider);
      _toast('Rejection upheld. This submission is closed.');
    } catch (e) {
      _toast('Nothing was changed — the appeal is still open. $e');
    }
    if (mounted) setState(() => _upholding = false);
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  // ── Row reading ───────────────────────────────────────────────────

  /// Submissions may carry several signed media keys as a JSON list; the
  /// thumbnail shows the first, and falls back to the stripe placeholder.
  String get _firstMediaUrl {
    final raw =
        (widget.data[SubmissionColumns.mediaUrl]?.toString() ?? '').trim();
    if (raw.startsWith('[')) {
      try {
        final list = (jsonDecode(raw) as List).cast<String>();
        return list.isNotEmpty ? list.first : '';
      } catch (_) {
        // Malformed legacy JSON is one opaque media value.
      }
    }
    return raw;
  }

  static String _text(Object? value, String fallback) {
    final s = (value ?? '').toString().trim();
    return s.isEmpty ? fallback : s;
  }

  /// First six characters of the uuid, upper case — the form a moderator
  /// quotes back in a support thread.
  static String _shortId(Object? value) {
    final s = (value ?? '').toString().replaceAll('-', '').toUpperCase();
    if (s.isEmpty) return '—';
    return s.length <= 6 ? s : s.substring(0, 6);
  }
}
