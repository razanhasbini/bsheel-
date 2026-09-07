import 'dart:typed_data';
import 'package:flutter_image_compress/flutter_image_compress.dart';

// M3 (2026-05-17): EXIF stripping. Photos picked from the gallery
// carry GPS coords, capture device, and full capture timestamp in
// their EXIF chunk. Uploading them as-is to the public R2 bucket
// leaks home / work / route information for every submission.
//
// We re-encode through flutter_image_compress, which already
// preserves orientation but drops every other EXIF tag. Output is
// JPEG by default; PNGs become JPEG which is a one-way trip but
// acceptable for user content (R2 serves both fine).
//
// quality 90 matches what the picker was already requesting; we keep
// images at their picked dimensions to avoid double-resizing.
//
// Camera-captured photos already use `requestFullMetadata: false` in
// image_picker, so this only matters for gallery picks and avatar
// uploads.

class ExifStripper {
  /// Returns a new byte buffer with EXIF metadata removed. If the
  /// input isn't a JPEG/PNG the original bytes are returned (we
  /// don't strip arbitrary container formats).
  static Future<Uint8List> strip(Uint8List input) async {
    if (input.isEmpty) return input;
    if (!_looksLikeJpegOrPng(input)) return input;
    final out = await FlutterImageCompress.compressWithList(
      input,
      quality: 90,
      keepExif: false,
      format: CompressFormat.jpeg,
    );
    // compressWithList returns Uint8List directly; defensive copy.
    return Uint8List.fromList(out);
  }

  static bool _looksLikeJpegOrPng(Uint8List b) {
    if (b.length < 8) return false;
    final jpeg = b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF;
    final png = b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47;
    return jpeg || png;
  }
}
