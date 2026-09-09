import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';
import 'package:app_core/app_core.dart';
import 'package:app_models/app_models.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../../design/bs_widgets.dart';
import 'collab_vote_button.dart';
import '../providers/feed_provider.dart';
import '../../../comments/presentation/widgets/comments_section.dart';

/// Instagram Reels-style full-screen post.
///
/// One per page in a vertical [PageView]. Supports multi-media carousels
/// (swipe horizontally to flip through images/videos within the post).
/// Portrait media fills the screen edge-to-edge; landscape media is shown
/// in full with a blurred backdrop.
class ReelsCard extends ConsumerStatefulWidget {
  const ReelsCard({
    super.key,
    required this.submissionId,
    required this.username,
    required this.displayName,
    required this.avatarUrl,
    required this.questTitle,
    required this.xpReward,
    required this.caption,
    required this.mediaUrls,
    required this.mediaType,
    required this.upvoteCount,
    required this.downvoteCount,
    required this.myVoteType,
    required this.isSaved,
    required this.timeAgo,
    required this.isActive,
    required this.modeBadge,
    this.onUpvote,
    this.onDownvote,
    this.onSave,
    this.onCommentTap,
    this.onUserTap,
    this.onTap,
    this.onMoreTap,
    this.onDoubleTapUpvote,
    this.collabGroupId,
    this.collabMode,
    this.collabMembers = const [],
    this.expiresAt,
  });

  final String submissionId;
  final String username;
  final String displayName;
  final String? avatarUrl;
  final String questTitle;
  final int xpReward;
  final String? caption;
  final List<String> mediaUrls;
  final String mediaType; // 'image' | 'video' (applies to all items)
  final int upvoteCount;
  final int downvoteCount;
  final String? myVoteType; // 'upvote' | 'downvote' | null
  final bool isSaved;
  final String timeAgo;
  final bool isActive;
  final String? modeBadge;

  final VoidCallback? onUpvote;
  final VoidCallback? onDownvote;
  final VoidCallback? onSave;
  final VoidCallback? onCommentTap;
  final VoidCallback? onUserTap;
  final VoidCallback? onTap;
  final VoidCallback? onMoreTap;
  // Distinct from [onUpvote] — fires on the media double-tap and is
  // expected to be additive only (never un-upvote). Toggle behaviour
  // stays on the upvote rail button.
  final VoidCallback? onDoubleTapUpvote;

  // Collab/versus context — when [collabMode] == 'versus' and
  // [collabMembers] is non-empty, the action rail swaps the up/down
  // arrows for one avatar-vote button per member.
  final String? collabGroupId;
  final String? collabMode;
  final List<CollabFeedMember> collabMembers;

  /// Quest deadline (post-owner's `user_quests.expires_at`). When this is
  /// in the past, the "WAITING FOR @user" placeholder switches to
  /// "DIDN'T POST" — that member ran out of time.
  final DateTime? expiresAt;

  @override
  ConsumerState<ReelsCard> createState() => _ReelsCardState();
}

class _ReelsCardState extends ConsumerState<ReelsCard> {
  static const Color _scrimStop0 =
      Color(0x00000000); // Screen-specific colour — not a theme token.
  static const Color _scrimStop20 =
      Color(0x33000000); // Screen-specific colour — not a theme token.
  static const Color _scrimStop60 =
      Color(0x99000000); // Screen-specific colour — not a theme token.
  static const Color _scrimStop85 =
      Color(0xD9000000); // Screen-specific colour — not a theme token.

  final _hController = PageController();
  int _hIndex = 0;

  // Mute state lives on a shared provider (feedVideoMutedProvider) so
  // toggling once persists across every post the user scrolls to next.

  // Local copy of collab members so optimistic votes from CollabVoteButton
  // can update the UI before the next provider refresh. Synced from the
  // widget on init / didUpdateWidget so a fresh server snapshot always
  // wins over stale local state.
  late List<CollabFeedMember> _members;

  @override
  void initState() {
    super.initState();
    _members = List<CollabFeedMember>.from(widget.collabMembers);
  }

  @override
  void didUpdateWidget(covariant ReelsCard old) {
    super.didUpdateWidget(old);
    if (!identical(old.collabMembers, widget.collabMembers)) {
      _members = List<CollabFeedMember>.from(widget.collabMembers);
    }
  }

  @override
  void dispose() {
    _hController.dispose();
    super.dispose();
  }

  void _toggleMute() {
    final notifier = ref.read(feedVideoMutedProvider.notifier);
    notifier.state = !notifier.state;
  }

  /// Detect video by URL extension first — a post's `mediaType` is one
  /// string (image / video / mixed), so for `mixed` posts each item must
  /// be classified individually or videos render as broken images.
  bool _isVideoUrl(String url) =>
      isVideoUrl(url) || widget.mediaType == 'video';

