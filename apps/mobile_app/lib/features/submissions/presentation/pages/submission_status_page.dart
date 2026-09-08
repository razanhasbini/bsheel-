import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/utils/account_lock_guard.dart';
import 'package:app_core/app_core.dart';
import 'package:app_models/app_models.dart';
import 'package:app_repositories/app_repositories.dart'
    show RealtimeDomainEvent;
import 'package:supabase_contracts/supabase_contracts.dart';
import '../../data/submission_providers.dart';
import '../../../quests/data/quest_providers.dart';
import '../../../feed/presentation/providers/feed_provider.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../core/backend/app_backend.dart';

// Screen-specific colours — not theme tokens.
const Color _inkShadow = Color(0x331A1330); // ~20% ink hard offset shadow
const Color _inkShadowSoft = Color(0x261A1330); // ~15% ink text-field shadow

class SubmissionStatusPage extends ConsumerStatefulWidget {
  final String submissionId;

  const SubmissionStatusPage({super.key, required this.submissionId});

  @override
  ConsumerState<SubmissionStatusPage> createState() =>
      _SubmissionStatusPageState();
}

class _SubmissionStatusPageState extends ConsumerState<SubmissionStatusPage> {
  StreamSubscription<RealtimeDomainEvent>? _realtimeSubscription;
  bool _postSubscribed = false;
  // ARC-003: gate the appeal RPC against double-submit. The bottom
  // sheet's send button can be tapped twice in quick succession on a
  // slow connection, which used to fire two RPCs (the second of which
  // hits "Already appealed" from 0119 and surfaced as a raw exception).
  bool _appealing = false;

  String get submissionId => widget.submissionId;

  String? _lastKnownStatus;

  @override
  void initState() {
    super.initState();
    final realtime = AppBackend.repositories.realtime;
    _realtimeSubscription = realtime.events.where((event) {
      return event.data['submissionId'] == submissionId &&
          event.type.startsWith('submission.');
    }).listen((event) {
      final status = switch (event.type) {
        'submission.approved' => SubmissionStatus.approved,
        'submission.rejected' => SubmissionStatus.rejected,
        _ => null,
      };
      _handleStatusUpdate(status);
    });
    unawaited(() async {
      try {
        await realtime.connect();
        realtime.subscribeToPost(submissionId);
        _postSubscribed = true;
      } catch (error) {
        AppLogger.warning('[SubmissionStatus] Realtime failed: $error');
      }
    }());
  }

  @override
  void dispose() {
    if (_postSubscribed) {
      try {
        AppBackend.repositories.realtime.unsubscribeFromPost(submissionId);
      } on Object {
        // The shared socket may already be reconnecting or signed out.
      }
    }
    final subscription = _realtimeSubscription;
    if (subscription != null) unawaited(subscription.cancel());
    super.dispose();
  }

