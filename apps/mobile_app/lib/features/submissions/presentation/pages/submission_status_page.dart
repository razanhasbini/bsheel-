import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:app_core/app_core.dart';
import 'package:app_models/app_models.dart';
import 'package:app_repositories/app_repositories.dart'
    show ApiRealtimeClient, RealtimeDomainEvent;
import 'package:app_contracts/app_contracts.dart';
import 'package:shared_ui/shared_ui.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/utils/account_lock_guard.dart';
import '../../../../core/backend/app_backend.dart';
import '../../../../features/quests/presentation/widgets/arcade_page_chrome.dart';
import '../../data/submission_providers.dart';
import '../../../quests/data/quest_providers.dart';
import '../../../feed/presentation/providers/feed_provider.dart';
import '../../../../l10n/app_localizations.dart';

/// Submission status and the appeal, drawn to
/// `export/mobile/08-submission-rejected.jpg` plus the SUBMISSION · STATE
/// SET panel beside it.
///
/// The verdict is a single full-bleed card whose ground *is* the outcome —
/// coral rejected, jade approved, gold waiting, dashed cream once the
/// decision is final. The appeal composer sits inline underneath with
/// SEND REQUEST on the sticky footer; it used to live in a bottom sheet
/// behind a REQUEST REVALIDATION button, which put the one durable action
/// on this page two taps away.
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

  // ARC-003: gate the appeal RPC against double-submit. The send button can
  // be tapped twice in quick succession on a slow connection, which used to
  // fire two RPCs (the second of which hits "Already appealed" from 0119
  // and surfaced as a raw exception).
  bool _appealing = false;

  final TextEditingController _appealController = TextEditingController();
  final FocusNode _appealFocus = FocusNode();

  String get submissionId => widget.submissionId;

  String? _lastKnownStatus;

  @override
  void initState() {
    super.initState();
    final realtime = _realtime();
    if (realtime == null) return;
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
        _realtime()?.unsubscribeFromPost(submissionId);
      } on Object {
        // The shared socket may already be reconnecting or signed out.
      }
    }
    final subscription = _realtimeSubscription;
    if (subscription != null) unawaited(subscription.cancel());
    _appealController.dispose();
    _appealFocus.dispose();
    super.dispose();
  }

  /// The realtime handle, or null when there is no backend to talk to.
  ///
  /// Live status flips are an enhancement on this page — the verdict is
  /// already in the fetched submission. Resolving this eagerly meant a
  /// cold deep link (or any widget test) threw before painting anything.
  ApiRealtimeClient? _realtime() {
    try {
      return AppBackend.repositories.realtime;
    } on Object {
      return null;
    }
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
            ? 'Submission approved. XP awarded.'
            : rejected
                ? 'Submission rejected. See the reviewer notes below.'
                : 'Submission status updated.';
        messenger.showSnackBar(
          SnackBar(
            content: Text(friendly),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
    if (newStatus != null) _lastKnownStatus = newStatus;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
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

    final submission = submissionAsync.valueOrNull;
    final canAppeal = submission != null &&
        submission.status == SubmissionStatus.rejected &&
        !submission.appealed &&
        submission.deletedAt == null;

    return GestureDetector
        // Tapping the page dismisses the appeal keyboard without stealing
        // taps from the controls inside it.
        (
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: QuestColors.bg(context),
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              ArcadePageHeader(
                title: l.submissionTitle,
                onBack: () {
                  if (Navigator.of(context).canPop()) {
                    context.pop();
                  } else {
                    context.goNamed(RouteNames.home);
                  }
                },
              ),
              Expanded(
                child: RefreshIndicator(
                  color: QuestColors.osPrimary,
                  backgroundColor: QuestColors.osCard,
                  onRefresh: handleRefresh,
                  child: submissionAsync.when(
                    loading: () => const _StatusSkeleton(),
                    error: (e, _) => ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        const SizedBox(height: 80),
                        ArcadeInlineError(
                          title: 'SUBMISSION UNAVAILABLE',
                          subtitle: 'We could not load this submission.',
                          onRetry: () => ref
                              .invalidate(submissionByIdProvider(submissionId)),
                        ),
                      ],
                    ),
                    data: (data) {
                      if (data == null) {
                        return ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: [
                            const SizedBox(height: 100),
                            Center(
                              child: Text(
                                l.submissionNotFound,
                                style: QuestTypography.osBodyMedium,
                              ),
                            ),
                          ],
                        );
                      }
                      return _body(context, data, l, canAppeal);
                    },
                  ),
                ),
              ),
              if (canAppeal)
                ArcadeStickyFooter(
                  child: ArcadeButton(
                    label: l.sendRequest,
                    variant: ArcadeButtonVariant.primary,
                    isLoading: _appealing,
                    onTap: _appealing ? null : _sendAppeal,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body(
    BuildContext context,
    SubmissionModel submission,
    AppLocalizations l,
    bool canAppeal,
  ) {
    final status = submission.status;
    final isRejected = status == SubmissionStatus.rejected;
    final reasons = isRejected
        ? _extractRejectionReasons(submission.reviewNote)
        : const <String>[];
    final caption = submission.caption?.trim() ?? '';
    final note = _prose(submission.reviewNote, reasons);

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        QuestSpacing.screenPadding,
        0,
        QuestSpacing.screenPadding,
        28,
      ),
      children: [
        // ── Verdict ─────────────────────────────────────────────
        _VerdictCard(submission: submission),
        const SizedBox(height: 14),

        // ── Moderator feedback ──────────────────────────────────
        // On a rejection the note is also the source of the reason chips,
        // so it is shown as prose here and tokenised below.
        if (note.isNotEmpty) ...[
          _BlockLabel(l.moderatorFeedback),
          const SizedBox(height: 8),
          _ProseCard(text: note),
          const SizedBox(height: 14),
        ],

        // ── Rejection reasons ───────────────────────────────────
        if (isRejected && reasons.isNotEmpty) ...[
          _BlockLabel(l.rejectionReasons),
          const SizedBox(height: 8),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [for (final r in reasons) _ReasonChip(text: r)],
          ),
          const SizedBox(height: 14),
        ],

        // ── Your proof ──────────────────────────────────────────
        _BlockLabel(l.yourProof),
        const SizedBox(height: 8),
        _ProofRow(submission: submission, caption: caption),
        const SizedBox(height: 14),

        // ── Revalidation request ────────────────────────────────
        if (canAppeal) ...[
          const _BlockLabel('REVALIDATION REQUEST'),
          const SizedBox(height: 8),
          _AppealBox(
            controller: _appealController,
            focusNode: _appealFocus,
            hint: l.revalidationHint,
            enabled: !_appealing,
          ),
          const SizedBox(height: 8),
          Text(
            "You get one appeal. If it's rejected again, the decision is "
            'final.',
            style: QuestTypography.osBodySmall.copyWith(
              color: QuestColors.osTextSecondary,
              fontSize: 12,
              height: 1.5,
            ),
          ),
        ],
      ],
    );
  }

  // ── Appeal ───────────────────────────────────────────────────────────

  Future<void> _sendAppeal() async {
    if (_appealing) return;
    if (guardAccountAction(context, ref)) return;
    final text = _appealController.text.trim();
    final messenger = ScaffoldMessenger.of(context);
    if (text.isEmpty) {
      _appealFocus.requestFocus();
      messenger
        ..clearSnackBars()
        ..showSnackBar(const SnackBar(
          content: Text('Write your revalidation request first.'),
        ));
      return;
    }

    setState(() => _appealing = true);
    try {
      await AppBackend.repositories.submissions
          .appealSubmission(submissionId, text);
      // Refresh all related providers so the UI updates immediately.
      // activeQuestProvider is included so home flips the appealed quest
      // back into IN REVIEW without a manual refresh.
      ref.invalidate(submissionByIdProvider(submissionId));
      ref.invalidate(userSubmissionsProvider);
      ref.invalidate(questHistoryProvider);
      ref.invalidate(activeQuestProvider);
      _appealController.clear();
      messenger.showSnackBar(
        const SnackBar(content: Text('Appeal sent. Back in the review queue.')),
      );
    } catch (e) {
      // ARC-023: route raw Postgres errors through the shared mapper so
      // users don't see exception strings.
      messenger
        ..clearSnackBars()
        ..showSnackBar(SnackBar(
          content: Text(mapDbError(e, action: 'submit appeal')),
        ));
    } finally {
      if (mounted) setState(() => _appealing = false);
    }
  }

  /// The note minus whatever the chip row already shows, so a reason is
  /// never printed twice.
  static String _prose(String? reviewNote, List<String> reasons) {
    final note = reviewNote?.trim() ?? '';
    if (note.isEmpty || reasons.isEmpty) return note;
    final taken = reasons.map((r) => r.toLowerCase()).toSet();
    return note
        .split(RegExp(r'\r?\n'))
        .where((line) => !taken.contains(line.trim().toLowerCase()))
        .join('\n')
        .trim();
  }

  /// Splits a moderator note into up to three short reason chips.
  static List<String> _extractRejectionReasons(String? reviewNote) {
    final note = reviewNote?.trim() ?? '';
    if (note.isEmpty) return const [];

    final lines = note
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    if (lines.length < 2) return const [];

    final cleaned = lines
        .map(
          (line) =>
              line.replaceFirst(RegExp(r'^\s*(?:[-*•]|\d+[.)])\s*'), '').trim(),
        )
        .where((line) => line.isNotEmpty && line.length <= 40)
        .toList();

    return cleaned.take(3).toList();
  }
}