  @override
  Widget build(BuildContext context) {
    final urls = widget.mediaUrls;
    // Whether the carousel contains *any* video — controls the mute toggle.
    final hasVideo = widget.mediaType == 'video' ||
        widget.mediaType == 'mixed' ||
        urls.any(_isVideoUrl);

    // Shared mute state — flips persist across every card the user sees.
    final muted = ref.watch(feedVideoMutedProvider);

    final navInset = MediaQuery.of(context).padding.bottom * 0.30 + 80;

    // Total comment count = top-level + nested replies. Reuses the same
    // provider the comments sheet/details page already prefetch, so this
    // is essentially free here.
    final commentsAsync = ref.watch(commentsProvider(widget.submissionId));
    final commentCount = commentsAsync.maybeWhen(
      data: (comments) => comments.fold<int>(
        0,
        (sum, c) => sum + 1 + c.replies.length,
      ),
      orElse: () => 0,
    );

    // ── Collab carousel ──────────────────────────────────────────────
    // For versus / coop posts the swipe iterates over a flat list of
    // (member, media-url) slots. A member with N pieces of media gets N
    // adjacent slots — so swiping through their media keeps THEIR caption
    // pinned, and only when we cross into the next member does the
    // bottom-meta flip to that person's avatar / handle / caption.
    // DB convention: collab modes are 'versus' and 'with' (the latter is
    // what the UI calls "coop"). The original 'coop' string was wrong.
    final isCollab =
        (widget.collabMode == 'versus' || widget.collabMode == 'with') &&
            _members.isNotEmpty;

    // Visible team — every member who hasn't been hidden from the feed,
    // whether they've uploaded yet or not. Members without media still
    // get a placeholder "waiting for…" slide so the user can swipe past
    // them and see who hasn't posted yet.
    final visibleMembers = isCollab
        ? _members.where((m) => m.showInFeed).toList()
        : const <CollabFeedMember>[];

    final List<_CarouselSlot> slots;
    if (isCollab && visibleMembers.isNotEmpty) {
      slots = [];
      for (final m in visibleMembers) {
        final memberUrls =
            m.mediaUrls.where((u) => u.trim().isNotEmpty).toList();
        if (memberUrls.isEmpty) {
          slots.add(_CarouselSlot(member: m, url: '', isWaiting: true));
        } else {
          for (final url in memberUrls) {
            slots.add(_CarouselSlot(member: m, url: url));
          }
        }
      }
    } else {
      slots = [for (final u in urls) _CarouselSlot(member: null, url: u)];
    }

    final clampedIndex = slots.isEmpty ? 0 : _hIndex.clamp(0, slots.length - 1);
    final activeSlot = slots.isEmpty ? null : slots[clampedIndex];
    final activeMember = activeSlot?.member;

    // The post-owner's quest deadline applies to the whole collab group
    // (members joined into the same active window), so we use it for the
    // "WAITING FOR" → "DIDN'T POST" copy switch.
    final hasExpired =
        widget.expiresAt != null && DateTime.now().isAfter(widget.expiresAt!);

    Widget buildSlot(int i, {required bool isActiveSlot}) {
      final slot = slots[i];
      if (slot.isWaiting) {
        return _WaitingForMember(
          member: slot.member!,
          hasExpired: hasExpired,
        );
      }
      return _ReelsMediaItem(
        url: slot.url,
        isVideo: _isVideoUrl(slot.url),
        isActive: widget.isActive && isActiveSlot,
        muted: muted,
        onSingleTap: widget.onTap,
        onDoubleTapAction: widget.onDoubleTapUpvote,
      );
    }

    Widget mediaLayer;
    if (slots.isEmpty) {
      mediaLayer = const _MediaPlaceholder();
    } else if (slots.length == 1) {
      mediaLayer = buildSlot(0, isActiveSlot: true);
    } else {
      mediaLayer = PageView.builder(
        controller: _hController,
        scrollDirection: Axis.horizontal,
        itemCount: slots.length,
        onPageChanged: (i) => setState(() => _hIndex = i),
        itemBuilder: (_, i) => buildSlot(i, isActiveSlot: i == clampedIndex),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        Container(color: QuestColors.pureBlack),
        Positioned.fill(child: mediaLayer),

        // ── Bottom legibility scrim ──────────────────────────────────
        // Two-layer scrim that sits ABOVE the media but BEHIND the
        // bottom-meta + action rail. Layer 1 is a long soft fade from
        // transparent at the top to ~85% black at the bottom — handles
        // overall legibility on bright media. Layer 2 is a shorter,
        // near-opaque band right behind the avatar / quest title /
        // caption so type always reads regardless of what's behind it.
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: navInset + 240,
          child: const IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    _scrimStop0,
                    _scrimStop20,
                    _scrimStop60,
                    _scrimStop85,
                  ],
                  stops: [0.0, 0.25, 0.55, 1.0],
                ),
              ),
            ),
          ),
        ),

        // Mute toggle for video posts (Instagram-style: small circle, soft).
        if (hasVideo && widget.isActive)
          Positioned(
            top: MediaQuery.of(context).padding.top + 96,
            right: 14,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _toggleMute,
              child: BsMinTouch(
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: QuestColors.pureBlack.withAlpha(150),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: QuestColors.pureBlack.withAlpha(70),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Icon(
                    muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                    color: QuestColors.textPrimary,
                    size: 16,
                  ),
                ),
              ),
            ),
          ),

        // ── Right-side action rail ───────────────────────────────────
        Positioned(
          right: 10,
          bottom: navInset,
          child: _ActionRail(
            upvoteCount: widget.upvoteCount,
            downvoteCount: widget.downvoteCount,
            commentCount: commentCount,
            myVoteType: widget.myVoteType,
            isSaved: widget.isSaved,
            onUpvote: widget.onUpvote,
            onDownvote: widget.onDownvote,
            onComment: widget.onCommentTap,
            onSave: widget.onSave,
            onMore: widget.onMoreTap,
            collabGroupId: widget.collabGroupId,
            collabMode: widget.collabMode,
            collabMembers: _members,
            onMemberVoteApplied: (memberId, nowVoted, newCount) {
              setState(() {
                _members = [
                  for (final m in _members)
                    if (m.userId == memberId)
                      m.copyWith(viewerVoted: nowVoted, voteCount: newCount)
                    else
                      m,
                ];
              });
            },
          ),
        ),

        // ── Bottom-left content ─────────────────────────────────────
        Positioned(
          left: 14,
          right: 84,
          bottom: navInset,
          child: _BottomMeta(
            // Collab → identity follows the active member. Caption is
            // taken strictly from that member (no fallback to the post
            // owner's caption); if they didn't write one, no caption is
            // shown — _BottomMeta already hides empty captions.
            displayName: activeMember?.displayName ?? widget.displayName,
            username: activeMember?.username ?? widget.username,
            avatarUrl: activeMember?.avatarUrl ?? widget.avatarUrl,
            questTitle: widget.questTitle,
            xpReward: widget.xpReward,
            caption: isCollab ? activeMember?.caption : widget.caption,
            timeAgo: widget.timeAgo,
            modeBadge: widget.modeBadge,
            mediaCount: slots.length,
            mediaIndex: clampedIndex,
            isCollab: isCollab,
            collabMode: widget.collabMode,
            collabMembers: visibleMembers,
            activeMemberIndex: 0, // unused now; kept for prop compat
            onUserTap: widget.onUserTap,
            onTap: widget.onTap,
          ),
        ),
      ],
    );
  }
}

