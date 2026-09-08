// Web-only inline video player for the admin moderation surfaces.
//
// Why this widget exists: Cloudflare R2 serves submission videos with a
// Content-Disposition that makes plain `launchUrl(...)` trigger a download
// instead of in-tab playback. Embedding the URL in a real `<video>` element
// via `HtmlElementView` lets the browser stream it as media, which sidesteps
// Content-Disposition entirely.
//
// `admin_web` only ever runs on Flutter web so this file uses `package:web`
// directly — there is no mobile target to abstract over.

import 'dart:js_interop';
import 'dart:math' as math;
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

import '../../../../core/theme/bsheel_design.dart';
import '../../../../shared/widgets/bsheel_widgets.dart';

/// Plays a video URL inline using the browser's native `<video>` element.
///
/// Calls [onWatched] exactly once after the user has watched at least
/// [watchedAfterFraction] of the total duration, OR — as a shortcut for
/// long videos — min([watchedAfterSeconds], duration × [watchedAfterFraction])
/// seconds. The seconds shortcut scales with duration so a short clip still
/// requires real playback (a 4s clip needs 2s, not a fixed low threshold);
/// it only fires early for videos longer than
/// [watchedAfterSeconds] ÷ [watchedAfterFraction] seconds. Used by the
/// moderation queue to gate the approve/reject actions until the moderator
/// has actually looked at the media.
///
/// The player draws itself as an Arcade Pop media frame: 2px ink outline,
/// 14px radius, hard offset shadow at [depth].
class InlineVideo extends StatefulWidget {
  const InlineVideo({
    super.key,
    required this.url,
    this.onWatched,
    this.watchedAfterSeconds = 10,
    this.watchedAfterFraction = 0.5,
    this.aspectRatio = 16 / 9,
    this.autoplay = false,
    this.depth = 5,
  });

  final String url;
  final VoidCallback? onWatched;
  final double watchedAfterSeconds;
  final double watchedAfterFraction;
  final double aspectRatio;
  final bool autoplay;

  /// Hard-shadow offset. 5 is the proof frame; 4 an extra asset behind it.
  final double depth;

  @override
  State<InlineVideo> createState() => _InlineVideoState();
}

class _InlineVideoState extends State<InlineVideo> {
  late final String _viewType;
  bool _watchedFired = false;
  // Set if the <video> element fires an `error` (unsupported codec/container,
  // e.g. a stray HEVC upload the browser can't decode, or a network failure).
  // We then swap the player for a fallback with an "open original" escape hatch
  // so a moderator is never stuck staring at a dead black box.
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    // Unique view type per instance — multiple cards on the same page each
    // need their own factory, otherwise the platform-view registry rejects
    // the duplicate registration.
    _viewType = 'inline-video-${widget.url.hashCode}-${identityHashCode(this)}';

    ui_web.platformViewRegistry.registerViewFactory(
      _viewType,
      (int viewId) {
        final video = web.HTMLVideoElement()
          ..src = widget.url
          ..controls = true
          ..preload = 'metadata'
          ..muted = widget.autoplay
          ..autoplay = widget.autoplay
          ..crossOrigin = 'anonymous';
        video.setAttribute('playsinline', '');
        video.style
          ..width = '100%'
          ..height = '100%'
          ..objectFit = 'contain'
          // The letterbox behind the frame is ink, not black: a colder
          // black beside the cream page reads as a second palette.
          ..backgroundColor = _cssColor(BsheelColors.ink)
          ..border = '0';

        video.addEventListener(
          'timeupdate',
          ((web.Event _) {
            if (_watchedFired) return;
            final dur = video.duration;
            final cur = video.currentTime;
            // Watched = reached the fraction gate (default 50% of the
            // video), OR — for long videos only — a seconds shortcut of
            // min(watchedAfterSeconds, duration × fraction). Capping the
            // shortcut at the fraction-equivalent means a 3-second clip
            // still needs ~1.5s of playback; a fixed low threshold would
            // count every video as "watched" almost immediately.
            // Before metadata loads `duration` is NaN, so `dur > 0` is
            // false and only the conservative raw-seconds fallback applies.
            final hitFraction =
                dur > 0 && cur / dur >= widget.watchedAfterFraction;
            final secondsGate = dur > 0
                ? math.min(
                    widget.watchedAfterSeconds,
                    dur * widget.watchedAfterFraction,
                  )
                : widget.watchedAfterSeconds;
            final hitSeconds = cur >= secondsGate;
            if (hitFraction || hitSeconds) {
              _watchedFired = true;
              widget.onWatched?.call();
            }
          }).toJS,
        );

        // A decode/network failure must not trap the moderator: mark the media
        // "viewed" (they can't watch bytes the browser can't play) so the
        // approve/reject gate unlocks, and flip to the fallback UI.
        video.addEventListener(
          'error',
          ((web.Event _) {
            if (!mounted || _failed) return;
            _failed = true;
            widget.onWatched?.call();
            setState(() {});
          }).toJS,
        );

        return video;
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) return _fallback();

    return AspectRatio(
      aspectRatio: widget.aspectRatio,
      child: _frame(child: HtmlElementView(viewType: _viewType)),
    );
  }

  /// The media frame every proof asset shares.
  Widget _frame({required Widget child, Color? color}) {
    return Container(
      decoration: BoxDecoration(
        color: color ?? BsheelColors.ink,
        borderRadius: BorderRadius.circular(BsheelRadii.lg),
        border: const Border.fromBorderSide(BsheelBorders.inkSide),
        boxShadow: BsheelShadows.hard(widget.depth),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }

  /// Shown when the browser can't play the video. Opens the (signed) source
  /// in a new tab so the moderator can still download/inspect it natively.
  Widget _fallback() {
    return AspectRatio(
      aspectRatio: widget.aspectRatio,
      child: _frame(
        color: BsheelColors.surface,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.videocam_off_outlined,
                color: BsheelColors.inkMuted,
              ),
              const SizedBox(height: 8),
              const BsheelLabel('Can’t play in browser'),
              const SizedBox(height: 4),
              const Text(
                'The browser could not decode this file. Nothing is wrong '
                'with the submission — open the original to inspect it.',
                textAlign: TextAlign.center,
                style: BsheelType.bodyXs,
              ),
              const SizedBox(height: 10),
              BsheelButton.ghost(
                label: 'Open original',
                icon: Icons.open_in_new_rounded,
                small: true,
                onPressed: () => web.window.open(widget.url, '_blank'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A token colour as the `#rrggbb` string the DOM needs. Keeps the
/// `<video>` element on the same palette as the frame around it without
/// a hex literal living in this file.
String _cssColor(Color color) {
  final rgb = color.toARGB32() & 0xFFFFFF;
  return '#${rgb.toRadixString(16).padLeft(6, '0')}';
}