// ══════════════════════════════════════════════════════════════════════════
// PIECES
// ══════════════════════════════════════════════════════════════════════════

class _BlockLabel extends StatelessWidget {
  const _BlockLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: QuestTypography.osLabelMedium.copyWith(
        color: QuestColors.osTextSecondary,
        fontSize: 11,
        letterSpacing: 1.32,
      ),
    );
  }
}

/// The verdict card. Its ground is the outcome, so the state is legible
/// before a word is read.
///
/// | State                       | Ground        | Shape           |
/// |-----------------------------|---------------|-----------------|
/// | rejected, appeal open       | coral         | `r16`, 5px ink  |
/// | approved                    | jade          | `r16`, 5px ink  |
/// | pending (fresh or appealed) | gold          | `r16`, 5px ink  |
/// | rejected after an appeal    | dashed cream  | `r14`, no shadow|
///
/// The final state is the only one drawn dashed: there is nothing left to
/// act on, and a solid card would keep implying there is.
class _VerdictCard extends StatelessWidget {
  const _VerdictCard({required this.submission});
  final SubmissionModel submission;

  @override
  Widget build(BuildContext context) {
    final ink = QuestColors.text(context);
    final status = submission.status;
    final title = (submission.questTitle ?? 'YOUR SUBMISSION').toUpperCase();
    final isFinal = status == SubmissionStatus.rejected && submission.appealed;

    final (String kicker, Color ground) = switch (status) {
      SubmissionStatus.approved => (
          'APPROVED · XP AWARDED',
          QuestColors.osSuccess,
        ),
      SubmissionStatus.rejected when submission.appealed => (
          'RE-REJECTED · FINAL',
          QuestColors.osSurface,
        ),
      SubmissionStatus.rejected => (
          'REJECTED · 1 APPEAL AVAILABLE',
          QuestColors.osRed,
        ),
      SubmissionStatus.pending when submission.appealed => (
          'PENDING · APPEALED',
          QuestColors.osAccent,
        ),
      _ => ('IN REVIEW', QuestColors.osAccent),
    };

    final fg =
        isFinal ? QuestColors.osTextSecondary : QuestColors.onAccent(ground);
    final stamp = submission.reviewedAt != null
        ? 'REVIEWED ${_stamp(submission.reviewedAt!)}'
        : 'SUBMITTED ${_stamp(submission.submittedAt)}';

    final content = Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            kicker,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: QuestTypography.osLabelMedium.copyWith(
              color: fg,
              fontSize: 10,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            title,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: QuestTypography.osDisplaySmall.copyWith(
              color: fg,
              fontSize: 21,
              height: 1.1,
              letterSpacing: -0.63,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            stamp,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: QuestTypography.osLabelMedium.copyWith(
              color: fg,
              fontSize: 10,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );

    if (isFinal) {
      return ArcadeDashedBox(radius: 14, child: content);
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: ground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: ink, width: 2),
        boxShadow: QuestSpacing.shadowLg,
      ),
      child: content,
    );
  }