// ── Single media item: image or video, aspect-aware ──────────────────────────

class _ReelsMediaItem extends ConsumerStatefulWidget {
  const _ReelsMediaItem({
    required this.url,
    required this.isVideo,
    required this.isActive,
    required this.muted,
    this.onSingleTap,
    this.onDoubleTapAction,
  });

  final String url;
  final bool isVideo;
  final bool isActive;
  final bool muted;
  final VoidCallback? onSingleTap;
  final VoidCallback? onDoubleTapAction;

  @override
  ConsumerState<_ReelsMediaItem> createState() => _ReelsMediaItemState();
}

class _ReelsMediaItemState extends ConsumerState<_ReelsMediaItem> {
  // Image-only state.
  ImageProvider? _imageProvider;
  Size? _imageSize;

  // Video-only state.
  VideoPlayerController? _video;
  bool _videoReady = false;
  bool _userPaused = false;
  // Tracks the controller's `value.isBuffering` so the loader can overlay
  // the post any time playback stalls — not just during initial load.
  bool _isBuffering = false;

  // Double-tap upvote feedback.
  int _flashKey = 0;
  Timer? _flashTimer;

  bool get _shouldPlay =>
      widget.isActive && !_userPaused && !ref.read(feedVideosPausedProvider);

  @override
  void initState() {
    super.initState();
    if (widget.isVideo) {
      if (widget.isActive) _initVideo();
    } else {
      _resolveImage();
    }
  }

  @override
  void didUpdateWidget(covariant _ReelsMediaItem old) {
    super.didUpdateWidget(old);
    if (widget.isVideo) {
      if (widget.isActive && _video == null) {
        _initVideo();
      } else if (_video != null && _videoReady) {
        if (_shouldPlay) {
          _video!.play();
        } else {
          _video!.pause();
        }
        _video!.setVolume(widget.muted ? 0 : 1);
      }
    }
  }

