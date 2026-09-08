import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/theme/bsheel_design.dart';
import '../../../../shared/widgets/bsheel_widgets.dart';
import '../providers/pending_submissions_provider.dart';
import 'inline_video.dart';

/// The proof-media block of the review surface.
///
/// Every asset carries an explicit "MARK VIEWED" toggle. Auto-marks fire
/// where they can (image loads, video reaches the watch threshold, image
/// error), but the manual toggle is always available — auto-detection on
/// web can silently fail (CORS, codec mismatch, an image URL fed into a
/// `<video>` element) and we never want the moderator trapped with no way
/// to unblock the approve/reject buttons.
///
/// Arcade Pop: every frame is a 2px ink outline on a 14px radius with a
/// hard offset shadow — 5px on the proof frame itself, 4px on the extra
/// assets behind it. Nothing that hasn't arrived yet is a spinner: a
/// missing asset is [BsheelMediaPlaceholder] and a loading one is
/// [BsheelSkeleton], both shaped like the frame they will become.
class MediaSection extends StatefulWidget {
  const MediaSection({
    super.key,
    required this.submission,
    required this.viewedIndices,
    required this.onMediaViewed,
    this.maxWidth = double.infinity,
  });

  final PendingSubmission submission;

  /// Room the evidence column can actually give this block. Frames fill
  /// it, so the media never paints outside the column on a narrow window.
  final double maxWidth;

  /// Indices the page has already recorded as viewed. Drives the jade
  /// checkmark state on each tile.
  final Set<int> viewedIndices;

  /// Called with the 0-based media index when an asset becomes viewed —
  /// either via auto-detection or the manual toggle. Idempotent at the page
  /// level (page de-duplicates with a Set).
  final void Function(int index) onMediaViewed;

  @override
  State<MediaSection> createState() => _MediaSectionState();
}

/// Bounds for the evidence frame. File-level because the extra-asset frame
/// further down needs the same two numbers, and it previously repeated them
/// as literals — which is why `_maxFrameHeight` read as unused.
const double _minFrameHeight = 220;
const double _maxFrameHeight = 420;

class _MediaSectionState extends State<MediaSection> {
  /// The proof frame is the heaviest surface in the evidence column.
  static const double _proofDepth = 5;

  /// Extra assets sit one step behind it.
  static const double _extraDepth = 4;

  /// Width to fall back on when the host gives no bound.
  static const double _unboundedWidth = 420;

  int _activeImage = 0;

  /// Per-URL type detection. The submission row has a single `mediaType`
  /// column but a multi-asset submission can mix images and videos — trust
  /// the file extension over the row-level field.
  bool _urlIsVideo(String url) {
    final l = url.toLowerCase();
    return l.endsWith('.mp4') ||
        l.endsWith('.mov') ||
        l.endsWith('.webm') ||
        l.endsWith('.m4v');
  }

  bool _isViewed(int i) => widget.viewedIndices.contains(i);

  /// The width the frames take: whatever the column can spare.
  double get _width =>
      widget.maxWidth.isFinite ? math.max(widget.maxWidth, 0) : _unboundedWidth;

  @override
  Widget build(BuildContext context) {
    final urls = widget.submission.mediaUrls;

    if (urls.isEmpty) return _noMedia();

    if (urls.length == 1) {
      return _wrapWithToggle(
        index: 0,
        child: _asset(urls.first, 0, depth: _proofDepth),
      );
    }

    if (urls.every((u) => !_urlIsVideo(u))) return _imageBlockMulti(urls);

    return _mixedStack(urls);
  }

  /// A pending submission with no media is a data fault, not an empty
  /// state — say so in the frame the proof would have filled.
  Widget _noMedia() {
    return BsheelMediaPlaceholder(
      label: 'No proof media',
      width: _width,
      height: _minFrameHeight,
      depth: _proofDepth,
    );
  }

