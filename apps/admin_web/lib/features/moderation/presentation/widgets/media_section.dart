import '../../../../core/theme/bsheel_design.dart';
import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';

import '../providers/pending_submissions_provider.dart';
import 'inline_video.dart';

// Screen-specific colours — not theme tokens.
const Color _mediaPanelBorder = Color(0xFF2A2A2A);

/// The left-hand media block of a pending-submission card.
///
/// Each asset has an explicit "✓ MARK VIEWED" toggle. Auto-marks fire when
/// possible (image loads, video reaches the watch threshold, image error),
/// but the manual toggle is always available — auto-detection on web can
/// silently fail (CORS, codec mismatch, an image URL fed into a `<video>`
/// element) and we never want the admin trapped with no way to unblock the
/// approve/deny buttons.
class MediaSection extends StatefulWidget {
  const MediaSection({
    super.key,
    required this.submission,
    required this.viewedIndices,
    required this.onMediaViewed,
  });

  final PendingSubmission submission;

  /// Indices the page has already recorded as viewed. Drives the green
  /// checkmark state on each tile.
  final Set<int> viewedIndices;

  /// Called with the 0-based media index when an asset becomes viewed —
  /// either via auto-detection or the manual toggle. Idempotent at the page
  /// level (page de-duplicates with a Set).
  final void Function(int index) onMediaViewed;

  @override
  State<MediaSection> createState() => _MediaSectionState();
}

class _MediaSectionState extends State<MediaSection> {
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

  @override
  Widget build(BuildContext context) {
    final urls = widget.submission.mediaUrls;

    if (urls.isEmpty) return _placeholder();

    final allImages = urls.every((u) => !_urlIsVideo(u));

    if (urls.length == 1 && allImages) {
      return _wrapWithToggle(
        index: 0,
        child: _ImageThumb(
          url: urls.first,
          size: 140,
          onLoaded: () => widget.onMediaViewed(0),
        ),
        width: 140,
      );
    }

    if (allImages) return _imageBlockMulti(urls);

    return _mixedStack(urls);
  }

  Widget _placeholder() {
    return Container(
      width: 140,
      height: 140,
      decoration: BoxDecoration(
        color: BsheelColors.ink,
        borderRadius: BorderRadius.circular(BsheelRadii.md),
      ),
      child: const Icon(Icons.image_outlined, color: BsheelColors.inkMuted),
    );
  }

  // ── Mixed stack ────────────────────────────────────────────────────────────

