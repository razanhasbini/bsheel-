import 'dart:async';
import 'dart:convert';
import 'package:app_core/app_core.dart';
import 'package:app_repositories/app_repositories.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_contracts/supabase_contracts.dart';

import '../../../../core/providers/supabase_provider.dart';

import '../../../../core/theme/bsheel_design.dart';
import '../../../../shared/widgets/bsheel_widgets.dart';
import '../../../moderation/presentation/widgets/inline_video.dart';
// ARC-014: cap to the 200 most-recent approved submissions. The full
// list grows unbounded as users post; without a limit this stalls the
// page once a few thousand approved posts exist (each with joined
// profile + user_quest + quest payload). 200 covers >95% of admin
// review needs; the search field is the path for older rows.
const int _adminFeedListLimit = 200;

final _feedPostsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final client = ref.watch(supabaseClientProvider);
  final data = await client
      .from(Tables.submissions)
      .select(
        '*, profiles!submissions_user_id_fkey(${ProfileColumns.username}, ${ProfileColumns.displayName}), ${Tables.userQuests}(${Tables.quests}(${QuestColumns.title}, ${QuestColumns.category}))',
      )
      .eq(SubmissionColumns.status, SubmissionStatus.approved)
      .order(SubmissionColumns.submittedAt, ascending: false)
      .limit(_adminFeedListLimit);
  // Security PR #52: media URLs in the DB are now private R2 keys.
  // Sign each one before handing to the UI so the existing img tags
  // can fetch the bytes via the worker's /media/* endpoint. The page
  // limit is preserved so a 10k+ feed table doesn't OOM the browser.
  return Future.wait(
    List<Map<String, dynamic>>.from(data as List).map((post) async {
      final rawMedia = post[SubmissionColumns.mediaUrl]?.toString() ?? '';
      return {
        ...post,
        SubmissionColumns.mediaUrl:
            await SignedMediaUrls.signJsonOrSingle(client, rawMedia),
      };
    }),
  );
});

class FeedManagementPage extends ConsumerStatefulWidget {
  const FeedManagementPage({super.key});

  @override
  ConsumerState<FeedManagementPage> createState() =>
      _FeedManagementPageState();
}