  Future<void> _initVideo() async {
    final c = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    _video = c;
    try {
      await c.initialize();
      await c.setLooping(true);
      await c.setVolume(widget.muted ? 0 : 1);
      if (!mounted) return;
      // Listen for buffering state changes so we can overlay the loader
      // any time playback stalls mid-stream, not just on first load.
      c.addListener(_onVideoTick);
      setState(() {
        _videoReady = true;
        _isBuffering = c.value.isBuffering;
      });
      if (_shouldPlay) await c.play();
    } catch (_) {/* placeholder fallback */}
  }

  void _onVideoTick() {
    final v = _video;
    if (v == null || !mounted) return;
    if (v.value.isBuffering != _isBuffering) {
      setState(() => _isBuffering = v.value.isBuffering);
    }
  }

  void _resolveImage() {
    final p = CachedNetworkImageProvider(widget.url);
    _imageProvider = p;
    final stream = p.resolve(const ImageConfiguration());
    late final ImageStreamListener listener;
    listener = ImageStreamListener((info, _) {
      if (!mounted) return;
      setState(() => _imageSize = Size(
            info.image.width.toDouble(),
            info.image.height.toDouble(),
          ));
      stream.removeListener(listener);
    }, onError: (_, __) {
      stream.removeListener(listener);
    });
    stream.addListener(listener);
  }

  void _toggleVideo() {
    if (_video == null || !_videoReady) return;
    if (_video!.value.isPlaying) {
      _video!.pause();
      _userPaused = true;
    } else {
      _video!.play();
      _userPaused = false;
    }
    setState(() {});
  }

  @override
  void dispose() {
    _flashTimer?.cancel();
    _video?.removeListener(_onVideoTick);
    _video?.dispose();
    super.dispose();
  }

  void _onDoubleTap() {
    widget.onDoubleTapAction?.call();
    setState(() => _flashKey++);
    _flashTimer?.cancel();
    _flashTimer = Timer(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => _flashKey = 0);
    });
  }

  void _onSingleTap() {
    if (widget.isVideo) {
      _toggleVideo();
    } else {
      widget.onSingleTap?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    // React when something pushes/pops a route over the feed.
    ref.listen<bool>(feedVideosPausedProvider, (_, paused) {
      final v = _video;
      if (v == null || !_videoReady) return;
      if (paused) {
        v.pause();
      } else if (_shouldPlay) {
        v.play();
      }
    });

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _onSingleTap,
      onDoubleTap: widget.onDoubleTapAction == null ? null : _onDoubleTap,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final media = widget.isVideo
              ? _buildVideo(constraints)
              : _buildImage(constraints);
          return Stack(
            fit: StackFit.expand,
            children: [
              media,
              if (_flashKey > 0)
                IgnorePointer(
                  child: TweenAnimationBuilder<double>(
                    key: ValueKey(_flashKey),
                    tween: Tween(begin: 0.0, end: 1.0),
                    duration: const Duration(milliseconds: 600),
                    curve: Curves.easeOut,
                    builder: (_, t, __) {
                      // Pop in fast, fade out slow.
                      final opacity =
                          t < 0.25 ? (t / 0.25) : (1 - (t - 0.25) / 0.75);
                      final scale = 0.6 + t * 0.6;
                      return Center(
                        child: Opacity(
                          opacity: opacity.clamp(0.0, 1.0),
                          child: Transform.scale(
                            scale: scale,
                            child: Icon(
                              Icons.arrow_upward_rounded,
                              color: QuestColors.osRed,
                              size: 120,
                              shadows: [
                                Shadow(
                                  color: QuestColors.pureBlack
                                      .withAlpha(QuestColors.alphaInkSoft),
                                  blurRadius: 12,
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  // ── Image rendering ────────────────────────────────────────────────

  Widget _buildImage(BoxConstraints constraints) {
    final dpr = MediaQuery.of(context).devicePixelRatio;
    // Cap memory usage by decoding at display resolution, not source size.
    final cacheWidth = (constraints.maxWidth * dpr).round();
    final cacheHeight = (constraints.maxHeight * dpr).round();

    final size = _imageSize;
    final screenAspect = constraints.maxWidth / constraints.maxHeight;
    final isLandscape = size != null &&
        size.width / size.height > screenAspect * 1.05; // small hysteresis

    if (isLandscape && _imageProvider != null) {
      // Letterbox on solid black. Was previously a blurred copy of the
      // image — looked like a coloured gradient and made the player feel
      // less premium than reels apps. Pure black matches Instagram /
      // TikTok and lets the actual media own the visual frame.
      return Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: QuestColors.pureBlack),
          Center(
            child: Image(
              image: _imageProvider!,
              fit: BoxFit.contain,
              gaplessPlayback: true,
            ),
          ),
        ],
      );
    }

    // Default: cover fill (works for portrait/square, and unknown sizes).
    return CachedNetworkImage(
      imageUrl: widget.url,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      memCacheWidth: cacheWidth,
      memCacheHeight: cacheHeight,
      placeholder: (_, __) => const _MediaSpinner(),
      errorWidget: (_, __, ___) => const _MediaPlaceholder(),
    );
  }

  // ── Video rendering ────────────────────────────────────────────────

  Widget _buildVideo(BoxConstraints constraints) {
    final v = _video;
    if (v == null || !_videoReady) {
      // Black plate behind the chunky loader so it reads on every device.
      return const Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: QuestColors.pureBlack),
          _BufferingGlyph(),
        ],
      );
    }
    final size = v.value.size;
    final screenAspect = constraints.maxWidth / constraints.maxHeight;
    final mediaAspect = size.width <= 0 || size.height <= 0
        ? screenAspect
        : size.width / size.height;
    final isLandscape = mediaAspect > screenAspect * 1.05;

    if (isLandscape) {
      // Letterbox on solid black. Was previously a blurred copy of the
      // video itself — looked like a coloured gradient in the dead space
      // above/below. Pure black matches reels/TikTok and stops the bars
      // from competing with the actual video for attention.
      return Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: QuestColors.pureBlack),
          Center(
            child: AspectRatio(
              aspectRatio: mediaAspect,
              child: VideoPlayer(v),
            ),
          ),
          if (_userPaused && widget.isActive) const _PauseGlyph(),
          if (_isBuffering) const _BufferingGlyph(),
        ],
      );
    }

    // Portrait/square: fill edge-to-edge.
    return Stack(
      fit: StackFit.expand,
      children: [
        SizedBox.expand(
          child: FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: size.width,
              height: size.height,
              child: VideoPlayer(v),
            ),
          ),
        ),
        if (_userPaused && widget.isActive) const _PauseGlyph(),
        if (_isBuffering) const _BufferingGlyph(),
      ],
    );
  }
}

class _PauseGlyph extends StatelessWidget {
  const _PauseGlyph();
  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Center(
        child: Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: QuestColors.pureBlack.withAlpha(120),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.play_arrow_rounded,
              color: QuestColors.textPrimary, size: 44),
        ),
      ),
    );
  }
}

