import 'dart:convert';
import 'package:app_core/app_core.dart';
import 'package:app_repositories/app_repositories.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_contracts/supabase_contracts.dart';

import '../../../../core/providers/supabase_provider.dart';
import '../../../../core/router/admin_route_names.dart';
import '../providers/moderation_controller.dart';
import '../providers/pending_submissions_provider.dart';
import '../widgets/inline_video.dart';

import '../../../../core/theme/bsheel_design.dart';
import '../../../../shared/widgets/bsheel_widgets.dart';

final _submissionDetailProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>?, String>((ref, id) async {
      final client = ref.watch(supabaseClientProvider);
      final data = await client
          .from(Tables.submissions)
          .select(
            '*, profiles!submissions_user_id_fkey(${ProfileColumns.username}, ${ProfileColumns.displayName}, ${ProfileColumns.avatarUrl}, ${ProfileColumns.xp}, ${ProfileColumns.level}), ${Tables.userQuests}(*, ${Tables.quests}(${QuestColumns.title}, ${QuestColumns.description}, ${QuestColumns.category}, ${QuestColumns.difficulty}, ${QuestColumns.xpReward}))',
          )
          .eq(SubmissionColumns.id, id)
          .maybeSingle();
      if (data == null) return null;

      final media = data[SubmissionColumns.mediaUrl]?.toString() ?? '';
      final profile = data['profiles'] as Map<String, dynamic>?;
      final avatar = profile?[ProfileColumns.avatarUrl]?.toString();
      return {
        ...data,
        SubmissionColumns.mediaUrl:
            await SignedMediaUrls.signJsonOrSingle(client, media),
        if (profile != null)
          'profiles': {
            ...profile,
            ProfileColumns.avatarUrl:
                await SignedMediaUrls.signNullable(client, avatar),
          },
      };
    });