class _FeedManagementPageState extends ConsumerState<FeedManagementPage> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final postsAsync = ref.watch(_feedPostsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BsheelCard(
          padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const BsheelEyebrow('Content · Feed'),
              const SizedBox(height: 14),
              BsheelDisplay(
                'Curate the {feed.}',
                baseStyle: BsheelType.displayXl.copyWith(fontSize: 44),
              ),
              const SizedBox(height: 12),
              Text(
                'Manage approved feed posts. Remove anything that breaks '
                'community guidelines.',
                style: BsheelType.bodyMd
                    .copyWith(color: BsheelColors.inkSoft),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: TextField(
            style: BsheelType.bodySm,
            decoration: InputDecoration(
              hintText: 'Search by username or caption...',
              hintStyle: BsheelType.bodySm.copyWith(
                color: BsheelColors.inkMuted,
              ),
              prefixIcon: const Icon(Icons.search, color: BsheelColors.inkMuted),
              filled: true,
              fillColor: BsheelColors.paper,
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(BsheelRadii.sm),
                borderSide: const BorderSide(color: BsheelColors.ink),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(BsheelRadii.sm),
                borderSide: const BorderSide(color: BsheelColors.ink, width: 1),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(BsheelRadii.sm),
                borderSide:
                    const BorderSide(color: BsheelColors.primary, width: 1),
              ),
            ),
            onChanged: (v) => setState(() => _search = v.toLowerCase()),
          ),
        ),
        Expanded(
          child: postsAsync.when(
              loading: () => const Center(
                child: CircularProgressIndicator(color: BsheelColors.primary),
              ),
              error: (e, _) => Center(
                child: Text(
                  'Error: $e',
                  style: BsheelType.bodySm.copyWith(
                    color: BsheelColors.hot,
                  ),
                ),
              ),
              data: (posts) {
                final filtered = posts.where((p) {
                  if (_search.isEmpty) return true;
                  final profile = p[Tables.profiles] as Map<String, dynamic>? ?? {};
                  final username = (profile[ProfileColumns.username] ?? '')
                      .toString()
                      .toLowerCase();
                  final caption = (p[SubmissionColumns.caption] ?? '')
                      .toString()
                      .toLowerCase();
                  return username.contains(_search) ||
                      caption.contains(_search);
                }).toList();

                if (filtered.isEmpty) {
                  return Center(
                    child: Text(
                      'No feed posts found.',
                      style: BsheelType.bodyMd.copyWith(
                        color: BsheelColors.inkMuted,
                      ),
                    ),
                  );
                }

                return ListView.separated(
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(height: QuestSpacing.sm),
                  itemBuilder: (_, i) => _FeedPostTile(
                    post: filtered[i],
                    onRemove: () => _removePost(filtered[i]),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  Future<void> _removePost(Map<String, dynamic> post) async {
    final id = post[SubmissionColumns.id].toString();
    final profile = post[Tables.profiles] as Map<String, dynamic>? ?? {};
    final username = profile[ProfileColumns.username] ?? 'user';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: BsheelColors.paper,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(BsheelRadii.md),
          side: const BorderSide(color: BsheelColors.ink, width: 1),
        ),
        child: Padding(
          padding: const EdgeInsets.all(QuestSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'REMOVE FROM FEED',
                style: BsheelType.displaySm.copyWith(
                  color: BsheelColors.ink,
                ),
              ),
              const SizedBox(height: QuestSpacing.md),
              Text(
                'Remove this post by @$username from the feed? This will mark the submission as rejected.',
                style: BsheelType.bodySm.copyWith(
                  color: BsheelColors.inkMuted,
                ),
              ),
              const SizedBox(height: QuestSpacing.lg),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: Text(
                      'CANCEL',
                      style: BsheelType.labelSm.copyWith(
                        color: BsheelColors.inkMuted,
                      ),
                    ),
                  ),
                  const SizedBox(width: QuestSpacing.sm),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: BsheelColors.hot,
                      foregroundColor: BsheelColors.ink,
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(BsheelRadii.sm),
                      ),
                    ),
                    onPressed: () => Navigator.pop(ctx, true),
                    child: Text(
                      'REMOVE',
                      style: BsheelType.labelSm.copyWith(
                        color: BsheelColors.ink,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (confirmed != true) return;

    // SEC-009: route through admin_remove_post so the action is captured
    // in admin_audit_log with actor + previous_status. The previous
    // direct .update() bypassed the audit pipeline added in 0098.
    final client = ref.read(supabaseClientProvider);
    try {
      await client.rpc(RpcNames.adminRemovePost, params: {
        AdminRemovePostParams.submissionId: id,
        AdminRemovePostParams.reason: 'Removed from feed by admin',
      },);

      ref.invalidate(_feedPostsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Post removed from feed.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to remove: $e')),
        );
      }
    }
  }
}

class _FeedPostTile extends ConsumerWidget {
  final Map<String, dynamic> post;
  final VoidCallback onRemove;

  const _FeedPostTile({required this.post, required this.onRemove});

  String get _firstMediaUrl {
    final raw = (post[SubmissionColumns.mediaUrl]?.toString() ?? '').trim();
    if (raw.startsWith('[')) {
      try {
        final list = (jsonDecode(raw) as List).cast<String>();
        return list.isNotEmpty ? list.first : '';
      } catch (_) {}
    }
    return raw;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = post[Tables.profiles] as Map<String, dynamic>? ?? {};
    final userQuest = post[Tables.userQuests] as Map<String, dynamic>?;
    final quest = userQuest?[Tables.quests] as Map<String, dynamic>?;
    final username = profile[ProfileColumns.username] ?? 'Unknown';
    final caption = post[SubmissionColumns.caption]?.toString() ?? '';
    final mediaUrl = _firstMediaUrl;
    final mediaType = post[SubmissionColumns.mediaType]?.toString() ?? 'image';
    final questTitle = quest?[QuestColumns.title] ?? '';
    final submittedAt = DateTime.tryParse(
      post[SubmissionColumns.submittedAt]?.toString() ?? '',
    );

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: BsheelColors.paper,
        border: Border.all(color: BsheelColors.ink, width: 1),
        borderRadius: BorderRadius.circular(BsheelRadii.sm),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(BsheelRadii.sm),
        onTap: () => _showPostDetail(context, ref),
        child: Padding(
          padding: const EdgeInsets.all(QuestSpacing.md),
          child: Row(
            children: [
              // Thumbnail
              ClipRRect(
                borderRadius: BorderRadius.circular(BsheelRadii.sm),
                child: mediaType == 'video'
                    ? Container(
                        width: 80,
                        height: 80,
                        color: BsheelColors.pureBlack,
                        child: const Icon(
                          Icons.videocam,
                          size: 32,
                          color: BsheelColors.cool,
                        ),
                      )
                    : Image.network(
                        mediaUrl,
                        width: 80,
                        height: 80,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          width: 80,
                          height: 80,
                          color: BsheelColors.ink,
                          child: const Icon(
                            Icons.broken_image,
                            color: BsheelColors.inkMuted,
                          ),
                        ),
                      ),
              ),
              const SizedBox(width: QuestSpacing.md),
              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          '@$username',
                          style: BsheelType.bodyMd.copyWith(
                            fontWeight: FontWeight.bold,
                            color: BsheelColors.ink,
                          ),
                        ),
                        if (questTitle.isNotEmpty) ...[
                          const SizedBox(width: QuestSpacing.sm),
                          Flexible(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: QuestSpacing.sm,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: BsheelColors.cool.withAlpha(30),
                                borderRadius: BorderRadius.circular(
                                  BsheelRadii.full,
                                ),
                                border: Border.all(
                                  color: BsheelColors.cool.withAlpha(80),
                                ),
                              ),
                              child: Text(
                                questTitle,
                                style: BsheelType.labelSm.copyWith(
                                  color: BsheelColors.cool,
                                  fontSize: 10,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (caption.isNotEmpty) ...[
                      const SizedBox(height: QuestSpacing.xs),
                      Text(
                        caption,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: BsheelType.bodySm.copyWith(
                          color: BsheelColors.inkSoft,
                        ),
                      ),
                    ],
                    if (submittedAt != null) ...[
                      const SizedBox(height: QuestSpacing.xs),
                      Text(
                        '${submittedAt.year}-${submittedAt.month.toString().padLeft(2, '0')}-${submittedAt.day.toString().padLeft(2, '0')} ${submittedAt.hour.toString().padLeft(2, '0')}:${submittedAt.minute.toString().padLeft(2, '0')}',
                        style: BsheelType.labelSm.copyWith(
                          color: BsheelColors.inkMuted,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: QuestSpacing.md),
              const Icon(Icons.chevron_right, color: BsheelColors.inkMuted, size: 20),
              const SizedBox(width: QuestSpacing.xs),
              IconButton(
                icon: const Icon(Icons.delete_outline, color: BsheelColors.hot),
                tooltip: 'Remove from feed',
                onPressed: onRemove,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showPostDetail(BuildContext context, WidgetRef ref) async {
    final submissionId = post[SubmissionColumns.id]?.toString() ?? '';
    final profile = post[Tables.profiles] as Map<String, dynamic>? ?? {};
    final userQuest = post[Tables.userQuests] as Map<String, dynamic>?;
    final quest = userQuest?[Tables.quests] as Map<String, dynamic>?;
    final username = profile[ProfileColumns.username] ?? 'Unknown';
    final caption = post[SubmissionColumns.caption]?.toString() ?? '';
    final mediaUrl = _firstMediaUrl;
    final mediaType = post[SubmissionColumns.mediaType]?.toString() ?? 'image';
    final questTitle = quest?[QuestColumns.title] ?? '';
    final submittedAt = DateTime.tryParse(
      post[SubmissionColumns.submittedAt]?.toString() ?? '',
    );

    // Fetch comments for this submission
    final client = ref.read(supabaseClientProvider);
    List<Map<String, dynamic>> comments = [];
    try {
      final data = await client
          .from(Tables.comments)
          .select('*, profiles!comments_user_id_fkey(${ProfileColumns.username}, ${ProfileColumns.displayName})')
          .eq(CommentColumns.submissionId, submissionId)
          .order(CommentColumns.createdAt, ascending: true);
      comments = List<Map<String, dynamic>>.from(data as List);
    } catch (_) {}

    if (!context.mounted) return;

    unawaited(showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: BsheelColors.paper,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(BsheelRadii.md),
          side: const BorderSide(color: BsheelColors.ink, width: 1),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600, maxHeight: 700),
          child: Padding(
            padding: const EdgeInsets.all(QuestSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Row(
                  children: [
                    Text(
                      'POST DETAILS',
                      style: BsheelType.displaySm.copyWith(
                        color: BsheelColors.ink,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close, color: BsheelColors.inkMuted),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const SizedBox(height: QuestSpacing.md),
                // User + quest
                Row(
                  children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: BsheelColors.cool.withAlpha(50),
                      child: Text(
                        username.isNotEmpty ? username[0].toUpperCase() : '?',
                        style: BsheelType.labelSm.copyWith(
                          color: BsheelColors.cool,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: QuestSpacing.sm),
                    Text(
                      '@$username',
                      style: BsheelType.bodyMd.copyWith(
                        fontWeight: FontWeight.bold,
                        color: BsheelColors.ink,
                      ),
                    ),
                    if (questTitle.isNotEmpty) ...[
                      const SizedBox(width: QuestSpacing.sm),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: QuestSpacing.sm,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: BsheelColors.cool.withAlpha(30),
                          borderRadius: BorderRadius.circular(BsheelRadii.full),
                          border: Border.all(color: BsheelColors.cool.withAlpha(80)),
                        ),
                        child: Text(
                          questTitle,
                          style: BsheelType.labelSm.copyWith(
                            color: BsheelColors.cool,
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ],
                    const Spacer(),
                    if (submittedAt != null)
                      Text(
                        '${submittedAt.year}-${submittedAt.month.toString().padLeft(2, '0')}-${submittedAt.day.toString().padLeft(2, '0')}',
                        style: BsheelType.labelSm.copyWith(
                          color: BsheelColors.inkMuted,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: QuestSpacing.md),
                // Media — inline-playable video (no download) or image.
                ClipRRect(
                  borderRadius: BorderRadius.circular(BsheelRadii.sm),
                  child: mediaType == 'video'
                      ? InlineVideo(url: mediaUrl, aspectRatio: 16 / 9)
                      : Image.network(
                          mediaUrl,
                          width: double.infinity,
                          height: 200,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            width: double.infinity,
                            height: 200,
                            color: BsheelColors.ink,
                            child: const Icon(Icons.broken_image, color: BsheelColors.inkMuted),
                          ),
                        ),
                ),
                // Caption
                if (caption.isNotEmpty) ...[
                  const SizedBox(height: QuestSpacing.md),
                  Text(
                    caption,
                    style: BsheelType.bodyMd.copyWith(
                      color: BsheelColors.ink,
                      height: 1.4,
                    ),
                  ),
                ],
                const SizedBox(height: QuestSpacing.md),
                const Divider(color: BsheelColors.ink, thickness: 2),
                const SizedBox(height: QuestSpacing.sm),
                // Comments header
                Text(
                  'COMMENTS (${comments.length})',
                  style: BsheelType.labelSm.copyWith(
                    color: BsheelColors.inkMuted,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: QuestSpacing.sm),
                // Comments list
                Flexible(
                  child: comments.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(QuestSpacing.lg),
                            child: Text(
                              'No comments yet.',
                              style: BsheelType.bodySm.copyWith(
                                color: BsheelColors.inkMuted,
                              ),
                            ),
                          ),
                        )
                      : ListView.separated(
                          shrinkWrap: true,
                          itemCount: comments.length,
                          separatorBuilder: (_, __) => const SizedBox(height: QuestSpacing.sm),
                          itemBuilder: (_, i) {
                            final comment = comments[i];
                            final cProfile = comment[Tables.profiles] as Map<String, dynamic>? ?? {};
                            final cUsername = cProfile[ProfileColumns.username]?.toString() ?? 'user';
                            final cBody = comment[CommentColumns.body]?.toString() ?? '';
                            final cCreatedAt = DateTime.tryParse(
                              comment[CommentColumns.createdAt]?.toString() ?? '',
                            );
                            final timeAgo = cCreatedAt != null
                                ? _formatTimeAgo(cCreatedAt)
                                : '';

                            return Container(
                              padding: const EdgeInsets.all(QuestSpacing.sm),
                              decoration: BoxDecoration(
                                color: BsheelColors.surface,
                                borderRadius: BorderRadius.circular(BsheelRadii.sm),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        '@$cUsername',
                                        style: BsheelType.labelSm.copyWith(
                                          color: BsheelColors.cool,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 11,
                                        ),
                                      ),
                                      const Spacer(),
                                      Text(
                                        timeAgo,
                                        style: BsheelType.labelSm.copyWith(
                                          color: BsheelColors.inkMuted,
                                          fontSize: 10,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    cBody,
                                    style: BsheelType.bodySm.copyWith(
                                      color: BsheelColors.ink,
                                      height: 1.3,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),);
  }

  static String _formatTimeAgo(DateTime dt) => '${timeAgo(dt)} ago';
}