/// Loader overlay shown in the centre of the post while a video is
/// initialising or buffering mid-stream. Slightly bigger and on a soft
/// dark plate so it reads against bright media too.
class _BufferingGlyph extends StatelessWidget {
  const _BufferingGlyph();
  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Center(
        child: Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: QuestColors.pureBlack.withAlpha(110),
            shape: BoxShape.circle,
          ),
          child: const Padding(
            padding: EdgeInsets.all(18),
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              valueColor:
                  AlwaysStoppedAnimation<Color>(QuestColors.textPrimary),
            ),
          ),
        ),
      ),
    );
  }
}

class _MediaSpinner extends StatelessWidget {
  const _MediaSpinner();
  @override
  Widget build(BuildContext context) {
    return const Center(
      child: SizedBox(
        width: 28,
        height: 28,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation<Color>(QuestColors.textSecondary),
        ),
      ),
    );
  }
}

class _MediaPlaceholder extends StatelessWidget {
  const _MediaPlaceholder();
  @override
  Widget build(BuildContext context) {
    return Container(
      color: QuestColors.pureBlack,
      child: Center(
        child: Icon(Icons.image_not_supported_rounded,
            color: QuestColors.pureWhite.withAlpha(QuestColors.alphaHairline),
            size: 48),
      ),
    );
  }
}

// ── Page indicator dots (carousel) ──────────────────────────────────────────

class _PageDots extends StatelessWidget {
  const _PageDots({required this.count, required this.current});
  final int count;
  final int current;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: QuestColors.pureBlack.withAlpha(110),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(count, (i) {
          final active = i == current;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            margin: EdgeInsets.symmetric(horizontal: i == 0 ? 0 : 3),
            width: active ? 7 : 5,
            height: active ? 7 : 5,
            decoration: BoxDecoration(
              color: active
                  ? QuestColors.textPrimary
                  : QuestColors.textPrimary.withAlpha(120),
              shape: BoxShape.circle,
            ),
          );
        }),
      ),
    );
  }
}

// ── Action rail ─────────────────────────────────────────────────────────────

class _ActionRail extends StatelessWidget {
  const _ActionRail({
    required this.upvoteCount,
    required this.downvoteCount,
    required this.commentCount,
    required this.myVoteType,
    required this.isSaved,
    required this.onUpvote,
    required this.onDownvote,
    required this.onComment,
    required this.onSave,
    required this.onMore,
    required this.collabGroupId,
    required this.collabMode,
    required this.collabMembers,
    required this.onMemberVoteApplied,
  });

  final int upvoteCount;
  final int downvoteCount;
  final int commentCount;
  final String? myVoteType;
  final bool isSaved;
  final VoidCallback? onUpvote;
  final VoidCallback? onDownvote;
  final VoidCallback? onComment;
  final VoidCallback? onSave;
  final VoidCallback? onMore;
  final String? collabGroupId;
  final String? collabMode;
  final List<CollabFeedMember> collabMembers;
  final void Function(String userId, bool nowVoted, int newCount)
      onMemberVoteApplied;