/// Checks if this submission is a retake of a previously completed quest.
final _isRetakeProvider = FutureProvider.autoDispose
    .family<bool, String>((ref, submissionId) async {
      final client = ref.watch(supabaseClientProvider);
      try {
        final result = await client.rpc(
          RpcNames.isQuestRetake,
          params: {'p_submission_id': submissionId},
        );
        return result == true;
      } catch (_) {
        return false;
      }
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
            style: BsheelType.bodySm.copyWith(color: BsheelColors.hot),
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

    final profile = data[Tables.profiles] as Map<String, dynamic>?;
    final userQuest = data[Tables.userQuests] as Map<String, dynamic>?;
    final quest = userQuest?[Tables.quests] as Map<String, dynamic>?;

    final username = profile?[ProfileColumns.username] ?? 'Unknown';
    final displayName = profile?[ProfileColumns.displayName] ?? username;
    final userXp = profile?[ProfileColumns.xp] ?? 0;
    final userLevel = profile?[ProfileColumns.level] ?? 1;
    final mediaUrl = (data[SubmissionColumns.mediaUrl] ?? '').toString();
    final mediaType = (data[SubmissionColumns.mediaType] ?? 'image').toString();
    final caption = data[SubmissionColumns.caption] as String?;
    final status = (data[SubmissionColumns.status] ?? '').toString();
    final submittedAt = DateTime.tryParse(
      data[SubmissionColumns.submittedAt]?.toString() ?? '',
    );

    final questTitle = quest?[QuestColumns.title] ?? 'Unknown Quest';
    final questDesc = quest?[QuestColumns.description] ?? '';
    final questCategory = quest?[QuestColumns.category] ?? '';
    final questDifficulty = quest?[QuestColumns.difficulty] ?? '';
    final questXp = quest?[QuestColumns.xpReward] ?? 0;

    final isPending = status == SubmissionStatus.pending;
    final isAppeal = data[SubmissionColumns.appealed] == true;
    final appealNote = data[SubmissionColumns.appealNote] as String?;

    // Check if this submission is part of a collab pair
    final userQuestId = data[SubmissionColumns.userQuestId] as String?;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Hero header with back arrow + collab badge + status pill.
          BsheelCard(
            padding: const EdgeInsets.symmetric(
              horizontal: 36,
              vertical: 28,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_rounded,
                      color: BsheelColors.ink,),
                  onPressed: () =>
                      context.goNamed(AdminRouteNames.pendingSubmissions),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const BsheelEyebrow('Moderation · Review'),
                      const SizedBox(height: 12),
                      BsheelDisplay(
                        'Read it {carefully.}',
                        baseStyle:
                            BsheelType.displayLg.copyWith(fontSize: 36),
                      ),
                    ],
                  ),
                ),
              // Retake badge
              Builder(
                builder: (ctx) {
                  final isRetake = ref.watch(_isRetakeProvider(widget.submissionId)).valueOrNull ?? false;
                  if (!isRetake) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(left: QuestSpacing.sm),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: BsheelColors.surface,
                        borderRadius: BorderRadius.circular(BsheelRadii.lg),
                        border: Border.all(color: BsheelColors.line),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.refresh,
                              size: 12, color: BsheelColors.cool,),
                          const SizedBox(width: 4),
                          Text(
                            'RETAKE',
                            style: BsheelType.labelSm.copyWith(
                              color: BsheelColors.cool,
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                              letterSpacing: 1,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              if (userQuestId != null) ...[
                const SizedBox(width: QuestSpacing.sm),
                _CollabBadgeAsync(
                  userQuestId: userQuestId,
                  submissionId: widget.submissionId,
                ),
              ],
              const Spacer(),
              _StatusChip(status: status),
            ],
          ),
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
                      const Icon(Icons.gavel, size: 20, color: BsheelColors.accent),
                      const SizedBox(width: QuestSpacing.sm),
                      Text(
                        'APPEAL — THIS SUBMISSION WAS PREVIOUSLY REJECTED',
                        style: BsheelType.labelMd.copyWith(
                          color: BsheelColors.ink,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 1,
                        ),
                      ),
                    ],
                  ),
                  if (appealNote != null && appealNote.isNotEmpty) ...[
                    const SizedBox(height: QuestSpacing.md),
                    Text(
                      'USER\'S APPEAL:',
                      style: BsheelType.labelSm.copyWith(
                        color: BsheelColors.inkMuted,
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
                      color: BsheelColors.pureWhite,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: BsheelColors.success,
                    foregroundColor: BsheelColors.pureWhite,
                    padding: const EdgeInsets.symmetric(
                      horizontal: QuestSpacing.xl,
                      vertical: QuestSpacing.md,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(BsheelRadii.full),
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
                      color: BsheelColors.hot,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: BsheelColors.hot,
                    side: const BorderSide(
                      color: BsheelColors.hot,
                      width: BsheelBorders.thin,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: QuestSpacing.xl,
                      vertical: QuestSpacing.md,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(BsheelRadii.full),
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
                return Row(
                  children: [
                    approveBtn,
                    const SizedBox(width: QuestSpacing.md),
                    denyBtn,
                    if (_isActioning) ...[
                      const SizedBox(width: QuestSpacing.md),
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: BsheelColors.primary,
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
          if (!isPending)
            Text(
              'This submission has already been $status.',
              style: BsheelType.bodySm.copyWith(
                color: BsheelColors.inkMuted,
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
      final client = ref.read(supabaseClientProvider);
      // Atomic admin RPC: re-verifies admin status, asserts current state
      // is 'pending' under FOR UPDATE, applies the review_note (if any),
      // and writes an admin_audit_log entry — all in one transaction.
      final params = <String, dynamic>{'p_submission_id': widget.submissionId};
      final trimmedNote = reviewNote.trim();
      if (trimmedNote.isNotEmpty) {
        params['p_review_note'] = trimmedNote;
      }
      await client.rpc(RpcNames.adminApproveSubmission, params: params);

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
      final client = ref.read(supabaseClientProvider);
      await client.rpc(RpcNames.adminRejectSubmission, params: {
        'p_submission_id': widget.submissionId,
        'p_review_note': rejectionNote,
      },);

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
                  color: BsheelColors.line, width: BsheelBorders.thin,),
            ),
            child: Padding(
              padding: const EdgeInsets.all(QuestSpacing.lg),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'DENY SUBMISSION',
                    style: BsheelType.displaySm.copyWith(
                      color: BsheelColors.ink,
                    ),
                  ),
                  const SizedBox(height: QuestSpacing.md),
                  Text(
                    'Provide 1 to 3 rejection reasons. Users will see these as bullet points.',
                    style: BsheelType.bodySm.copyWith(
                      color: BsheelColors.inkMuted,
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
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: Text(
                          'CANCEL',
                          style: BsheelType.labelSm.copyWith(
                            color: BsheelColors.inkMuted,
                          ),
                        ),
                      ),
                      const SizedBox(width: QuestSpacing.sm),
                      ElevatedButton(
                        onPressed: canSubmit
                            ? () {
                                Navigator.pop(ctx);
                                _deny(context, _buildRejectionNote(reasons));
                              }
                            : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: BsheelColors.hot,
                          foregroundColor: BsheelColors.pureWhite,
                          shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(BsheelRadii.full),
                          ),
                        ),
                        child: Text(
                          'DENY',
                          style: BsheelType.labelSm.copyWith(
                            color: BsheelColors.pureWhite,
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
                color: BsheelColors.line, width: BsheelBorders.thin,),
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
                      style: BsheelType.bodyMd.copyWith(
                        fontWeight: FontWeight.w500,
                        color: BsheelColors.ink,
                      ),
                    ),
                    Text(
                      '@$username',
                      style: BsheelType.bodySm.copyWith(
                        color: BsheelColors.inkMuted,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'LEVEL $userLevel',
                    style: BsheelType.labelSm.copyWith(
                      color: BsheelColors.primary,
                    ),
                  ),
                  Text(
                    '$userXp XP',
                    style: BsheelType.labelSm.copyWith(
                      color: BsheelColors.accent,
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
                color: BsheelColors.line, width: BsheelBorders.thin,),
            borderRadius: BorderRadius.circular(BsheelRadii.lg),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'QUEST',
                style: BsheelType.labelSm.copyWith(
                  color: BsheelColors.inkMuted,
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
              color: BsheelColors.inkMuted,
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
              color: BsheelColors.inkMuted,
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
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: BsheelType.labelSm.copyWith(color: color, fontSize: 10),
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
    final (Color bg, Color fg) = switch (status) {
      'approved' => (BsheelColors.success.withAlpha(30), BsheelColors.success),
      'rejected' => (BsheelColors.hot.withAlpha(30), BsheelColors.hot),
      _ => (BsheelColors.cool.withAlpha(30), BsheelColors.cool),
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
            color: fg.withAlpha(100), width: BsheelBorders.thin,),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: fg),
          const SizedBox(width: QuestSpacing.xs),
          Text(
            status.toUpperCase(),
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

/// Async check if this submission is part of a collab pair.
/// [_CollabBadgeAsync] renders a COLLAB (or VERSUS) badge if so.
final _collabGroupProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>?, String>((ref, userQuestId) async {
  final client = ref.watch(supabaseClientProvider);
  final memberRow = await client
      .from(Tables.collabGroupMembers)
      .select(CollabGroupMemberColumns.groupId)
      .eq(CollabGroupMemberColumns.userQuestId, userQuestId)
      .maybeSingle();
  if (memberRow == null) return null;
  final groupId = memberRow[CollabGroupMemberColumns.groupId] as String;
  return await client
      .from(Tables.collabGroups)
      .select()
      .eq(CollabGroupColumns.id, groupId)
      .maybeSingle();
});

class _CollabBadgeAsync extends ConsumerWidget {
  final String userQuestId;
  final String submissionId;

  const _CollabBadgeAsync({
    required this.userQuestId,
    required this.submissionId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pairAsync = ref.watch(_collabGroupProvider(userQuestId));

    return pairAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (pair) {
        if (pair == null) return const SizedBox.shrink();

        final mode = pair[CollabGroupColumns.mode] as String? ?? 'with';
        final isVersus = mode == 'versus';
        final badgeColor = isVersus ? BsheelColors.hot : BsheelColors.ink;
        final badgeLabel = isVersus ? 'VERSUS' : 'COLLAB';

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: badgeColor.withAlpha(20),
                borderRadius: BorderRadius.circular(BsheelRadii.full),
                border: Border.all(color: badgeColor.withAlpha(80)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.group, size: 12, color: badgeColor),
                  const SizedBox(width: 4),
                  Text(
                    badgeLabel,
                    style: BsheelType.labelSm.copyWith(
                      color: badgeColor,
                      fontWeight: FontWeight.w500,
                      fontSize: 10,
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
}
