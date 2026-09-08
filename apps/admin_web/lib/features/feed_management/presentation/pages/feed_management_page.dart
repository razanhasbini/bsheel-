import 'dart:async';
import 'dart:convert';

import 'package:app_contracts/app_contracts.dart';
import 'package:app_models/app_models.dart';
import 'package:app_repositories/app_repositories.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/backend/app_backend.dart';
import '../../../../core/theme/bsheel_design.dart';
import '../../../../shared/layout/admin_shell.dart';
import '../../../../shared/widgets/bsheel_widgets.dart';
import '../../../moderation/presentation/widgets/inline_video.dart';

// ARC-014: cap to the 200 most-recent approved submissions. The full
// list grows unbounded as users post; without a limit this stalls the
// page once a few thousand approved posts exist (each with joined
// profile + user_quest + quest payload). 200 covers >95% of admin
// review needs; the search field is the path for older rows.
const int _adminFeedListLimit = 200;

/// Approved posts in one visibility state, newest first. Media keys are
/// private R2 objects; the adapter signs them so the UI's img tags can
/// fetch the bytes. The page limit is preserved so a 10k+ feed table
/// cannot OOM the browser.
///
/// Keyed by the `SubmissionVisibility` string the chip row selects, so
/// switching tabs is a separate cached request rather than a client-side
/// slice of one unbounded fetch.
final _feedPostsProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, String>((ref, visibility) async {
  return AppBackend.repositories.moderation.listSubmissionsForAdmin(
    status: SubmissionStatus.approved,
    visibility: visibility,
    order: 'desc',
    limit: _adminFeedListLimit,
  );
});

class FeedManagementPage extends ConsumerStatefulWidget {
  const FeedManagementPage({super.key});

  @override
  ConsumerState<FeedManagementPage> createState() => _FeedManagementPageState();
}

class _FeedManagementPageState extends ConsumerState<FeedManagementPage> {
  /// The selected visibility state. Never a literal — the three chips are
  /// the three `SubmissionVisibility` values the database enum allows.
  String _visibility = SubmissionVisibility.visible;

  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final postsAsync = ref.watch(_feedPostsProvider(_visibility));