  bool get _isVersus =>
      collabMode == 'versus' &&
      collabGroupId != null &&
      collabGroupId!.isNotEmpty &&
      collabMembers.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (_isVersus) ..._buildVersusVotes() else ..._buildSoloVotes(),
        const SizedBox(height: 10),
        _RailButton(
          icon: Icons.chat_bubble_outline_rounded,
          label: '',
          centerLabel: commentCount > 0 ? _formatCount(commentCount) : null,
          activeColor: QuestColors.textPrimary,
          isActive: false,
          onTap: onComment,
        ),
        const SizedBox(height: 10),
        _RailButton(
          icon:
              isSaved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
          label: '',
          activeColor: QuestColors.accentYellow,
          isActive: isSaved,
          onTap: onSave,
        ),
        const SizedBox(height: 10),
        _RailButton(
          icon: Icons.more_horiz_rounded,
          label: '',
          activeColor: QuestColors.textPrimary,
          isActive: false,
          onTap: onMore,
        ),
      ],
    );
  }

  List<Widget> _buildSoloVotes() {
    final upActive = myVoteType == 'upvote';
    final downActive = myVoteType == 'downvote';
    return [
      _RailButton(
        icon: Icons.arrow_upward_rounded,
        label: _formatCount(upvoteCount),
        activeColor: QuestColors.osRed,
        isActive: upActive,
        onTap: onUpvote,
      ),
      const SizedBox(height: 10),
      _RailButton(
        icon: Icons.arrow_downward_rounded,
        label: _formatCount(downvoteCount),
        activeColor: QuestColors.osPrimary,
        isActive: downActive,
        onTap: onDownvote,
      ),
    ];
  }

  /// One avatar-vote button per visible collab member, ranked by votes
  /// so the leader sits at the top of the rail with a crown.
  List<Widget> _buildVersusVotes() {
    final visible = collabMembers.where((m) => m.showInFeed).toList()
      ..sort((a, b) => b.voteCount.compareTo(a.voteCount));
    if (visible.isEmpty) return _buildSoloVotes();

    final topVotes = visible.first.voteCount;
    final widgets = <Widget>[];
    for (var i = 0; i < visible.length; i++) {
      final m = visible[i];
      widgets.add(
        CollabVoteButton(
          key: ValueKey('reels-vote-${m.userId}'),
          member: m,
          groupId: collabGroupId!,
          accentColor: QuestColors.osRed,
          isLeader: m.voteCount == topVotes && topVotes > 0,
          avatarSize: 38,
          tapBoxWidth: 56,
          tapBoxHeight: 70,
          onVoteApplied: ({required bool nowVoted, required int newCount}) =>
              onMemberVoteApplied(m.userId, nowVoted, newCount),
        ),
      );
      if (i < visible.length - 1) {
        widgets.add(const SizedBox(height: 6));
      }
    }
    return widgets;
  }

  static String _formatCount(int n) {
    if (n <= 0) return '';
    if (n < 1000) return '$n';
    if (n < 10000) return '${(n / 1000).toStringAsFixed(1)}k';
    if (n < 1000000) return '${(n / 1000).floor()}k';
    return '${(n / 1000000).toStringAsFixed(1)}M';
  }
}

class _RailButton extends StatefulWidget {
  const _RailButton({
    required this.icon,
    required this.label,
    required this.activeColor,
    required this.isActive,
    this.centerLabel,
    this.onTap,
  });

  final IconData icon;
  final String label;
  // When non-null, rendered centered inside the icon instead of below it.
  // Used for the comment count so the number sits inside the chat bubble.
  final String? centerLabel;
  final Color activeColor;
  final bool isActive;
  final VoidCallback? onTap;

  @override
  State<_RailButton> createState() => _RailButtonState();
}

class _RailButtonState extends State<_RailButton> {
  double _scale = 1.0;