  /// `12 MAR · 18:04` — the frame's stamp, in the device's local time.
  static String _stamp(DateTime at) {
    const months = [
      'JAN',
      'FEB',
      'MAR',
      'APR',
      'MAY',
      'JUN',
      'JUL',
      'AUG',
      'SEP',
      'OCT',
      'NOV',
      'DEC',
    ];
    final t = at.toLocal();
    final hh = t.hour.toString().padLeft(2, '0');
    final mm = t.minute.toString().padLeft(2, '0');
    return '${t.day} ${months[t.month - 1]} · $hh:$mm';
  }
}

/// White `r13` prose card, 2px ink, 3px ink shadow, `13 / 14` padding.
class _ProseCard extends StatelessWidget {
  const _ProseCard({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final ink = QuestColors.text(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        color: QuestColors.osCard,
        borderRadius: BorderRadius.circular(QuestSpacing.radiusPanel),
        border: Border.all(color: ink, width: 2),
        boxShadow: QuestSpacing.shadowSm,
      ),
      child: Text(
        text,
        style: QuestTypography.osBodyMedium.copyWith(
          fontSize: 14,
          height: 1.55,
        ),
      ),
    );
  }
}

/// A rejection reason: white, `r8`, 2px ink, mono 10. Square-ish so it
/// reads as a tag rather than a status pill.
class _ReasonChip extends StatelessWidget {
  const _ReasonChip({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final ink = QuestColors.text(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: QuestColors.osCard,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: ink, width: 2),
      ),
      child: Text(
        text.toUpperCase(),
        style: QuestTypography.osLabelMedium.copyWith(
          color: QuestColors.osTextPrimary,
          fontSize: 10,
          letterSpacing: 0.7,
        ),
      ),
    );
  }
}