    return AdminPane(
      title: 'Feed management',
      meta: 'Visibility',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BsheelFilterChips(
            filters: const [
              BsheelFilter(SubmissionVisibility.visible, 'Visible'),
              BsheelFilter(SubmissionVisibility.hiddenFromFeed, 'Hidden'),
              BsheelFilter(SubmissionVisibility.deleted, 'Deleted'),
            ],
            selected: _visibility,
            onChanged: (v) => setState(() => _visibility = v),
          ),
          const SizedBox(height: 12),
          // ARC-014: the search field is the only path to rows older than
          // the 200-row window, so it stays even though the design frame
          // draws the chip row alone.
          BsheelSearchField(
            controller: _search,
            hint: 'Search by username or caption…',
            onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
          ),
          const SizedBox(height: 12),
          postsAsync.when(
            loading: () => const BsheelLoadingList(rows: 4, rowHeight: 92),
            error: (e, _) => BsheelErrorState(
              title: 'Feed didn’t load',
              message: 'The feed list didn’t come back. Nothing was hidden, '
                  'restored or deleted — no post has changed state. $e',
              onRetry: () => ref.invalidate(_feedPostsProvider),
            ),
            data: (posts) {
              final filtered = _filter(posts);
              if (filtered.isEmpty) {
                return _emptyState(posts.isEmpty);
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < filtered.length; i++) ...[
                    if (i != 0) const SizedBox(height: 12),
                    _tileFor(filtered[i], _topVotedId(filtered)),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _tileFor(Map<String, dynamic> post, String? topVotedId) {
    final id = _id(post);
    switch (_visibility) {
      case SubmissionVisibility.hiddenFromFeed:
        return _HiddenPostTile(
          post: post,
          onOpen: () => _showPostDetail(post),
          onRestore: () => _restoreToFeed(post),
        );
      case SubmissionVisibility.deleted:
        // Permanent. The row deliberately carries no action at all — not
        // even a disabled one, because there is nothing to re-enable.
        return _DeletedPostTile(
          post: post,
          onOpen: () => _showPostDetail(post),
        );
      default:
        return _VisiblePostTile(
          post: post,
          // A coloured shadow marks the one row that stands out; the rest
          // stay on ink.
          topVoted: topVotedId != null && topVotedId == id,
          onOpen: () => _showPostDetail(post),
          onHide: () => _hideFromFeed(post),
          onDelete: () => _deletePost(post),
        );
    }
  }

  /// The id of the single highest-scoring row, or null when the list has
  /// no scores worth calling out.
  String? _topVotedId(List<Map<String, dynamic>> rows) {
    if (_visibility != SubmissionVisibility.visible || rows.isEmpty) {
      return null;
    }
    var best = rows.first;
    for (final row in rows) {
      if (_netScore(row) > _netScore(best)) best = row;
    }
    return _netScore(best) <= 0 ? null : _id(best);
  }

  List<Map<String, dynamic>> _filter(List<Map<String, dynamic>> posts) {
    if (_query.isEmpty) return posts;
    return posts.where((p) {
      final username = (p['username'] ?? '').toString().toLowerCase();
      final caption = (p['caption'] ?? '').toString().toLowerCase();
      return username.contains(_query) || caption.contains(_query);
    }).toList(growable: false);
  }

  Widget _emptyState(bool listWasEmpty) {
    if (!listWasEmpty) {
      return BsheelEmptyState(
        title: 'No match',
        message: 'No post in this state mentions “${_search.text.trim()}”. '
            'Clear the search to see the whole list.',
        actionLabel: 'Clear search',
        onAction: () {
          _search.clear();
          setState(() => _query = '');
        },
      );
    }
    switch (_visibility) {
      case SubmissionVisibility.hiddenFromFeed:
        return BsheelEmptyState(
          title: 'Nothing hidden',
          message: 'No approved post is hidden from the feed. Hide one from '
              'the visible list and it moves here.',
          actionLabel: 'Show visible posts',
          onAction: () =>
              setState(() => _visibility = SubmissionVisibility.visible),
        );
      case SubmissionVisibility.deleted:
        return BsheelEmptyState(
          title: 'No deleted posts',
          message: 'No posts have been deleted yet.',
          actionLabel: 'Show visible posts',
          onAction: () =>
              setState(() => _visibility = SubmissionVisibility.visible),
        );
      default:
        return BsheelEmptyState(
          title: 'Nothing on the feed',
          message: 'No approved post is live right now. Approve a submission '
              'in the moderation queue and it lands here.',
          actionLabel: 'Reload',
          onAction: () => ref.invalidate(_feedPostsProvider),
        );
    }
  }

  // ── Visibility actions ────────────────────────────────────────────

  /// Hiding is reversible, so it asks for no confirmation — the row it
  /// produces carries the RESTORE TO FEED button that undoes it.
  Future<void> _hideFromFeed(Map<String, dynamic> post) async {
    final username = (post['username'] ?? 'user').toString();
    try {
      await AppBackend.repositories.submissions.setSubmissionVisibility(
        _id(post),
        SoftDeleteMode.hiddenFromFeed,
      );
      ref.invalidate(_feedPostsProvider);
      _snack('Hidden from the feed. Still on @$username’s profile.');
    } catch (e) {
      _snack('Failed to hide: $e', isError: true);
    }
  }

  Future<void> _restoreToFeed(Map<String, dynamic> post) async {
    try {
      await AppBackend.repositories.submissions.setSubmissionVisibility(
        _id(post),
        SoftDeleteMode.visible,
      );
      ref.invalidate(_feedPostsProvider);
      _snack('Restored to the feed.');
    } catch (e) {
      _snack('Failed to restore: $e', isError: true);
    }
  }

  Future<void> _deletePost(Map<String, dynamic> post) async {
    final username = (post['username'] ?? 'user').toString();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => BsheelDialog(
        title: 'Delete this post',
        content: Text(
          'Delete @$username’s post? It leaves the feed and the author’s '
          'profile, the XP it earned is rolled back, and this cannot be '
          'undone. To take it off the feed reversibly, hide it instead.',
          style: BsheelType.bodySm.copyWith(color: BsheelColors.inkSoft),
        ),
        actions: [
          BsheelButton.ghost(
            label: 'Cancel',
            small: true,
            onPressed: () => Navigator.pop(ctx, false),
          ),
          BsheelButton.coral(
            label: 'Delete',
            small: true,
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // SEC-009: the API captures the actor and previous status in the audit
    // log. A direct visibility update would bypass that.
    try {
      await AppBackend.repositories.admin
          .removePost(_id(post), 'Removed from feed by admin');

      ref.invalidate(_feedPostsProvider);
      _snack('Post deleted. The XP it earned was rolled back.');
    } catch (e) {
      _snack('Failed to delete: $e', isError: true);
    }
  }

  void _snack(String message, {bool isError = false}) {
    if (!mounted) return;
    final ground = isError ? BsheelColors.danger : BsheelColors.card;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: ground,
        content: Text(
          message,
          // The snack ground is coral on an error: ink, never white.
          style: BsheelType.bodySm.copyWith(
            color: BsheelColors.onAccent(ground),
          ),
        ),
      ),
    );
  }

  // ── Detail dialog ─────────────────────────────────────────────────

  Future<void> _showPostDetail(Map<String, dynamic> post) async {
    final submissionId = _id(post);

    // Comments come back as models with replies already grouped and
    // avatars signed.
    var comments = const <CommentModel>[];
    try {
      comments =
          await AppBackend.repositories.comments.getComments(submissionId);
    } catch (_) {
      // Non-fatal: the dialog still shows the post without its thread.
    }

    if (!mounted) return;

    unawaited(
      showDialog<void>(
        context: context,
        builder: (ctx) => BsheelDialog(
          title: 'Post details',
          maxWidth: 600,
          content: _PostDetail(post: post, comments: comments),
          actions: [
            BsheelButton.ghost(
              label: 'Close',
              small: true,
              onPressed: () => Navigator.pop(ctx),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Row shape ───────────────────────────────────────────────────────

/// Live on the feed: white card, ink outline, both actions in reach.
class _VisiblePostTile extends StatelessWidget {
  final Map<String, dynamic> post;
  final bool topVoted;
  final VoidCallback onOpen;
  final VoidCallback onHide;
  final VoidCallback onDelete;

  const _VisiblePostTile({
    required this.post,
    required this.topVoted,
    required this.onOpen,
    required this.onHide,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return BsheelCard(
      padding: const EdgeInsets.all(13),
      shadowColor: topVoted ? BsheelColors.success : BsheelColors.ink,
      onTap: onOpen,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BsheelThumb(url: _firstMediaUrl(post), size: 66),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // A long handle clamps rather than pushing the score
                    // out of the row.
                    Flexible(
                      child: Text(
                        _username(post),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: BsheelType.titleMd,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(_votes(post), style: BsheelType.monoSm),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  _questTitle(post),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: BsheelType.bodySm.copyWith(
                    color: BsheelColors.inkSoft,
                  ),
                ),
                const SizedBox(height: 9),
                Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: [
                    BsheelButton.ghost(
                      label: 'Hide from feed',
                      small: true,
                      onPressed: onHide,
                    ),
                    BsheelButton.coral(
                      label: 'Delete',
                      small: true,
                      onPressed: onDelete,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Hidden from the feed: dashed muted card, and the one button that puts
/// it back. Hiding is reversible and the row says so.
class _HiddenPostTile extends StatelessWidget {
  final Map<String, dynamic> post;
  final VoidCallback onOpen;
  final VoidCallback onRestore;

  const _HiddenPostTile({
    required this.post,
    required this.onOpen,
    required this.onRestore,
  });

  @override
  Widget build(BuildContext context) {
    return BsheelCard.muted(
      padding: const EdgeInsets.all(13),
      onTap: onOpen,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const BsheelMediaPlaceholder(
            label: 'Hidden',
            width: 66,
            height: 66,
            radius: BsheelRadii.sm,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        _username(post),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: BsheelType.titleMd.copyWith(
                          color: BsheelColors.inkSoft,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const BsheelPill.muted('Hidden from feed', small: true),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  _hiddenProvenance(post),
                  style: BsheelType.bodySm.copyWith(
                    color: BsheelColors.inkSoft,
                  ),
                ),
                const SizedBox(height: 9),
                BsheelButton.ghost(
                  label: 'Restore to feed',
                  small: true,
                  onPressed: onRestore,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Deleted: permanent, so the row offers no action. The absence is the
/// point — a disabled button would imply something to re-enable.
class _DeletedPostTile extends StatelessWidget {
  final Map<String, dynamic> post;
  final VoidCallback onOpen;

  const _DeletedPostTile({required this.post, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    return BsheelCard.muted(
      padding: const EdgeInsets.all(13),
      onTap: onOpen,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const BsheelMediaPlaceholder(
            label: 'Deleted',
            width: 66,
            height: 66,
            radius: BsheelRadii.sm,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        _username(post),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: BsheelType.titleMd.copyWith(
                          color: BsheelColors.inkSoft,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    BsheelPill.status(SubmissionVisibility.deleted),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  _deletedProvenance(post),
                  style: BsheelType.bodySm.copyWith(
                    color: BsheelColors.inkSoft,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Detail body ─────────────────────────────────────────────────────

class _PostDetail extends StatelessWidget {
  final Map<String, dynamic> post;
  final List<CommentModel> comments;

  const _PostDetail({required this.post, required this.comments});

  @override
  Widget build(BuildContext context) {
    final caption = (post['caption'] ?? '').toString();
    final mediaUrl = _firstMediaUrl(post);
    final isVideo = (post['media_type'] ?? '').toString() == MediaType.video;
    final questTitle = _questTitle(post);

    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 460),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                BsheelAvatar(
                  url: post['avatar_url']?.toString(),
                  initial: _initial(post),
                  size: 34,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    _username(post),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: BsheelType.titleMd,
                  ),
                ),
                const SizedBox(width: 9),
                Text(
                  bsheelTimeAgo(post['submitted_at']?.toString()),
                  style: BsheelType.monoSm,
                ),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(BsheelRadii.lg),
              child: isVideo
                  ? InlineVideo(url: mediaUrl, aspectRatio: 16 / 9)
                  : Image.network(
                      mediaUrl,
                      width: double.infinity,
                      height: 210,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          const BsheelMediaPlaceholder(
                        height: 210,
                        width: double.infinity,
                      ),
                    ),
            ),
            if (questTitle.isNotEmpty) ...[
              const SizedBox(height: 12),
              const BsheelLabel('Quest'),
              const SizedBox(height: 4),
              Text(questTitle, style: BsheelType.bodySmMedium),
            ],
            if (caption.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(caption, style: BsheelType.bodyMd),
            ],
            const SizedBox(height: 14),
            BsheelLabel('Comments ${comments.length}'),
            const SizedBox(height: 8),
            if (comments.isEmpty)
              Text(
                'No comments yet.',
                style: BsheelType.bodySm.copyWith(color: BsheelColors.inkSoft),
              )
            else
              for (final comment in comments) ...[
                BsheelCard.flat(
                  color: BsheelColors.surface,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '@${comment.username}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: BsheelType.monoMd,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            bsheelTimeAgo(comment.createdAt.toIso8601String()),
                            style: BsheelType.monoSm,
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(comment.body, style: BsheelType.bodySm),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
              ],
          ],
        ),
      ),
    );
  }
}

// ── Row readers ─────────────────────────────────────────────────────

String _id(Map<String, dynamic> post) => (post['id'] ?? '').toString();

String _username(Map<String, dynamic> post) =>
    '@${post['username'] ?? 'unknown'}';

String _initial(Map<String, dynamic> post) {
  final handle = (post['username'] ?? '').toString().trim();
  return handle.isEmpty ? '?' : handle.substring(0, 1);
}

String _questTitle(Map<String, dynamic> post) =>
    (post['quest_title'] ?? '').toString();

/// `submissions.net_score` is maintained by a trigger on `reactions`, so
/// it is the one vote figure the admin list row carries.
int _netScore(Map<String, dynamic> post) =>
    int.tryParse((post['net_score'] ?? '0').toString()) ?? 0;

String _votes(Map<String, dynamic> post) => '${_netScore(post)} ▲';

/// The row records `moderation_removed_at` only when a moderator took the
/// post down, which is the one provenance signal available — there is no
/// `hidden_by` / `hidden_at` column to name a person from.
String _hiddenProvenance(Map<String, dynamic> post) {
  final removed = post['moderation_removed_at']?.toString();
  if (removed != null && removed.isNotEmpty) {
    final when = bsheelTimeAgo(removed, caps: false);
    return 'Still visible on the author’s profile. Hidden by a moderator'
        '${when.isEmpty ? '' : ' $when'}.';
  }
  return 'Still visible on the author’s profile. Hidden by the author.';
}

String _deletedProvenance(Map<String, dynamic> post) {
  final byModerator =
      (post['moderation_removed_at']?.toString() ?? '').isNotEmpty;
  final when = bsheelTimeAgo(
    post['deleted_at']?.toString() ?? post['moderation_removed_at']?.toString(),
    caps: false,
  );
  final actor = byModerator ? 'a moderator' : 'the author';
  return 'Gone from the feed and the author’s profile, and the XP it earned '
      'was rolled back. Deleted by $actor${when.isEmpty ? '' : ' $when'}.';
}

/// `media_url` is either a single signed URL or a JSON array of them.
String _firstMediaUrl(Map<String, dynamic> post) {
  final raw = (post['media_url']?.toString() ?? '').trim();
  if (raw.startsWith('[')) {
    try {
      final list = (jsonDecode(raw) as List).cast<String>();
      return list.isNotEmpty ? list.first : '';
    } catch (_) {}
  }
  return raw;
}