  @override
  Widget build(BuildContext context) {
    // Instagram-style: no squircle background, no chunky outline. The
    // icon floats directly on the video with a soft drop-shadow for
    // legibility on bright media. Color only flips when the action is
    // ACTIVE (e.g. user has upvoted → red heart, saved → white filled).
    final iconColor =
        widget.isActive ? widget.activeColor : QuestColors.textPrimary;
    final shadows = <Shadow>[
      Shadow(
        color: QuestColors.pureBlack.withAlpha(QuestColors.alphaInkSoft),
        blurRadius: 8,
        offset: const Offset(0, 1),
      ),
    ];

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _scale = 0.85),
      onTapCancel: () => setState(() => _scale = 1.0),
      onTapUp: (_) {
        setState(() => _scale = 1.0);
        HapticFeedback.selectionClick();
        widget.onTap?.call();
      },
      child: AnimatedScale(
        scale: _scale,
        duration: const Duration(milliseconds: 90),
        curve: Curves.easeOut,
        // The glyph stays 30px so the rail keeps its Instagram look, but
        // the hit box is padded out to the 44pt floor the spec requires.
        child: BsMinTouch(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Icon sits naked on the video. If a centerLabel is provided
              // (the comment glyph carries the count inside the bubble) we
              // keep that overlay, but stripped of the surrounding tile.
              widget.centerLabel == null
                  ? Icon(
                      widget.icon,
                      color: iconColor,
                      size: 30,
                      shadows: shadows,
                    )
                  : SizedBox(
                      width: 34,
                      height: 30,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Icon(widget.icon,
                              color: iconColor, size: 30, shadows: shadows),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 3),
                            child: Text(
                              widget.centerLabel!,
                              maxLines: 1,
                              style: TextStyle(
                                color: QuestColors.textPrimary,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                height: 1,
                                shadows: [
                                  Shadow(
                                    color: QuestColors.pureBlack
                                        .withAlpha(QuestColors.alphaInkSoft),
                                    blurRadius: 4,
                                    offset: const Offset(0, 1),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
              if (widget.label.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: QuestColors.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.1,
                    height: 1.1,
                    shadows: shadows,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── Reels avatar — rounded rectangle, image fills the full frame ────────────

class _ReelsAvatar extends StatelessWidget {
  const _ReelsAvatar({
    required this.imageUrl,
    required this.username,
    required this.size,
  });

  final String? imageUrl;
  final String username;
  final double size;

  @override
  Widget build(BuildContext context) {
    final fallback = Center(
      child: Text(
        username.isNotEmpty ? username[0].toUpperCase() : '?',
        style: TextStyle(
          color: QuestColors.textPrimary,
          fontSize: size * 0.42,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(QuestSpacing.radiusSm),
      child: Container(
        width: size,
        height: size,
        color: QuestColors.pureBlack.withAlpha(140),
        child: (imageUrl == null || imageUrl!.isEmpty)
            ? fallback
            : CachedNetworkImage(
                imageUrl: imageUrl!,
                fit: BoxFit.cover,
                width: size,
                height: size,
                placeholder: (_, __) => const SizedBox.shrink(),
                errorWidget: (_, __, ___) => fallback,
              ),
      ),
    );
  }
}

// ── Bottom meta block ───────────────────────────────────────────────────────

class _BottomMeta extends StatelessWidget {
  const _BottomMeta({
    required this.displayName,
    required this.username,
    required this.avatarUrl,
    required this.questTitle,
    required this.xpReward,
    required this.caption,
    required this.timeAgo,
    required this.modeBadge,
    required this.mediaCount,
    required this.mediaIndex,
    required this.isCollab,
    required this.collabMode,
    required this.collabMembers,
    required this.activeMemberIndex,
    required this.onUserTap,
    required this.onTap,
  });

  final String displayName;
  final String username;
  final String? avatarUrl;
  final String questTitle;
  final int xpReward;
  final String? caption;
  final String timeAgo;
  final String? modeBadge;
  final int mediaCount;
  final int mediaIndex;
  // Collab context — when true, the avatar / handle / caption rendered
  // here belong to the currently-swiped member (passed in via the parent
  // since the parent owns the page index).
  final bool isCollab;
  final String? collabMode;
  final List<CollabFeedMember> collabMembers;
  final int activeMemberIndex;
  final VoidCallback? onUserTap;
  final VoidCallback? onTap;

  bool get _isVersus => collabMode == 'versus';

  /// Coop badges go green to match the rest of the coop chrome, versus
  /// stays coral. Anything else falls back to coral too.
  Color get _modeBadgeGround => _isVersus
      ? QuestColors.osRed
      : (collabMode == 'with' ? QuestColors.osSuccess : QuestColors.osRed);

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (mediaCount > 1) ...[
          Align(
            alignment: Alignment.centerLeft,
            child: _PageDots(count: mediaCount, current: mediaIndex),
          ),
          const SizedBox(height: 10),
        ],
        if (modeBadge != null && modeBadge!.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: _modeBadgeGround,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: QuestColors.pureWhite, width: 2),
            ),
            child: Text(
              modeBadge!.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: QuestColors.onAccent(_modeBadgeGround),
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
        GestureDetector(
          onTap: onUserTap,
          behavior: HitTestBehavior.opaque,
          child: Row(
            children: [
              _ReelsAvatar(
                imageUrl: avatarUrl,
                username: username,
                size: 42,
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FitText(
                      '$username · $timeAgo',
                      minFontSize: 11,
                      style: const TextStyle(
                        color: QuestColors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.3,
                        shadows: [
                          Shadow(
                              color: QuestColors.pureBlack,
                              blurRadius: 8,
                              offset: Offset(0, 1))
                        ],
                      ),
                    ),
                    // Sub-line shows EITHER the displayName (solo) OR a
                    // mode-tinted "+N OTHERS" line when collab so the
                    // user can tell at a glance how many people are in
                    // this quest while they're viewing one of them.
                    if (isCollab && collabMembers.length > 1)
                      Text(
                        '+ ${collabMembers.length - 1} OTHERS · '
                        '${(_isVersus ? "VS" : "COOP")}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: _isVersus
                              ? QuestColors.osRed
                              : QuestColors.osSuccess,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.0,
                          shadows: const [
                            Shadow(
                                color: QuestColors.pureBlack,
                                blurRadius: 8,
                                offset: Offset(0, 1)),
                          ],
                        ),
                      )
                    else if (displayName.trim().isNotEmpty)
                      Text(
                        displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: QuestColors.textPrimary.withAlpha(210),
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          shadows: const [
                            Shadow(
                                color: QuestColors.pureBlack,
                                blurRadius: 8,
                                offset: Offset(0, 1)),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 6,
            runSpacing: 6,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: QuestColors.accentYellow,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: QuestColors.pureBlack, width: 2),
                ),
                child: Text(
                  '+$xpReward XP',
                  style: const TextStyle(
                    color: QuestColors.pureBlack,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 240),
                child: Text(
                  questTitle.toUpperCase(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: QuestColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                    shadows: [
                      Shadow(
                          color: QuestColors.pureBlack,
                          blurRadius: 8,
                          offset: Offset(0, 1))
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        if (caption != null && caption!.trim().isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            caption!,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: QuestColors.textPrimary.withAlpha(235),
              fontSize: 13,
              fontWeight: FontWeight.w500,
              height: 1.3,
              shadows: const [
                Shadow(
                    color: QuestColors.pureBlack,
                    blurRadius: 8,
                    offset: Offset(0, 1))
              ],
            ),
          ),
        ],
      ],
    );
  }
}

// ── Carousel slot ───────────────────────────────────────────────────────────

/// One page of the horizontal carousel. For collab posts the slot points
/// to the member who owns the media; for solo posts member is null and
/// we use the post-level data instead.
///
/// `isWaiting == true` marks a placeholder slide for a collab member who
/// hasn't uploaded yet — `url` is empty in that case and the card shows a
/// "WAITING FOR @user" panel instead of a media item.
class _CarouselSlot {
  const _CarouselSlot({
    required this.member,
    required this.url,
    this.isWaiting = false,
  });
  final CollabFeedMember? member;
  final String url;
  final bool isWaiting;
}

// ── Waiting-for-member placeholder ──────────────────────────────────────────

/// Shown in the carousel for a collab member who hasn't uploaded their
/// piece yet. The bottom meta still flips to that member so the user knows
/// who they're waiting on.
class _WaitingForMember extends StatelessWidget {
  const _WaitingForMember({
    required this.member,
    required this.hasExpired,
  });
  final CollabFeedMember member;
  final bool hasExpired;

  static const Color _waitingBg =
      Color(0xFF111111); // Screen-specific colour — not a theme token.

  @override
  Widget build(BuildContext context) {
    final name =
        member.username.isNotEmpty ? member.username : member.displayName;
    final headline = hasExpired ? "DIDN'T POST" : 'WAITING FOR';
    final subline =
        hasExpired ? 'ran out of time on this quest' : "hasn't posted yet";
    return Container(
      color: _waitingBg,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  borderRadius:
                      BorderRadius.circular(QuestSpacing.radiusSm + 6),
                  border: Border.all(
                    color:
                        hasExpired ? QuestColors.osRed : QuestColors.pureWhite,
                    width: 2,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: (member.avatarUrl == null || member.avatarUrl!.isEmpty)
                    ? ColoredBox(
                        color: QuestColors.pureBlack.withAlpha(180),
                        child: Center(
                          child: Text(
                            name.isNotEmpty ? name[0].toUpperCase() : '?',
                            style: const TextStyle(
                              color: QuestColors.textPrimary,
                              fontSize: 36,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      )
                    : CachedNetworkImage(
                        imageUrl: member.avatarUrl!,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => const SizedBox.shrink(),
                        errorWidget: (_, __, ___) => const SizedBox.shrink(),
                      ),
              ),
              const SizedBox(height: 18),
              Text(
                headline,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: hasExpired
                      ? QuestColors.osRed
                      : QuestColors.textPrimary.withAlpha(150),
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 2.0,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '@$name',
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: QuestColors.textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.4,
                  shadows: [
                    Shadow(
                      color: QuestColors.pureBlack
                          .withAlpha(QuestColors.alphaInkSoft),
                      blurRadius: 6,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Text(
                subline,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: QuestColors.textPrimary.withAlpha(180),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