/// `96 x 118` proof thumb with the caption beside it. Tapping opens the
/// full-size viewer; a mono counter marks a multi-file submission.
class _ProofRow extends StatelessWidget {
  const _ProofRow({required this.submission, required this.caption});
  final SubmissionModel submission;
  final String caption;

  @override
  Widget build(BuildContext context) {
    final ink = QuestColors.text(context);
    final urls = submission.mediaUrls.where((u) => u.isNotEmpty).toList();
    final isVideo = submission.mediaType == MediaType.video;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: urls.isEmpty ? null : () => _openViewer(context, urls),
          behavior: HitTestBehavior.opaque,
          child: Container(
            width: 96,
            height: 118,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: ink, width: 2),
              boxShadow: QuestSpacing.shadowSm,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  const ArcadeHatch(),
                  if (urls.isNotEmpty && !isVideo)
                    Image.network(
                      urls.first,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    ),
                  if (isVideo)
                    Center(
                      child: Icon(
                        Icons.play_arrow_rounded,
                        color: ink,
                        size: 30,
                      ),
                    ),
                  if (urls.length > 1)
                    Positioned(
                      right: 6,
                      bottom: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: QuestColors.osBg,
                          borderRadius:
                              BorderRadius.circular(QuestSpacing.radiusBadge),
                          border: Border.all(color: ink, width: 2),
                        ),
                        child: Text(
                          '${urls.length}',
                          style: QuestTypography.osLabelSmall.copyWith(
                            color: QuestColors.osTextPrimary,
                            fontSize: 9,
                            height: 1.2,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            caption.isEmpty ? 'No caption.' : '"$caption"',
            style: QuestTypography.osBodySmall.copyWith(
              color: QuestColors.osTextSecondary,
              fontSize: 13,
              height: 1.55,
            ),
          ),
        ),
      ],
    );
  }

  void _openViewer(BuildContext context, List<String> urls) {
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        builder: (_) => _ProofViewer(urls: urls),
      ),
    );
  }
}