  Widget _mixedStack(List<String> urls) {
    final videoCount = urls.where(_urlIsVideo).length;
    final imageCount = urls.length - videoCount;

    return SizedBox(
      width: 320,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (urls.length > 1)
            Padding(
              padding: const EdgeInsets.only(bottom: QuestSpacing.xs),
              child: _MediaCountBadge(
                icon: Icons.collections,
                label: _mixedLabel(videoCount, imageCount, urls.length),
              ),
            ),
          for (var i = 0; i < urls.length; i++) ...[
            _wrapWithToggle(
              index: i,
              width: 320,
              child: _urlIsVideo(urls[i])
                  ? InlineVideo(
                      url: urls[i],
                      onWatched: () => widget.onMediaViewed(i),
                    )
                  : _StackImage(
                      url: urls[i],
                      onLoaded: () => widget.onMediaViewed(i),
                    ),
            ),
            if (i < urls.length - 1) const SizedBox(height: QuestSpacing.sm),
          ],
        ],
      ),
    );
  }

  String _mixedLabel(int videos, int images, int total) {
    if (videos > 0 && images > 0) {
      return '$total ITEMS · ${videos}V $images${images == 1 ? 'IMG' : 'IMGS'}';
    }
    if (videos > 0) return '$videos ${videos == 1 ? 'VIDEO' : 'VIDEOS'}';
    return '$images ${images == 1 ? 'PHOTO' : 'PHOTOS'}';
  }

  // ── All-image multi block ─────────────────────────────────────────────────

  Widget _imageBlockMulti(List<String> urls) {
    final activeUrl = urls[_activeImage];

    return SizedBox(
      width: 140,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _wrapWithToggle(
            index: _activeImage,
            width: 140,
            child: Stack(
              children: [
                _ImageThumb(
                  url: activeUrl,
                  size: 140,
                  key: ValueKey(activeUrl),
                  onLoaded: () => widget.onMediaViewed(_activeImage),
                ),
                Positioned(
                  top: 4,
                  left: 4,
                  child: _MediaCountBadge(
                    icon: Icons.photo_library,
                    label: '${_activeImage + 1}/${urls.length}',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: QuestSpacing.xs),
          SizedBox(
            height: 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: urls.length,
              separatorBuilder: (_, __) => const SizedBox(width: 4),
              itemBuilder: (context, i) {
                final selected = i == _activeImage;
                final viewed = _isViewed(i);
                return GestureDetector(
                  onTap: () => setState(() => _activeImage = i),
                  child: Stack(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          borderRadius:
                              BorderRadius.circular(BsheelRadii.md),
                          border: Border.all(
                            color: selected
                                ? BsheelColors.pureWhite
                                : _mediaPanelBorder,
                            width: BsheelBorders.thin,
                          ),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Image.network(
                          urls[i],
                          fit: BoxFit.cover,
                          frameBuilder: (context, child, frame, _) {
                            if (frame != null) {
                              WidgetsBinding.instance.addPostFrameCallback(
                                  (_) => widget.onMediaViewed(i),);
                            }
                            return child;
                          },
                          // A failed strip thumbnail still counts — admin saw
                          // the broken-image indicator, no way for them to
                          // "view" missing bytes.
                          errorBuilder: (_, __, ___) {
                            WidgetsBinding.instance.addPostFrameCallback(
                                (_) => widget.onMediaViewed(i),);
                            return Container(
                              color: BsheelColors.ink,
                              child: const Icon(
                                Icons.broken_image,
                                color: BsheelColors.inkMuted,
                                size: 14,
                              ),
                            );
                          },
                        ),
                      ),
                      if (viewed)
                        const Positioned(
                          right: 1,
                          bottom: 1,
                          child: Icon(
                            Icons.check_circle,
                            color: BsheelColors.success,
                            size: 14,
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
    );
  }

  // ── Toggle wrapper ────────────────────────────────────────────────────────
  // Overlays a "MARK VIEWED" / "✓ VIEWED" pill on the bottom-right of any
  // media item so the admin always has an explicit way to clear the gate.

  Widget _wrapWithToggle({
    required int index,
    required Widget child,
    required double width,
  }) {
    final viewed = _isViewed(index);
    return SizedBox(
      width: width,
      child: Stack(
        children: [
          child,
          Positioned(
            right: 6,
            bottom: 6,
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

class _ViewedToggle extends StatelessWidget {
  const _ViewedToggle({required this.viewed, required this.onTap});

  final bool viewed;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color =
        viewed ? BsheelColors.success : BsheelColors.pureWhite;
    return Material(
      color: BsheelColors.pureBlack.withAlpha(190),
      borderRadius: BorderRadius.circular(BsheelRadii.full),
      child: InkWell(
        borderRadius: BorderRadius.circular(BsheelRadii.full),
        onTap: onTap,
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(BsheelRadii.full),
            border: Border.all(
                color: color.withAlpha(180), width: BsheelBorders.thin,),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                viewed ? Icons.check_circle : Icons.visibility_outlined,
                size: 12,
                color: color,
              ),
              const SizedBox(width: 4),
              Text(
                viewed ? 'VIEWED' : 'MARK VIEWED',
                style: TextStyle(
                  color: color,
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.6,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ImageThumb extends StatelessWidget {
  const _ImageThumb({
    super.key,
    required this.url,
    required this.size,
    required this.onLoaded,
  });

  final String url;
  final double size;
  final VoidCallback onLoaded;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(BsheelRadii.md),
      child: Image.network(
        url,
        width: size,
        height: size,
        fit: BoxFit.cover,
        frameBuilder: (context, child, frame, _) {
          if (frame != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) => onLoaded());
          }
          return child;
        },
        errorBuilder: (_, __, ___) {
          WidgetsBinding.instance.addPostFrameCallback((_) => onLoaded());
          return Container(
            width: size,
            height: size,
            color: BsheelColors.ink,
            child: const Icon(Icons.broken_image, color: BsheelColors.inkMuted),
          );
        },
      ),
    );
  }
}

/// Image renderer for the mixed-stack layout — full-card-width box, height
/// caps at 220 so portrait photos don't dominate the card.
class _StackImage extends StatelessWidget {
  const _StackImage({required this.url, required this.onLoaded});

  final String url;
  final VoidCallback onLoaded;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 220),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: BsheelColors.pureBlack,
          borderRadius: BorderRadius.circular(BsheelRadii.md),
          border: Border.all(
              color: _mediaPanelBorder, width: BsheelBorders.thin,),
        ),
        clipBehavior: Clip.antiAlias,
        child: Image.network(
          url,
          fit: BoxFit.contain,
          frameBuilder: (context, child, frame, _) {
            if (frame != null) {
              WidgetsBinding.instance
                  .addPostFrameCallback((_) => onLoaded());
            }
            return child;
          },
          errorBuilder: (_, __, ___) {
            WidgetsBinding.instance.addPostFrameCallback((_) => onLoaded());
            return Container(
              height: 120,
              color: BsheelColors.ink,
              child: const Center(
                child: Icon(Icons.broken_image, color: BsheelColors.inkMuted),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _MediaCountBadge extends StatelessWidget {
  const _MediaCountBadge({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: BsheelColors.pureBlack.withAlpha(180),
        borderRadius: BorderRadius.circular(BsheelRadii.full),
        border: Border.all(color: BsheelColors.pureWhite.withAlpha(80)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: BsheelColors.pureWhite),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              color: BsheelColors.pureWhite,
              fontSize: 10,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}
