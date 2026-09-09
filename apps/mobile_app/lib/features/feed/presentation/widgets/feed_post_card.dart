import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app_contracts/app_contracts.dart';
import 'package:app_core/app_core.dart';
import 'package:app_models/app_models.dart';
import 'package:shared_ui/shared_ui.dart';

import '../providers/feed_comment_count_provider.dart';
import 'post_action_row.dart';
import 'post_avatar.dart';

/// One post in the feed list, read off `export/mobile/09-feed.jpg`.
///
/// White ground, 2px ink border, `r16`, and — the one rule that appears in
/// no prose and only in the image — a 3px hard shadow in the post's
/// **category** colour: jade for LEARNING, gold for ADVENTURE, via
/// [QuestColors.category]. The coloured shadow is the load-bearing signal
/// on this screen, the way violet marks the active quest on home.
///
/// Structure, top to bottom: header (round avatar · handle · mono meta ·
/// category tag), a full-width cream media band bounded by 2px ink rules,
/// then the title / body / action block.
class FeedPostCard extends ConsumerWidget {
  const FeedPostCard({
    super.key,
    required this.post,
    required this.upvotes,
    required this.downvotes,
    required this.isUpvoted,
    required this.isDownvoted,
    required this.isSaved,
    required this.timeAgoLabel,
    this.modeBadge,
    this.onOpen,
    this.onUserTap,
    this.onUpvote,
    this.onDownvote,
    this.onComment,
    this.onSave,
    this.onActions,
  });

  final FeedPostModel post;
  final int upvotes;
  final int downvotes;
  final bool isUpvoted;
  final bool isDownvoted;
  final bool isSaved;
  final String timeAgoLabel;

  /// `VERSUS · 3` / `COOP · 2` for collab posts, null for solo ones.
  final String? modeBadge;

  final VoidCallback? onOpen;
  final VoidCallback? onUserTap;
  final VoidCallback? onUpvote;
  final VoidCallback? onDownvote;
  final VoidCallback? onComment;
  final VoidCallback? onSave;
  final VoidCallback? onActions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const ink = QuestColors.osTextPrimary;
    final tint = QuestColors.category(post.questCategory);

    final commentCount = ref.watch(feedCommentCountProvider(post.id));

    final body = (post.caption?.trim().isNotEmpty ?? false)
        ? post.caption!.trim()
        : post.questDescription.trim();