  /// One asset, rendered by its own type. Videos draw their own frame.
  Widget _asset(String url, int index, {required double depth}) {
    if (_urlIsVideo(url)) {
      return SizedBox(
        width: _width,
        child: InlineVideo(
          url: url,
          depth: depth,
          onWatched: () => widget.onMediaViewed(index),
        ),
      );
    }
    return _ProofImage(
      url: url,
      width: _width,
      depth: depth,
      onLoaded: () => widget.onMediaViewed(index),
    );
  }

  // ── Mixed stack ────────────────────────────────────────────────────────────

  Widget _mixedStack(List<String> urls) {
    final videoCount = urls.where(_urlIsVideo).length;
    final imageCount = urls.length - videoCount;

    return SizedBox(
      width: _width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: BsheelPill(
              _mixedLabel(videoCount, imageCount, urls.length),
            ),
          ),
          for (var i = 0; i < urls.length; i++) ...[
            _wrapWithToggle(
              index: i,
              child: _asset(
                urls[i],
                i,
                depth: i == 0 ? _proofDepth : _extraDepth,
              ),
            ),
            if (i < urls.length - 1) const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }

  String _mixedLabel(int videos, int images, int total) {
    if (videos > 0 && images > 0) {
      return '$total items · ${videos}v ${images}img';
    }
    if (videos > 0) return '$videos ${videos == 1 ? 'video' : 'videos'}';
    return '$images ${images == 1 ? 'photo' : 'photos'}';
  }

  // ── All-image multi block ─────────────────────────────────────────────────

  Widget _imageBlockMulti(List<String> urls) {
    final activeUrl = urls[_activeImage];

    return SizedBox(
      width: _width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _wrapWithToggle(
            index: _activeImage,
            child: Stack(
              children: [
                _ProofImage(
                  key: ValueKey(activeUrl),
                  url: activeUrl,
                  width: _width,
                  depth: _proofDepth,
                  onLoaded: () => widget.onMediaViewed(_activeImage),
                ),
                Positioned(
                  top: 8,
                  left: 8,
                  child: BsheelPill('${_activeImage + 1} of ${urls.length}'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: BsheelLayout.minTarget,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: urls.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (context, i) => _StripThumb(
                url: urls[i],
                selected: i == _activeImage,
                viewed: _isViewed(i),
                onTap: () => setState(() => _activeImage = i),
                onSettled: () => widget.onMediaViewed(i),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Toggle wrapper ────────────────────────────────────────────────────────
  // Overlays a "MARK VIEWED" / "VIEWED" pill on the bottom-right of any
  // media item so the moderator always has an explicit way to clear the
  // gate that holds the approve and reject buttons.

  Widget _wrapWithToggle({required int index, required Widget child}) {
    final viewed = _isViewed(index);
    return SizedBox(
      width: _width,
      child: Stack(
        children: [
          child,
          Positioned(
            right: 8,
            bottom: 8,
            child: _ViewedToggle(
              viewed: viewed,
              onTap: viewed ? null : () => widget.onMediaViewed(index),
            ),
          ),
        ],
      ),
    );
  }
}

/// The gate's only manual control. Jade once viewed, because a cleared
/// gate is the thing that lets an approval through.
class _ViewedToggle extends StatelessWidget {
  const _ViewedToggle({required this.viewed, required this.onTap});

  final bool viewed;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ground = viewed ? BsheelColors.success : BsheelColors.card;
    final fg = BsheelColors.onAccent(ground);

    final pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: ground,
        borderRadius: BorderRadius.circular(BsheelRadii.full),
        border: const Border.fromBorderSide(BsheelBorders.inkSide),
        boxShadow: viewed ? null : BsheelShadows.sm,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            viewed ? Icons.check_rounded : Icons.visibility_outlined,
            size: 13,
            color: fg,
          ),
          const SizedBox(width: 5),
          Text(
            viewed ? 'VIEWED' : 'MARK VIEWED',
            style: BsheelType.labelSm.copyWith(color: fg),
          ),
        ],
      ),
    );

    // The pill keeps its own size; the box around it carries the 44px
    // minimum click target.
    return SizedBox(
      height: BsheelLayout.minTarget,
      child: Center(
        widthFactor: 1,
        child: viewed
            ? pill
            : BsheelPressable(onTap: onTap, depth: 3, child: pill),
      ),
    );
  }
}

/// One proof photo in its frame. The signed URL is used verbatim.
class _ProofImage extends StatelessWidget {
  const _ProofImage({
    super.key,
    required this.url,
    required this.width,
    required this.depth,
    required this.onLoaded,
  });

  final String url;
  final double width;
  final double depth;
  final VoidCallback onLoaded;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      constraints: const BoxConstraints(
        minHeight: _minFrameHeight,
        maxHeight: _maxFrameHeight,
      ),
      decoration: BoxDecoration(
        color: BsheelColors.surface,
        borderRadius: BorderRadius.circular(BsheelRadii.lg),
        border: const Border.fromBorderSide(BsheelBorders.inkSide),
        boxShadow: BsheelShadows.hard(depth),
      ),
      clipBehavior: Clip.antiAlias,
      child: Image.network(
        url,
        fit: BoxFit.contain,
        frameBuilder: (context, child, frame, _) {
          if (frame != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) => onLoaded());
          }
          return child;
        },
        loadingBuilder: (_, child, progress) => progress == null
            ? child
            : const BsheelSkeleton(height: 220, radius: BsheelRadii.lg),
        // A failed frame still counts as viewed — the moderator saw that
        // there are no bytes to look at, and there is no way for them to
        // "view" media that never arrived.
        errorBuilder: (_, __, ___) {
          WidgetsBinding.instance.addPostFrameCallback((_) => onLoaded());
          return const BsheelMediaPlaceholder(
            label: 'Proof unavailable',
            height: 220,
          );
        },
      ),
    );
  }
}

