import 'dart:convert';
import 'package:app_core/app_core.dart';
import 'package:app_contracts/app_contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/backend/app_backend.dart';
import '../../../../core/router/admin_route_names.dart';
import '../providers/moderation_controller.dart';
import '../providers/pending_submissions_provider.dart';
import '../widgets/inline_video.dart';

import '../../../../core/theme/bsheel_design.dart';
import '../../../../shared/widgets/bsheel_widgets.dart';

/// Full review context in one request: the submission, the author's
/// profile, the quest, and the retake flag. Media and avatar arrive signed.
final _submissionDetailProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>?, String>((ref, id) async {
  return AppBackend.repositories.moderation.reviewDetail(id);
});

class SubmissionReviewPage extends ConsumerWidget {
  final String submissionId;
  const SubmissionReviewPage({super.key, required this.submissionId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(_submissionDetailProvider(submissionId));

    return Padding(
      padding: const EdgeInsets.all(QuestSpacing.lg),
      child: detailAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: BsheelColors.primary),
        ),
        error: (e, _) => Center(
          child: Text(
            'Error: $e',
            textAlign: TextAlign.center,
            style: BsheelType.bodySm.copyWith(
              color: BsheelColors.onCream(BsheelColors.danger),
            ),
          ),
        ),
        data: (data) {
          if (data == null) {
            return Center(
              child: Text(
                'Submission not found.',
                style: BsheelType.bodyMd.copyWith(
                  color: BsheelColors.inkMuted,
                ),
              ),
            );
          }
          return _ReviewContent(data: data, submissionId: submissionId);
        },
      ),
    );
  }
}

class _ReviewContent extends ConsumerStatefulWidget {
  final Map<String, dynamic> data;
  final String submissionId;

  const _ReviewContent({required this.data, required this.submissionId});

  @override
  ConsumerState<_ReviewContent> createState() => _ReviewContentState();
}

class _ReviewContentState extends ConsumerState<_ReviewContent> {
  bool _isActioning = false;

  @override
  Widget build(BuildContext context) {
    final data = widget.data;

    final username = data['username'] ?? 'Unknown';
    final displayName = data['display_name'] ?? username;
    final userXp = data['xp'] ?? 0;
    final userLevel = data['level'] ?? 1;
    final mediaUrl = (data['media_url'] ?? '').toString();
    final mediaType = (data['media_type'] ?? 'image').toString();
    final caption = data['caption'] as String?;
    final status = (data['status'] ?? '').toString();
    final submittedAt = DateTime.tryParse(
      data['submitted_at']?.toString() ?? '',
    );

    final questTitle = data['quest_title'] ?? 'Unknown Quest';
    final questDesc = data['quest_description'] ?? '';
    final questCategory = data['quest_category'] ?? '';
    final questDifficulty = data['quest_difficulty'] ?? '';
    final questXp = data['quest_xp_reward'] ?? 0;

    final isPending = status == SubmissionStatus.pending;
    final isAppeal = data['appealed'] == true;
    final appealNote = data['appeal_note'] as String?;

    // Check if this submission is part of a collab pair
    final collabGroupId = data['collab_group_id']?.toString();
    final collabMode = data['collab_mode']?.toString();

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Hero header with back arrow + collab badge + status pill.
          LayoutBuilder(
            builder: (context, c) {
              final narrow = c.maxWidth < 720;
              final badges = Wrap(
                spacing: QuestSpacing.sm,
                runSpacing: QuestSpacing.sm,
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (data['is_retake'] == true) const _RetakeBadge(),
                  if (collabGroupId != null)
                    _CollabBadge(mode: collabMode ?? 'with'),
                  _StatusChip(status: status),
                ],
              );

              final headline = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const BsheelEyebrow('Moderation · Review'),
                  const SizedBox(height: 12),
                  BsheelDisplay(
                    'Read it {carefully.}',
                    baseStyle: BsheelType.displayLg.copyWith(
                      fontSize: narrow ? 26 : 36,
                    ),
                  ),
                ],
              );

