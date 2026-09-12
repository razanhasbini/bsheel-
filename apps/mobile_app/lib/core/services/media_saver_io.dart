import 'dart:typed_data';

import 'package:share_plus/share_plus.dart';

/// iOS/Android: the system share sheet.
///
/// Bytes, never a temp file — `XFile.fromData` needs no filesystem, and the
/// previous `getTemporaryDirectory()` + `dart:io` File is what made every
/// save throw on the web build before this was split in two.
Future<void> saveMediaFile({
  required Uint8List bytes,
  required String fileName,
  required String mimeType,
  required String shareText,
}) async {
  await SharePlus.instance.share(
    ShareParams(
      files: [XFile.fromData(bytes, mimeType: mimeType, name: fileName)],
      // The share implementation reads the filename from here, not from the
      // XFile — without it the file arrives as "file" with no extension.
      fileNameOverrides: [fileName],
      text: shareText,
    ),
  );
}