/// One tile in the photo strip under a multi-photo proof frame.
class _StripThumb extends StatelessWidget {
  const _StripThumb({
    required this.url,
    required this.selected,
    required this.viewed,
    required this.onTap,
    required this.onSettled,
  });

  final String url;
  final bool selected;
  final bool viewed;
  final VoidCallback onTap;
  final VoidCallback onSettled;

  @override
  Widget build(BuildContext context) {
    const size = 38.0;

    return BsheelPressable(
      onTap: onTap,
      depth: selected ? 3 : 0,
      child: Center(
        widthFactor: 1,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: BsheelColors.surface,
                borderRadius: BorderRadius.circular(BsheelRadii.sm),
                border: const Border.fromBorderSide(BsheelBorders.inkSide),
                boxShadow: selected ? BsheelShadows.sm : null,
              ),
              clipBehavior: Clip.antiAlias,
              child: Image.network(
                url,
                fit: BoxFit.cover,
                frameBuilder: (context, child, frame, _) {
                  if (frame != null) {
                    WidgetsBinding.instance.addPostFrameCallback(
                      (_) => onSettled(),
                    );
                  }
                  return child;
                },
                loadingBuilder: (_, child, progress) => progress == null
                    ? child
                    : const BsheelSkeleton(
                        height: size,
                        width: size,
                        radius: BsheelRadii.sm,
                      ),
                // A failed strip thumbnail still counts, for the same
                // reason the main frame does.
                errorBuilder: (_, __, ___) {
                  WidgetsBinding.instance.addPostFrameCallback(
                    (_) => onSettled(),
                  );
                  return const BsheelMediaPlaceholder(
                    label: '',
                    width: size,
                    height: size,
                    radius: BsheelRadii.sm,
                  );
                },
              ),
            ),
            if (viewed)
              Positioned(
                right: -3,
                bottom: -3,
                child: Container(
                  padding: const EdgeInsets.all(1),
                  decoration: const BoxDecoration(
                    color: BsheelColors.success,
                    shape: BoxShape.circle,
                    border: Border.fromBorderSide(
                      BsheelBorders.inkSide,
                    ),
                  ),
                  child: Icon(
                    Icons.check_rounded,
                    size: 9,
                    color: BsheelColors.onAccent(BsheelColors.success),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