/// The appeal composer: white `r13`, 2px ink, 3px ink shadow, a 76pt floor.
class _AppealBox extends StatelessWidget {
  const _AppealBox({
    required this.controller,
    required this.focusNode,
    required this.hint,
    required this.enabled,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String hint;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final ink = QuestColors.text(context);
    return Container(
      constraints: const BoxConstraints(minHeight: 76),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        color: QuestColors.osCard,
        borderRadius: BorderRadius.circular(QuestSpacing.radiusPanel),
        border: Border.all(color: ink, width: 2),
        boxShadow: QuestSpacing.shadowSm,
      ),
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        enabled: enabled,
        minLines: 2,
        maxLines: 6,
        maxLength: 600,
        cursorColor: QuestColors.osPrimary,
        style: QuestTypography.osBodyMedium.copyWith(
          fontSize: 14,
          height: 1.55,
        ),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: QuestTypography.osBodyMedium.copyWith(
            color: QuestColors.osTextMuted,
            fontSize: 14,
            height: 1.55,
          ),
          isDense: true,
          filled: false,
          counterText: '',
          contentPadding: EdgeInsets.zero,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          disabledBorder: InputBorder.none,
        ),
      ),
    );
  }
}

/// Full-size proof viewer. Not in any frame — a utility surface reached by
/// tapping the thumb.
class _ProofViewer extends StatefulWidget {
  const _ProofViewer({required this.urls});
  final List<String> urls;

  @override
  State<_ProofViewer> createState() => _ProofViewerState();
}

class _ProofViewerState extends State<_ProofViewer> {
  final PageController _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: QuestColors.pureBlack,
      body: Stack(
        children: [
          PageView.builder(
            controller: _controller,
            itemCount: widget.urls.length,
            onPageChanged: (i) => setState(() => _page = i),
            itemBuilder: (_, i) => InteractiveViewer(
              minScale: 1,
              maxScale: 4,
              child: Center(
                child: Image.network(
                  widget.urls[i],
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const ArcadeSkeleton(
                    width: 240,
                    height: 320,
                    radius: 12,
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: MediaQuery.viewPaddingOf(context).top + 8,
            left: 12,
            child: ArcadeIconTile(
              icon: Icons.close_rounded,
              semanticLabel: 'Close',
              onTap: () => Navigator.of(context).maybePop(),
            ),
          ),
          if (widget.urls.length > 1)
            Positioned(
              top: MediaQuery.viewPaddingOf(context).top + 8,
              right: 12,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: QuestColors.osBg,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: QuestColors.osTextPrimary,
                    width: 2,
                  ),
                ),
                child: Text(
                  '${_page + 1} / ${widget.urls.length}',
                  style: QuestTypography.osLabelMedium.copyWith(fontSize: 10),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _StatusSkeleton extends StatelessWidget {
  const _StatusSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(
        horizontal: QuestSpacing.screenPadding,
      ),
      children: const [
        ArcadeSkeleton(height: 150, radius: 16),
        SizedBox(height: 14),
        ArcadeSkeleton(width: 160, height: 11, radius: 4, bordered: false),
        SizedBox(height: 8),
        ArcadeSkeleton(height: 92, radius: 13),
        SizedBox(height: 14),
        ArcadeSkeleton(width: 130, height: 11, radius: 4, bordered: false),
        SizedBox(height: 8),
        ArcadeSkeleton(height: 118, radius: 12),
      ],
    );
  }
}
