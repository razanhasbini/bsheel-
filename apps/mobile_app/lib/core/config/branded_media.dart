import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:app_core/app_core.dart';
import 'package:flutter/painting.dart';

/// Renders a proof photo with the Bsheel template baked into it.
///
/// A shared link carries the template as text, but a photo saved to
/// somebody's camera roll and reposted somewhere else arrives with nothing
/// attached — no quest, no place, no Bsheel. Burning the caption band into
/// the image is what makes a saved photo still say where it came from.
///
/// The band is ADDED below the photo rather than laid over it. An overlay
/// would cover whatever the player actually photographed, which on a proof
/// image is the one part that matters.
abstract final class BrandedMedia {
  /// Width the band's text is laid out against, and the minimum output
  /// width. A very small source image is scaled up to this so the caption
  /// stays legible rather than shrinking with it.
  static const double _minWidth = 1080;

  /// Draws [imageBytes] with a Bsheel footer and returns PNG bytes.
  ///
  /// Returns null if the bytes are not a decodable image — the caller then
  /// saves the original rather than failing the download, because a photo
  /// without the band is still the photo they asked for.
  static Future<Uint8List?> brand(
    Uint8List imageBytes, {
    required String questTitle,
    String? country,
    String? caption,
    String? username,
  }) async {
    final ui.Image source;
    try {
      final codec = await ui.instantiateImageCodec(imageBytes);
      source = (await codec.getNextFrame()).image;
    } catch (_) {
      return null;
    }

    final scale = source.width < _minWidth ? _minWidth / source.width : 1.0;
    final width = source.width * scale;
    final photoHeight = source.height * scale;

    final headline = [
      if (questTitle.trim().isNotEmpty) '"${questTitle.trim()}"',
      if ((country ?? '').trim().isNotEmpty) country!.trim(),
    ].join('  ·  ');

    final pad = width * 0.045;
    final wordmark = _layout('BSHEEL', width - pad * 2,
        size: width * 0.040,
        weight: FontWeight.w800,
        spacing: width * 0.006,
        color: QuestColors.osPrimary);
    final title = _layout(
      headline.isNotEmpty
          ? headline
          : (username ?? '').isNotEmpty
              ? 'A quest by @$username'
              : 'A quest',
      width - pad * 2,
      size: width * 0.034,
      weight: FontWeight.w700,
      maxLines: 2,
      color: QuestColors.osTextPrimary,
    );
    final words = (caption ?? '').trim().isEmpty
        ? null
        : _layout(caption!.trim(), width - pad * 2,
            size: width * 0.026,
            weight: FontWeight.w400,
            maxLines: 2,
            color: QuestColors.osTextSecondary);

    final bandHeight = pad * 2 +
        wordmark.height +
        pad * 0.45 +
        title.height +
        (words == null ? 0 : pad * 0.35 + words.height);

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);

    canvas.drawImageRect(
      source,
      Rect.fromLTWH(0, 0, source.width.toDouble(), source.height.toDouble()),
      Rect.fromLTWH(0, 0, width, photoHeight),
      Paint()..filterQuality = FilterQuality.high,
    );

    canvas.drawRect(
      Rect.fromLTWH(0, photoHeight, width, bandHeight),
      Paint()..color = QuestColors.osBg,
    );
    // The ink hairline the rest of the app puts between a card and its
    // ground, so a saved photo looks like it came from Bsheel rather than
    // from a generic caption tool.
    canvas.drawRect(
      Rect.fromLTWH(0, photoHeight, width, width * 0.004),
      Paint()..color = QuestColors.osTextPrimary,
    );

    var y = photoHeight + pad;
    wordmark.paint(canvas, Offset(pad, y));
    y += wordmark.height + pad * 0.45;
    title.paint(canvas, Offset(pad, y));
    if (words != null) {
      y += title.height + pad * 0.35;
      words.paint(canvas, Offset(pad, y));
    }

    final picture = recorder.endRecording();
    final out = await picture.toImage(
        width.round(), (photoHeight + bandHeight).round());
    final data = await out.toByteData(format: ui.ImageByteFormat.png);
    source.dispose();
    out.dispose();
    picture.dispose();
    return data?.buffer.asUint8List();
  }

  static TextPainter _layout(
    String text,
    double maxWidth, {
    required double size,
    required FontWeight weight,
    required Color color,
    double spacing = 0,
    int maxLines = 1,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: size,
          fontWeight: weight,
          letterSpacing: spacing,
          height: 1.25,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: maxLines,
      ellipsis: '…',
    )..layout(maxWidth: maxWidth);
    return painter;
  }
}