    return Container(
      decoration: BoxDecoration(
        color: QuestColors.osCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: ink, width: 2),
        boxShadow: [
          // Category colour, square offset, no blur.
          BoxShadow(color: tint, offset: const Offset(3, 3), blurRadius: 0),
        ],
      ),
      child: ClipRRect(
        // Inside the 2px border, so the clip follows the border's inner edge.
        borderRadius: BorderRadius.circular(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _CardHeader(
              post: post,
              tint: tint,
              timeAgoLabel: timeAgoLabel,
              modeBadge: modeBadge,
              onUserTap: onUserTap,
              onActions: onActions,
            ),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onOpen,
              child: ProofMediaBand(
                urls: post.mediaUrls,
                isVideo: post.mediaType == MediaType.video,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onOpen,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          post.questTitle.toUpperCase(),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: QuestTypography.osHeadlineLarge.copyWith(
                            fontSize: 22,
                            height: 1.08,
                            letterSpacing: -0.2,
                          ),
                        ),
                        if (body.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            body,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: QuestTypography.osBodyMedium.copyWith(
                              color: QuestColors.osTextSecondary,
                              height: 1.45,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  PostActionRow(
                    upvotes: upvotes,
                    downvotes: downvotes,
                    commentCount: commentCount,
                    isUpvoted: isUpvoted,
                    isDownvoted: isDownvoted,
                    isSaved: isSaved,
                    // Collab posts vote per member on the detail screen.
                    showVotes: modeBadge == null,
                    onUpvote: onUpvote,
                    onDownvote: onDownvote,
                    onComment: onComment,
                    onSave: onSave,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Header ──────────────────────────────────────────────────────────────────

class _CardHeader extends StatelessWidget {
  const _CardHeader({
    required this.post,
    required this.tint,
    required this.timeAgoLabel,
    required this.modeBadge,
    required this.onUserTap,
    required this.onActions,
  });

  final FeedPostModel post;
  final Color tint;
  final String timeAgoLabel;
  final String? modeBadge;
  final VoidCallback? onUserTap;
  final VoidCallback? onActions;

  @override
  Widget build(BuildContext context) {
    final handle = post.username.isNotEmpty ? post.username : post.displayName;

    // The render's `LVL 12 · MAGE · 2H AGO`. The feed row carries no level
    // or class, so the two facts it does carry — the XP the proof earned
    // and how long ago it landed — take the slot rather than inventing a
    // level the API has not sent.
    final meta = <String>[
      if (post.xpReward > 0) '+${post.xpReward} XP',
      if (modeBadge != null) modeBadge!,
      timeAgoLabel.toUpperCase(),
    ].join(' · ');

    return Padding(
      // Matches the title block below it: 14 from the card's inner edge.
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Row(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onUserTap,
            child: PostAvatar(
              username: handle,
              imageUrl: post.avatarUrl,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onUserTap,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    handle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: QuestTypography.osHeadlineMedium.copyWith(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    meta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: QuestTypography.osLabelSmall.copyWith(
                      color: QuestColors.osTextSecondary,
                      fontSize: 10,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (post.questCategory.isNotEmpty) ...[
            const SizedBox(width: 8),
            ArcadeCategoryTag(label: post.questCategory, tint: tint),
          ],
          IconButton(
            tooltip: 'Post actions: share, report or block',
            onPressed: onActions,
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            icon: const Icon(Icons.more_horiz),
          ),
        ],
      ),
    );
  }
}

// ── Media band ──────────────────────────────────────────────────────────────

/// The cream proof-media band: full card width, bounded above and below by
/// 2px ink rules, `PROOF MEDIA` centred while there is nothing to show.
///
/// Video is deliberately **not** played here. A card list has no single
/// active post, so a video shows a tap-to-play face and hands playback to
/// the post-detail screen, which already owns a real player. Nothing in
/// this file reaches `video_compress`, so the web build stays buildable.
class ProofMediaBand extends StatelessWidget {
  const ProofMediaBand({
    super.key,
    required this.urls,
    required this.isVideo,
    this.aspectRatio = 4 / 3,
  });

  final List<String> urls;
  final bool isVideo;
  final double aspectRatio;

  @override
  Widget build(BuildContext context) {
    const ink = QuestColors.osTextPrimary;
    final url = urls.isEmpty ? null : urls.first;
    final video = isVideo || (url != null && isVideoUrl(url));

    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: QuestColors.osSurface,
        border: Border.symmetric(
          horizontal: BorderSide(color: ink, width: 2),
        ),
      ),
      child: AspectRatio(
        aspectRatio: aspectRatio,
        child: Stack(
          fit: StackFit.expand,
          children: [
            const ProofMediaLabel(),
            if (url != null && !video)
              CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.cover,
                placeholder: (_, __) => const ArcadeSkeleton(
                  width: double.infinity,
                  height: double.infinity,
                  radius: 0,
                  bordered: false,
                ),
                errorWidget: (_, __, ___) => const ProofMediaLabel(),
              ),
            if (url != null && video) const _VideoFace(),
            if (urls.length > 1)
              Positioned(
                right: 8,
                bottom: 8,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: QuestColors.osCard,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: ink, width: 2),
                  ),
                  child: Text(
                    '1/${urls.length}',
                    style: QuestTypography.osLabelSmall.copyWith(
                      color: ink,
                      fontSize: 10,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// `PROOF MEDIA`, centred. The loading and empty face of the media band.
class ProofMediaLabel extends StatelessWidget {
  const ProofMediaLabel({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'PROOF MEDIA',
        textAlign: TextAlign.center,
        style: QuestTypography.osLabelMedium.copyWith(
          // Muted-on-cream would measure 2.9:1; the secondary ink keeps the
          // same quiet read and passes.
          color: QuestColors.osTextSecondary,
          fontSize: 11,
          letterSpacing: 1.6,
        ),
      ),
    );
  }
}

class _VideoFace extends StatelessWidget {
  const _VideoFace();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: QuestColors.osPrimary,
              shape: BoxShape.circle,
              border: Border.all(color: QuestColors.osTextPrimary, width: 2),
              boxShadow: const [
                BoxShadow(
                  color: QuestColors.osTextPrimary,
                  offset: Offset(3, 3),
                  blurRadius: 0,
                ),
              ],
            ),
            alignment: Alignment.center,
            child: Icon(
              Icons.play_arrow_rounded,
              size: 30,
              color: QuestColors.onAccent(QuestColors.osPrimary),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'TAP TO PLAY',
            style: QuestTypography.osLabelMedium.copyWith(
              color: QuestColors.osTextSecondary,
              fontSize: 10,
              letterSpacing: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}