              return BsheelCard(
                padding: EdgeInsets.symmetric(
                  horizontal: narrow ? 20 : 36,
                  vertical: narrow ? 20 : 28,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        IconButton(
                          icon: const Icon(
                            Icons.arrow_back_rounded,
                            color: BsheelColors.ink,
                          ),
                          tooltip: 'Back to the queue',
                          onPressed: () => context
                              .goNamed(AdminRouteNames.pendingSubmissions),
                        ),
                        const SizedBox(width: 8),
                        Expanded(child: headline),
                        if (!narrow) ...[
                          const SizedBox(width: QuestSpacing.md),
                          Flexible(child: badges),
                        ],
                      ],
                    ),
                    if (narrow) ...[
                      const SizedBox(height: 14),
                      badges,
                    ],
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 24),

          // Appeal banner
          if (isAppeal) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(QuestSpacing.lg),
              decoration: BoxDecoration(
                color: BsheelColors.surface,
                borderRadius: BorderRadius.circular(BsheelRadii.md),
                border: Border.all(
                  color: BsheelColors.line,
                  width: BsheelBorders.thin,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.gavel,
                        size: 20,
                        color: BsheelColors.onCream(BsheelColors.accent),
                      ),
                      const SizedBox(width: QuestSpacing.sm),
                      Expanded(
                        child: Text(
                          'APPEAL — THIS SUBMISSION WAS PREVIOUSLY REJECTED',
                          style: BsheelType.labelMd.copyWith(
                            color: BsheelColors.ink,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (appealNote != null && appealNote.isNotEmpty) ...[
                    const SizedBox(height: QuestSpacing.md),
                    Text(
                      'USER\'S APPEAL:',
                      style: BsheelType.labelSm.copyWith(
                        color: BsheelColors.inkSoft,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: QuestSpacing.xs),
                    Text(
                      '"$appealNote"',
                      style: BsheelType.bodyMd.copyWith(
                        color: BsheelColors.inkSoft,
                        fontStyle: FontStyle.italic,
                        height: 1.5,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: QuestSpacing.lg),
          ],

          LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth > 800;
              final imageWidget = _MediaSection(
                mediaUrl: mediaUrl,
                mediaType: mediaType,
              );
              final detailsWidget = _DetailsSection(
                username: username,
                displayName: displayName,
                userXp: userXp,
                userLevel: userLevel,
                caption: caption,
                submittedAt: submittedAt,
                questTitle: questTitle,
                questDesc: questDesc,
                questCategory: questCategory,
                questDifficulty: questDifficulty,
                questXp: questXp,
              );

              if (wide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 3, child: imageWidget),
                    const SizedBox(width: QuestSpacing.xl),
                    Expanded(flex: 2, child: detailsWidget),
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  imageWidget,
                  const SizedBox(height: QuestSpacing.lg),
                  detailsWidget,
                ],
              );
            },
          ),

          const SizedBox(height: QuestSpacing.xl),

          if (isPending)
            LayoutBuilder(
              builder: (context, constraints) {
                final isMobile = constraints.maxWidth < 600;
                final approveBtn = ElevatedButton.icon(
                  onPressed: _isActioning ? null : () => _approve(context),
                  icon: const Icon(Icons.check),
                  label: Text(
                    'APPROVE',
                    style: BsheelType.labelSm.copyWith(
                      color: BsheelColors.onAccent(BsheelColors.success),
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: BsheelColors.success,
                    foregroundColor:
                        BsheelColors.onAccent(BsheelColors.success),
                    padding: const EdgeInsets.symmetric(
                      horizontal: QuestSpacing.xl,
                      vertical: QuestSpacing.md,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(BsheelRadii.full),
                    ),
                  ),
                );
                final denyBtn = OutlinedButton.icon(
                  onPressed:
                      _isActioning ? null : () => _showDenyDialog(context),
                  icon: const Icon(Icons.close),
                  label: Text(
                    'DENY',
                    style: BsheelType.labelSm.copyWith(
                      color: BsheelColors.onCream(BsheelColors.danger),
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: BsheelColors.onCream(BsheelColors.danger),
                    side: const BorderSide(
                      color: BsheelColors.danger,
                      width: BsheelBorders.thin,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: QuestSpacing.xl,
                      vertical: QuestSpacing.md,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(BsheelRadii.full),
                    ),
                  ),
                );
                if (isMobile) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      approveBtn,
                      const SizedBox(height: QuestSpacing.sm),
                      denyBtn,
                      if (_isActioning) ...[
                        const SizedBox(height: QuestSpacing.md),
                        const Center(
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: BsheelColors.primary,
                            ),
                          ),
                        ),
                      ],
                    ],
                  );
                }
                return Wrap(
                  spacing: QuestSpacing.md,
                  runSpacing: QuestSpacing.sm,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    approveBtn,
                    denyBtn,
                    if (_isActioning)
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: BsheelColors.primary,
                        ),
                      ),
                  ],
                );
              },
            ),
          if (!isPending)
            Text(
              'This submission has already been $status.',
              style: BsheelType.bodySm.copyWith(
                color: BsheelColors.inkSoft,
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _approve(BuildContext context) async {
    // Show optional review note dialog
    final reviewNote = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final controller = TextEditingController();
        return AlertDialog(
          backgroundColor: BsheelColors.paper,
          title: const Text('Approve Submission', style: BsheelType.displaySm),
          content: TextField(
            controller: controller,
            maxLines: 3,
            style: BsheelType.bodyMd,
            decoration: const InputDecoration(
              hintText: 'Optional review note for the user...',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('CANCEL'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, controller.text),
              style: ElevatedButton.styleFrom(
                backgroundColor: BsheelColors.primary,
                foregroundColor: BsheelColors.pureWhite,
              ),
              child: const Text('APPROVE'),
            ),
          ],
        );
      },
    );
    if (reviewNote == null) return; // cancelled

    setState(() => _isActioning = true);
    try {
      // Atomic on the API: it re-checks the moderator's role, asserts the
      // submission is still pending under FOR UPDATE, awards XP once,
      // applies the review note and writes an audit record — one transaction.
      final trimmedNote = reviewNote.trim();
      await AppBackend.repositories.moderation.approveSubmission(
        widget.submissionId,
        '',
        note: trimmedNote.isEmpty ? null : trimmedNote,
      );

      ref.invalidate(pendingSubmissionsProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Submission approved.')),
        );
        context.goNamed(AdminRouteNames.pendingSubmissions);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(mapModerationError(e, action: 'approve'))),
        );
      }
    } finally {
      if (mounted) setState(() => _isActioning = false);
    }
  }

  Future<void> _deny(BuildContext context, String note) async {
    final rejectionNote = note.trim();
    if (rejectionNote.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please provide at least one rejection reason.'),
          ),
        );
      }
      return;
    }

    setState(() => _isActioning = true);
    try {
      await AppBackend.repositories.moderation.rejectSubmission(
        widget.submissionId,
        '',
        note: rejectionNote,
      );

      ref.invalidate(pendingSubmissionsProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Submission denied.')),
        );
        context.goNamed(AdminRouteNames.pendingSubmissions);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(mapModerationError(e, action: 'reject'))),
        );
      }
    } finally {
      if (mounted) setState(() => _isActioning = false);
    }
  }

  void _showDenyDialog(BuildContext context) {
    final reason1Controller = TextEditingController();
    final reason2Controller = TextEditingController();
    final reason3Controller = TextEditingController();

    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final reasons = _collectRejectionReasons([
            reason1Controller.text,
            reason2Controller.text,
            reason3Controller.text,
          ]);
          final canSubmit = reasons.isNotEmpty;

          return Dialog(
            backgroundColor: BsheelColors.paper,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(BsheelRadii.xl),
              side: const BorderSide(
                color: BsheelColors.line,
                width: BsheelBorders.thin,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(QuestSpacing.lg),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'DENY SUBMISSION',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: BsheelType.displaySm.copyWith(
                      color: BsheelColors.ink,
                    ),
                  ),
                  const SizedBox(height: QuestSpacing.md),
                  Text(
                    'Provide 1 to 3 rejection reasons. Users will see these '
                    'as bullet points.',
                    style: BsheelType.bodySm.copyWith(
                      color: BsheelColors.inkSoft,
                    ),
                  ),
                  const SizedBox(height: QuestSpacing.md),
                  BsheelTextField(
                    controller: reason1Controller,
                    label: 'REASON 1 (REQUIRED)',
                    onChanged: (_) => setDialogState(() {}),
                  ),
                  const SizedBox(height: QuestSpacing.sm),
                  BsheelTextField(
                    controller: reason2Controller,
                    label: 'REASON 2 (OPTIONAL)',
                    onChanged: (_) => setDialogState(() {}),
                  ),
                  const SizedBox(height: QuestSpacing.sm),
                  BsheelTextField(
                    controller: reason3Controller,
                    label: 'REASON 3 (OPTIONAL)',
                    onChanged: (_) => setDialogState(() {}),
                  ),
                  const SizedBox(height: QuestSpacing.lg),
                  Wrap(
                    alignment: WrapAlignment.end,
                    spacing: QuestSpacing.sm,
                    runSpacing: QuestSpacing.sm,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: Text(
                          'CANCEL',
                          style: BsheelType.labelSm.copyWith(
                            color: BsheelColors.inkSoft,
                          ),
                        ),
                      ),
                      ElevatedButton(
                        onPressed: canSubmit
                            ? () {
                                Navigator.pop(ctx);
                                _deny(context, _buildRejectionNote(reasons));
                              }
                            : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: BsheelColors.danger,
                          foregroundColor:
                              BsheelColors.onAccent(BsheelColors.danger),
                          shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(BsheelRadii.full),
                          ),
                        ),
                        child: Text(
                          'DENY',
                          style: BsheelType.labelSm.copyWith(
                            color: BsheelColors.onAccent(BsheelColors.danger),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    ).whenComplete(() {
      reason1Controller.dispose();
      reason2Controller.dispose();
      reason3Controller.dispose();
    });
  }

  List<String> _collectRejectionReasons(List<String> rawReasons) {
    return rawReasons
        .map((r) => r.trim())
        .where((r) => r.isNotEmpty)
        .take(3)
        .toList();
  }

  String _buildRejectionNote(List<String> reasons) {
    return reasons.map((r) => '• $r').join('\n');
  }
}