  void _handleStatusUpdate(String? newStatus) {
    ref.invalidate(submissionByIdProvider(submissionId));
    ref.invalidate(feedProvider);
    ref.invalidate(activeQuestProvider);
    ref.invalidate(questHistoryProvider);
    ref.invalidate(userSubmissionsProvider);

    if (!mounted) return;
    if (_lastKnownStatus != null &&
        newStatus != null &&
        newStatus != _lastKnownStatus) {
      final messenger = ScaffoldMessenger.maybeOf(context);
      if (messenger != null) {
        final approved = newStatus == SubmissionStatus.approved;
        final rejected = newStatus == SubmissionStatus.rejected;
        final friendly = approved
            ? 'Submission approved! 🎉 XP awarded.'
            : rejected
                ? 'Submission rejected. See the reviewer notes below.'
                : 'Submission status updated.';
        messenger.showSnackBar(
          SnackBar(
            content: Text(friendly),
            backgroundColor:
                approved ? QuestColors.successGreen : QuestColors.softRed,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
    if (newStatus != null) _lastKnownStatus = newStatus;
  }

  @override
  Widget build(BuildContext context) {
    final submissionAsync = ref.watch(submissionByIdProvider(submissionId));
    // Seed _lastKnownStatus from the initial fetch so the very first
    // realtime status flip after page open is detected. Without this
    // seed we only start tracking from the second event onward.
    if (_lastKnownStatus == null) {
      final initial = submissionAsync.valueOrNull;
      if (initial != null) _lastKnownStatus = initial.status;
    }

    Future<void> handleRefresh() async {
      ref.invalidate(submissionByIdProvider(submissionId));
      try {
        await ref.read(submissionByIdProvider(submissionId).future);
      } catch (_) {/* surfaced through .when error state */}
    }

    return Scaffold(
      backgroundColor: QuestColors.bg(context),
      body: SafeArea(
        child: Column(
          children: [
            // App bar — chunky back tile, centered title.
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: QuestSpacing.screenPadding,
                vertical: QuestSpacing.sm,
              ),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () {
                      if (Navigator.of(context).canPop()) {
                        context.pop();
                      } else {
                        context.goNamed(RouteNames.home);
                      }
                    },
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: _chunkyDecoration(
                        radius: QuestSpacing.radiusSm,
                      ),
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.arrow_back,
                        size: 20,
                        color: QuestColors.osTextPrimary,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    AppLocalizations.of(context)!.submissionTitle.toUpperCase(),
                    style: QuestTypography.headlineSmall.copyWith(
                      color: QuestColors.osTextPrimary,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const Spacer(),
                  const SizedBox(width: 40),
                ],
              ),
            ),

            Expanded(
              child: RefreshIndicator(
                color: QuestColors.violet,
                backgroundColor: QuestColors.osCard,
                onRefresh: handleRefresh,
                child: submissionAsync.when(
                  loading: () => ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: const [
                      SizedBox(height: 160),
                      Center(child: CircularProgressIndicator(strokeWidth: 2)),
                    ],
                  ),
                  error: (e, _) => ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.symmetric(
                      horizontal: QuestSpacing.screenPadding,
                    ),
                    children: [
                      const SizedBox(height: 100),
                      Icon(Icons.error_outline,
                          color: QuestColors.textDim(context), size: 48),
                      const SizedBox(height: QuestSpacing.md),
                      Text(
                        'Failed to load submission',
                        textAlign: TextAlign.center,
                        style: QuestTypography.bodyMedium.copyWith(
                          color: QuestColors.textDim(context),
                        ),
                      ),
                      const SizedBox(height: QuestSpacing.sm),
                      Center(
                        child: Text(
                          'PULL TO RETRY',
                          style: QuestTypography.labelSmall.copyWith(
                            color: QuestColors.accent(context),
                            letterSpacing: 1.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                  data: (submission) {
                    if (submission == null) {
                      return ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          const SizedBox(height: 120),
                          Center(
                            child: Text(
                              AppLocalizations.of(context)!.submissionNotFound,
                            ),
                          ),
                        ],
                      );
                    }

                    final status = submission.status;
                    final statusColor = _statusColor(status);
                    final statusIcon = _statusIcon(status);
                    final isRejected = status == SubmissionStatus.rejected;
                    final rejectionReasons = isRejected
                        ? _extractRejectionReasons(submission.reviewNote)
                        : const <String>[];

                    return SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(QuestSpacing.screenPadding),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Status banner — white card with colored icon disc
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(QuestSpacing.lg),
                            decoration: _chunkyDecoration(),
                            child: Column(
                              children: [
                                Container(
                                  width: 64,
                                  height: 64,
                                  decoration: BoxDecoration(
                                    color: statusColor,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: QuestColors.osBorderStrong,
                                      width: 2,
                                    ),
                                    boxShadow: const [
                                      BoxShadow(
                                        color: _inkShadow,
                                        offset: Offset(2, 3),
                                        blurRadius: 0,
                                      ),
                                    ],
                                  ),
                                  alignment: Alignment.center,
                                  child: Icon(statusIcon,
                                      color: QuestColors.osTextOnPrimary,
                                      size: 32),
                                ),
                                const SizedBox(height: QuestSpacing.md),
                                Text(
                                  status.toUpperCase(),
                                  style:
                                      QuestTypography.headlineMedium.copyWith(
                                    color: QuestColors.osTextPrimary,
                                    letterSpacing: 1.5,
                                  ),
                                ),
                                const SizedBox(height: QuestSpacing.xs),
                                Text(
                                  status == SubmissionStatus.pending
                                      ? 'Your submission is being reviewed'
                                      : status == SubmissionStatus.approved
                                          ? 'Your submission was approved!'
                                          : 'Your submission was rejected',
                                  textAlign: TextAlign.center,
                                  style: QuestTypography.bodySmall.copyWith(
                                    color: QuestColors.osTextSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: QuestSpacing.xl),

                          // Media proof
                          _SectionLabel(
                            AppLocalizations.of(context)!.yourProof,
                          ),
                          const SizedBox(height: QuestSpacing.sm),
                          _ProofMediaCarousel(submission: submission),
                          const SizedBox(height: QuestSpacing.lg),

                          // Caption
                          if (submission.caption != null &&
                              submission.caption!.isNotEmpty) ...[
                            const _SectionLabel('CAPTION'),
                            const SizedBox(height: QuestSpacing.sm),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(QuestSpacing.md),
                              decoration: _chunkyDecoration(),
                              child: Text(
                                submission.caption!,
                                style: QuestTypography.bodyMedium.copyWith(
                                  color: QuestColors.osTextSecondary,
                                  height: 1.6,
                                ),
                              ),
                            ),
                            const SizedBox(height: QuestSpacing.xl),
                          ],

                          // Moderator feedback (approved subs)
                          if (status == SubmissionStatus.approved &&
                              submission.reviewNote != null &&
                              submission.reviewNote!.isNotEmpty) ...[
                            _SectionLabel(
                              AppLocalizations.of(context)!.moderatorFeedback,
                            ),
                            const SizedBox(height: QuestSpacing.sm),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(QuestSpacing.md),
                              decoration:
                                  _chunkyDecoration(accent: statusColor),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(Icons.check_circle_outline,
                                      color: statusColor, size: 20),
                                  const SizedBox(width: QuestSpacing.sm),
                                  Expanded(
                                    child: Text(
                                      submission.reviewNote!,
                                      style:
                                          QuestTypography.bodyMedium.copyWith(
                                        color: QuestColors.osTextPrimary,
                                        height: 1.5,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: QuestSpacing.xl),
                          ],

                          // Appeal submitted — pending after appeal
                          if (status == SubmissionStatus.pending &&
                              submission.appealed) ...[
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(QuestSpacing.md),
                              decoration: _chunkyDecoration(
                                accent: QuestColors.violet,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(Icons.gavel,
                                          color: QuestColors.violet, size: 20),
                                      const SizedBox(width: QuestSpacing.sm),
                                      Expanded(
                                        child: Text(
                                          'APPEAL SUBMITTED',
                                          style: QuestTypography.labelMedium
                                              .copyWith(
                                            color: QuestColors.violet,
                                            letterSpacing: 1.5,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (submission.appealNote != null &&
                                      submission.appealNote!.isNotEmpty) ...[
                                    const SizedBox(height: QuestSpacing.sm),
                                    Text(
                                      submission.appealNote!,
                                      style: QuestTypography.bodySmall.copyWith(
                                        color: QuestColors.osTextSecondary,
                                        fontStyle: FontStyle.italic,
                                        height: 1.5,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(height: QuestSpacing.xl),
                          ],

                          if (isRejected && !submission.appealed) ...[
                            _SectionLabel(
                              AppLocalizations.of(context)!.rejectionReasons,
                            ),
                            const SizedBox(height: QuestSpacing.sm),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(QuestSpacing.md),
                              decoration: _chunkyDecoration(
                                accent: QuestColors.softRed,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  for (var i = 0;
                                      i < rejectionReasons.length;
                                      i++)
                                    Padding(
                                      padding: EdgeInsets.only(
                                        bottom: i == rejectionReasons.length - 1
                                            ? 0
                                            : QuestSpacing.sm,
                                      ),
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Icon(Icons.block,
                                              size: 16,
                                              color: QuestColors.softRed),
                                          const SizedBox(
                                              width: QuestSpacing.sm),
                                          Expanded(
                                            child: Text(
                                              rejectionReasons[i],
                                              style: QuestTypography.bodyMedium
                                                  .copyWith(
                                                color:
                                                    QuestColors.osTextPrimary,
                                                height: 1.5,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(height: QuestSpacing.md),
                            _ChunkyButton(
                              label: 'REQUEST REVALIDATION',
                              onTap: () => _showRevalidationSheet(
                                context,
                                submission.userQuestId,
                                ref,
                              ),
                            ),
                            const SizedBox(height: QuestSpacing.xl),
                          ],

                          if (isRejected && submission.appealed) ...[
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(QuestSpacing.md),
                              decoration: _chunkyDecoration(
                                accent: QuestColors.violet,
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.info_outline,
                                      color: QuestColors.violet, size: 20),
                                  const SizedBox(width: QuestSpacing.sm),
                                  Expanded(
                                    child: Text(
                                      'You already appealed this submission. No further appeals allowed.',
                                      style: QuestTypography.bodySmall.copyWith(
                                        color: QuestColors.osTextPrimary,
                                        height: 1.5,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: QuestSpacing.xl),
                          ],

                          // Submitted timestamp
                          Row(
                            children: [
                              const Icon(Icons.access_time,
                                  size: 14, color: QuestColors.osTextMuted),
                              const SizedBox(width: QuestSpacing.xs),
                              Text(
                                'SUBMITTED ${timeAgoLong(submission.submittedAt).toUpperCase()}',
                                style: QuestTypography.labelSmall.copyWith(
                                  color: QuestColors.osTextMuted,
                                  letterSpacing: 1.2,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: QuestSpacing.xxl),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Chunky Arcade Pop card decoration: white fill, ink outline, hard
  // ink-tinted offset shadow. Pass `accent` to override the border color.
  static BoxDecoration _chunkyDecoration({
    Color? fill,
    Color? accent,
    double radius = QuestSpacing.radiusMd,
  }) {
    return BoxDecoration(
      color: fill ?? QuestColors.osCard,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: accent ?? QuestColors.osBorderStrong,
        width: 2,
      ),
      boxShadow: const [
        BoxShadow(
          color: _inkShadow,
          offset: Offset(2, 3),
          blurRadius: 0,
        ),
      ],
    );
  }

  Color _statusColor(String status) => switch (status) {
        SubmissionStatus.pending => QuestColors.accentYellow,
        SubmissionStatus.approved => QuestColors.successGreen,
        SubmissionStatus.rejected => QuestColors.softRed,
        _ => QuestColors.textMuted,
      };

  IconData _statusIcon(String status) => switch (status) {
        SubmissionStatus.pending => Icons.hourglass_top,
        SubmissionStatus.approved => Icons.check_circle_outline,
        SubmissionStatus.rejected => Icons.cancel_outlined,
        _ => Icons.help_outline,
      };

  List<String> _extractRejectionReasons(String? reviewNote) {
    final note = reviewNote?.trim() ?? '';
    if (note.isEmpty) return const ['No rejection reasons were provided.'];

    final lines = note
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    if (lines.isEmpty) return const ['No rejection reasons were provided.'];

    final cleaned = lines
        .map(
          (line) =>
              line.replaceFirst(RegExp(r'^\s*(?:[-*•]|\d+[.)])\s*'), '').trim(),
        )
        .where((line) => line.isNotEmpty)
        .toList();

    if (cleaned.isEmpty) return const ['No rejection reasons were provided.'];
    return cleaned.take(3).toList();
  }

  Future<void> _showRevalidationSheet(
      BuildContext pageContext, String userQuestId, WidgetRef ref) async {
    if (guardAccountAction(pageContext, ref)) return;
    final messenger = ScaffoldMessenger.of(pageContext);
    final l = AppLocalizations.of(pageContext)!;

    final appealText = await showModalBottomSheet<String>(
      context: pageContext,
      isScrollControlled: true,
      // Force the sheet onto the cream page bg, never the dark surface,
      // so the chunky white card inside reads correctly.
      backgroundColor: QuestColors.osBg,
      barrierColor: QuestColors.pureBlack.withAlpha(120),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(QuestSpacing.radiusLg),
        ),
        side: BorderSide(
          color: QuestColors.osBorderStrong,
          width: 2,
        ),
      ),
      builder: (_) => _RevalidationSheetContent(
        hintText: l.revalidationHint,
        buttonLabel: l.sendRequest,
      ),
    );

    if (appealText == null || appealText.isEmpty) return;
    if (_appealing) return; // ARC-003: ignore re-taps while in flight.
    _appealing = true;

    try {
      await AppBackend.repositories.submissions
          .appealSubmission(submissionId, appealText);
      // Refresh all related providers so UI updates immediately. Includes
      // activeQuestProvider so the home screen flips the appealed quest
      // back into IN REVIEW without a manual refresh.
      ref.invalidate(submissionByIdProvider(submissionId));
      ref.invalidate(userSubmissionsProvider);
      ref.invalidate(questHistoryProvider);
      ref.invalidate(activeQuestProvider);
      messenger.showSnackBar(
        const SnackBar(content: Text('Appeal submitted! Waiting for review.')),
      );
    } catch (e) {
      // ARC-023: route raw Postgres errors through the shared mapper
      // so users don't see exception strings.
      messenger
        ..clearSnackBars()
        ..showSnackBar(SnackBar(
          content: Text(mapDbError(e, action: 'submit appeal')),
        ));
    } finally {
      _appealing = false;
    }
  }
}

/// Extracted as a proper StatefulWidget to avoid the _dependents.isEmpty
/// assertion that occurs when StatefulBuilder + MediaQuery is used inside
/// a bottom sheet that gets dismissed.
class _RevalidationSheetContent extends StatefulWidget {
  const _RevalidationSheetContent({
    required this.hintText,
    required this.buttonLabel,
  });
  final String hintText;
  final String buttonLabel;

  @override
  State<_RevalidationSheetContent> createState() =>
      _RevalidationSheetContentState();
}

class _RevalidationSheetContentState extends State<_RevalidationSheetContent> {
  final _controller = TextEditingController();
  bool _canSubmit = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        QuestSpacing.lg,
        QuestSpacing.lg,
        QuestSpacing.lg,
        QuestSpacing.lg + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Grab handle — small visual affordance that this sheet is
          // dismissable.
          Center(
            child: Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                color: QuestColors.osTextMuted.withAlpha(140),
                borderRadius: BorderRadius.circular(QuestSpacing.radiusFull),
              ),
            ),
          ),
          const SizedBox(height: QuestSpacing.lg),
          // Violet pill icon with hard ink shadow — matches the rest of
          // the chunky Arcade Pop accents.
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: QuestColors.violet,
              shape: BoxShape.circle,
              border: Border.all(
                color: QuestColors.osBorderStrong,
                width: 2,
              ),
              boxShadow: const [
                BoxShadow(
                  color: _inkShadow,
                  offset: Offset(2, 3),
                  blurRadius: 0,
                ),
              ],
            ),
            alignment: Alignment.center,
            child: const Icon(Icons.gavel,
                color: QuestColors.osTextOnPrimary, size: 22),
          ),
          const SizedBox(height: QuestSpacing.md),
          Text(
            'REQUEST REVALIDATION',
            style: QuestTypography.headlineSmall.copyWith(
              color: QuestColors.osTextPrimary,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: QuestSpacing.xs),
          Text(
            'Explain why this submission should be reviewed again.',
            style: QuestTypography.bodySmall.copyWith(
              color: QuestColors.osTextSecondary,
              height: 1.5,
            ),
          ),
          const SizedBox(height: QuestSpacing.lg),
          // Chunky text field — explicit ink text + cursor so input is
          // always visible regardless of theme brightness inference.
          DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(QuestSpacing.radiusMd),
              boxShadow: const [
                BoxShadow(
                  color: _inkShadowSoft,
                  offset: Offset(2, 3),
                  blurRadius: 0,
                ),
              ],
            ),
            child: TextField(
              controller: _controller,
              minLines: 4,
              maxLines: 6,
              autofocus: true,
              cursorColor: QuestColors.violet,
              cursorWidth: 2,
              onChanged: (_) => setState(() {
                _canSubmit = _controller.text.trim().isNotEmpty;
              }),
              style: QuestTypography.bodyMedium.copyWith(
                color: QuestColors.osTextPrimary,
                height: 1.5,
              ),
              decoration: InputDecoration(
                hintText: widget.hintText,
                hintStyle: QuestTypography.bodyMedium.copyWith(
                  color: QuestColors.osTextMuted,
                ),
                filled: true,
                fillColor: QuestColors.osCard,
                contentPadding: const EdgeInsets.all(QuestSpacing.md),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(QuestSpacing.radiusMd),
                  borderSide: const BorderSide(
                    color: QuestColors.osBorderStrong,
                    width: 2,
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(QuestSpacing.radiusMd),
                  borderSide: const BorderSide(
                    color: QuestColors.osBorderStrong,
                    width: 2,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(QuestSpacing.radiusMd),
                  borderSide: const BorderSide(
                    color: QuestColors.violet,
                    width: 2,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: QuestSpacing.lg),
          GestureDetector(
            onTap: _canSubmit
                ? () => Navigator.of(context).pop(_controller.text.trim())
                : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: QuestSpacing.md),
              decoration: BoxDecoration(
                color: _canSubmit
                    ? QuestColors.violet
                    : QuestColors.osTextMuted.withAlpha(80),
                borderRadius: BorderRadius.circular(QuestSpacing.radiusMd),
                border: Border.all(
                  color: QuestColors.osBorderStrong,
                  width: 2,
                ),
                boxShadow: _canSubmit
                    ? const [
                        BoxShadow(
                          color: _inkShadow,
                          offset: Offset(2, 3),
                          blurRadius: 0,
                        ),
                      ]
                    : const [],
              ),
              child: Text(
                widget.buttonLabel.toUpperCase(),
                textAlign: TextAlign.center,
                style: QuestTypography.buttonText.copyWith(
                  color: _canSubmit
                      ? QuestColors.osTextOnPrimary
                      : QuestColors.osTextMuted,
                  letterSpacing: 1.5,
                ),
              ),
            ),
          ),
          const SizedBox(height: QuestSpacing.sm),
          Center(
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: QuestSpacing.sm,
                  horizontal: QuestSpacing.lg,
                ),
                child: Text(
                  'CANCEL',
                  style: QuestTypography.labelMedium.copyWith(
                    color: QuestColors.osTextMuted,
                    letterSpacing: 1.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProofMediaCarousel extends StatefulWidget {
  const _ProofMediaCarousel({required this.submission});
  final SubmissionModel submission;

  @override
  State<_ProofMediaCarousel> createState() => _ProofMediaCarouselState();
}

class _ProofMediaCarouselState extends State<_ProofMediaCarousel> {
  final PageController _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final urls =
        widget.submission.mediaUrls.where((u) => u.isNotEmpty).toList();

    if (urls.isEmpty) {
      return Container(
        width: double.infinity,
        height: 220,
        decoration: BoxDecoration(
          color: QuestColors.cardBg(context),
          borderRadius: BorderRadius.circular(QuestSpacing.radiusMd),
          border: Border.all(color: QuestColors.borderC(context), width: 2),
        ),
        child: Center(
          child: Icon(Icons.image_outlined,
              size: 48, color: QuestColors.textDim(context)),
        ),
      );
    }

    return Column(
      children: [
        SizedBox(
          height: 220,
          child: Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(QuestSpacing.radiusMd),
                child: PageView.builder(
                  controller: _controller,
                  itemCount: urls.length,
                  onPageChanged: (i) => setState(() => _page = i),
                  itemBuilder: (_, i) {
                    final url = urls[i];
                    final isVideo = url.contains('.mp4') ||
                        url.contains('.mov') ||
                        url.contains('.webm') ||
                        (widget.submission.mediaType == MediaType.video &&
                            urls.length == 1);
                    if (isVideo) {
                      return Container(
                        color: QuestColors.cardBg(context),
                        child: const Center(
                          child: Icon(Icons.videocam,
                              size: 52, color: QuestColors.accentYellow),
                        ),
                      );
                    }
                    return Image.network(url,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Center(
                              child: Icon(Icons.image_outlined,
                                  size: 48,
                                  color: QuestColors.textDim(context)),
                            ));
                  },
                ),
              ),
              if (urls.length > 1)
                Positioned(
                  top: QuestSpacing.sm,
                  right: QuestSpacing.sm,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: QuestSpacing.sm, vertical: 3),
                    decoration: BoxDecoration(
                      color: QuestColors.pureBlack.withAlpha(153),
                      borderRadius:
                          BorderRadius.circular(QuestSpacing.radiusFull),
                    ),
                    child: Text(
                      '${_page + 1} / ${urls.length}',
                      style: const TextStyle(
                          color: QuestColors.textPrimary,
                          fontSize: 10,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (urls.length > 1) ...[
          const SizedBox(height: QuestSpacing.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(urls.length, (i) {
              final active = i == _page;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: active ? 16 : 6,
                height: 6,
                decoration: BoxDecoration(
                  color: active ? QuestColors.violet : QuestColors.border,
                  borderRadius: BorderRadius.circular(QuestSpacing.radiusFull),
                ),
              );
            }),
          ),
        ],
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label.toUpperCase(),
      style: QuestTypography.labelMedium.copyWith(
        color: QuestColors.osTextSecondary,
        letterSpacing: 1.4,
        fontWeight: FontWeight.w800,
      ),
    );
  }
}

class _ChunkyButton extends StatefulWidget {
  const _ChunkyButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  State<_ChunkyButton> createState() => _ChunkyButtonState();
}

class _ChunkyButtonState extends State<_ChunkyButton> {
  double _scale = 1.0;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _scale = 0.96),
      onTapCancel: () => setState(() => _scale = 1.0),
      onTapUp: (_) {
        setState(() => _scale = 1.0);
        widget.onTap();
      },
      child: AnimatedScale(
        scale: _scale,
        duration: const Duration(milliseconds: 90),
        curve: Curves.easeOut,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: QuestSpacing.md),
          decoration: BoxDecoration(
            color: QuestColors.violet,
            borderRadius: BorderRadius.circular(QuestSpacing.radiusMd),
            border: Border.all(
              color: QuestColors.osBorderStrong,
              width: 2,
            ),
            boxShadow: const [
              BoxShadow(
                color: _inkShadow,
                offset: Offset(2, 3),
                blurRadius: 0,
              ),
            ],
          ),
          alignment: Alignment.center,
          child: Text(
            widget.label,
            textAlign: TextAlign.center,
            style: QuestTypography.buttonText.copyWith(
              color: QuestColors.osTextOnPrimary,
              letterSpacing: 1.5,
            ),
          ),
        ),
      ),
    );
  }
}