class _MediaSection extends StatelessWidget {
  final String mediaUrl;
  final String mediaType;

  const _MediaSection({required this.mediaUrl, required this.mediaType});

  List<String> get _urls {
    final trimmed = mediaUrl.trim();
    if (trimmed.startsWith('[')) {
      try {
        final list = (jsonDecode(trimmed) as List).cast<String>();
        return list.where((u) => u.isNotEmpty).toList();
      } catch (_) {}
    }
    return [trimmed];
  }

  bool _isVideoUrl(String url) {
    final l = url.toLowerCase();
    return l.endsWith('.mp4') ||
        l.endsWith('.mov') ||
        l.endsWith('.webm') ||
        l.endsWith('.m4v');
  }

  @override
  Widget build(BuildContext context) {
    final urls = _urls;

    return Column(
      children: urls.map((url) {
        if (_isVideoUrl(url) || (mediaType == 'video' && urls.length == 1)) {
          return Padding(
            padding: const EdgeInsets.only(bottom: QuestSpacing.md),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 480),
              child: InlineVideo(url: url),
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.only(bottom: QuestSpacing.md),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 500),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(BsheelRadii.md),
              child: Image.network(
                url,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => Container(
                  height: 300,
                  decoration: BoxDecoration(
                    color: BsheelColors.ink,
                    borderRadius: BorderRadius.circular(BsheelRadii.md),
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.broken_image,
                      size: 64,
                      color: BsheelColors.inkMuted,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _DetailsSection extends StatelessWidget {
  final String username;
  final String displayName;
  final dynamic userXp;
  final dynamic userLevel;
  final String? caption;
  final DateTime? submittedAt;
  final String questTitle;
  final String questDesc;
  final String questCategory;
  final String questDifficulty;
  final dynamic questXp;

  const _DetailsSection({
    required this.username,
    required this.displayName,
    required this.userXp,
    required this.userLevel,
    required this.caption,
    required this.submittedAt,
    required this.questTitle,
    required this.questDesc,
    required this.questCategory,
    required this.questDifficulty,
    required this.questXp,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // User info card
        Container(
          padding: const EdgeInsets.all(QuestSpacing.md),
          decoration: BoxDecoration(
            color: BsheelColors.paper,
            border: Border.all(
              color: BsheelColors.line,
              width: BsheelBorders.thin,
            ),
            borderRadius: BorderRadius.circular(BsheelRadii.lg),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: BsheelColors.surface,
                child: Text(
                  displayName.isNotEmpty ? displayName[0].toUpperCase() : '?',
                  style: BsheelType.labelMd.copyWith(
                    color: BsheelColors.ink,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(width: QuestSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: BsheelType.bodyMd.copyWith(
                        fontWeight: FontWeight.w500,
                        color: BsheelColors.ink,
                      ),
                    ),
                    Text(
                      '@$username',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: BsheelType.bodySm.copyWith(
                        color: BsheelColors.inkSoft,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: QuestSpacing.sm),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'LEVEL $userLevel',
                    maxLines: 1,
                    style: BsheelType.labelSm.copyWith(
                      color: BsheelColors.primary,
                    ),
                  ),
                  Text(
                    '$userXp XP',
                    maxLines: 1,
                    style: BsheelType.labelSm.copyWith(
                      // Gold is 1.6:1 as 9px type on cream — text twin.
                      color: BsheelColors.onCream(BsheelColors.accent),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: QuestSpacing.md),

        // Quest info card
        Container(
          padding: const EdgeInsets.all(QuestSpacing.md),
          decoration: BoxDecoration(
            color: BsheelColors.paper,
            border: Border.all(
              color: BsheelColors.line,
              width: BsheelBorders.thin,
            ),
            borderRadius: BorderRadius.circular(BsheelRadii.lg),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'QUEST',
                style: BsheelType.labelSm.copyWith(
                  color: BsheelColors.inkSoft,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: QuestSpacing.xs),
              Text(
                questTitle,
                style: BsheelType.bodyMd.copyWith(
                  fontWeight: FontWeight.w500,
                  color: BsheelColors.ink,
                ),
              ),
              if (questDesc.isNotEmpty) ...[
                const SizedBox(height: QuestSpacing.sm),
                Text(
                  questDesc,
                  style: BsheelType.bodySm.copyWith(
                    color: BsheelColors.inkSoft,
                  ),
                ),
              ],
              const SizedBox(height: QuestSpacing.sm),
              Wrap(
                spacing: QuestSpacing.sm,
                runSpacing: QuestSpacing.sm,
                children: [
                  if (questCategory.isNotEmpty)
                    _InfoChip(
                      label: questCategory.toUpperCase(),
                      color: BsheelColors.cool,
                    ),
                  if (questDifficulty.isNotEmpty)
                    _InfoChip(
                      label: questDifficulty.toUpperCase(),
                      color: BsheelColors.accent,
                    ),
                  _InfoChip(
                    label: '$questXp XP',
                    color: BsheelColors.primary,
                    icon: Icons.bolt,
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: QuestSpacing.md),

        if (caption != null && caption!.isNotEmpty) ...[
          Text(
            'CAPTION',
            style: BsheelType.labelSm.copyWith(
              color: BsheelColors.inkSoft,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: QuestSpacing.xs),
          Text(
            caption!,
            style: BsheelType.bodyMd.copyWith(color: BsheelColors.ink),
          ),
          const SizedBox(height: QuestSpacing.md),
        ],

        if (submittedAt != null)
          Text(
            'SUBMITTED: ${submittedAt!.year}-${submittedAt!.month.toString().padLeft(2, '0')}-${submittedAt!.day.toString().padLeft(2, '0')} ${submittedAt!.hour.toString().padLeft(2, '0')}:${submittedAt!.minute.toString().padLeft(2, '0')}',
            style: BsheelType.labelSm.copyWith(
              color: BsheelColors.inkSoft,
            ),
          ),
      ],
    );
  }
}

class _InfoChip extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;

  const _InfoChip({required this.label, required this.color, this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: QuestSpacing.sm,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(BsheelRadii.full),
        border: Border.all(color: color.withAlpha(80)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: BsheelColors.onCream(color)),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: BsheelType.labelSm.copyWith(
                // The chip fill is a 12% tint, so the label is drawn on
                // what is effectively cream — accent fills fail there.
                color: BsheelColors.onCream(color),
                fontSize: 10,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    // The pill ground is a 12% tint of the accent, i.e. effectively cream:
    // the label takes the accent's text twin, the outline the accent itself.
    final (Color bg, Color fg, Color line) = switch (status) {
      'approved' => (
          BsheelColors.success.withAlpha(30),
          BsheelColors.onCream(BsheelColors.success),
          BsheelColors.success,
        ),
      'rejected' => (
          BsheelColors.danger.withAlpha(30),
          BsheelColors.onCream(BsheelColors.danger),
          BsheelColors.danger,
        ),
      _ => (
          BsheelColors.cool.withAlpha(30),
          BsheelColors.onCream(BsheelColors.cool),
          BsheelColors.cool,
        ),
    };
    final icon = switch (status) {
      'approved' => Icons.check_circle,
      'rejected' => Icons.cancel,
      _ => Icons.pending,
    };

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: QuestSpacing.md,
        vertical: QuestSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(BsheelRadii.full),
        border: Border.all(
          color: line,
          width: BsheelBorders.thin,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: fg),
          const SizedBox(width: QuestSpacing.xs),
          Text(
            status.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: BsheelType.labelSm.copyWith(
              color: fg,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

/// Collab context arrives with the review detail, so the badge no longer
/// issues its own request — the old one was scoped to the signed-in user
/// and returned nothing when a moderator reviewed somebody else's post.
class _CollabBadge extends StatelessWidget {
  const _CollabBadge({required this.mode});

  /// `with` or `versus`, from the review detail payload.
  final String mode;

  @override
  Widget build(BuildContext context) {
    final isVersus = mode == 'versus';
    final badgeColor = isVersus ? BsheelColors.danger : BsheelColors.ink;
    final badgeInk = BsheelColors.onCream(badgeColor);
    final badgeLabel = isVersus ? 'VERSUS' : 'COLLAB';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: badgeColor.withAlpha(20),
        borderRadius: BorderRadius.circular(BsheelRadii.full),
        border: Border.all(color: badgeColor.withAlpha(80)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.group, size: 12, color: badgeInk),
          const SizedBox(width: 4),
          Text(
            badgeLabel,
            maxLines: 1,
            style: BsheelType.labelSm.copyWith(
              color: badgeInk,
              fontWeight: FontWeight.w500,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}

/// Retake marker — a submission the user re-shot after a rejection.
class _RetakeBadge extends StatelessWidget {
  const _RetakeBadge();

  @override
  Widget build(BuildContext context) {
    // Sky is 1.9:1 as 10px type on cream, so the label takes its twin.
    final ink = BsheelColors.onCream(BsheelColors.cool);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: BsheelColors.surface,
        borderRadius: BorderRadius.circular(BsheelRadii.lg),
        border: Border.all(color: BsheelColors.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.refresh, size: 12, color: ink),
          const SizedBox(width: 4),
          Text(
            'RETAKE',
            maxLines: 1,
            style: BsheelType.labelSm.copyWith(
              color: ink,
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
