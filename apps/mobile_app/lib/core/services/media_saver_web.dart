import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Web: the browser's own download.
///
/// A Blob, an object URL, a hidden anchor carrying the `download` attribute,
/// one synthetic click, then remove the anchor and revoke the URL. This is
/// the shape every file this codebase hands a browser uses, and it is the
/// only one that works everywhere: the Web Share API cannot share *files* on
/// desktop Chrome or Firefox, so routing a video through the share sheet did
/// nothing at all there.
///
/// Going through a Blob rather than linking the signed URL directly is what
/// makes the filename stick and what stops the media being served inline:
/// R2 sets a Content-Disposition of its own, and an `<a download>` pointed
/// at a cross-origin URL is ignored by the browser — the attribute only
/// applies to same-origin and blob: hrefs.
///
/// [shareText] is dropped: a download has nowhere to carry a message, and
/// appending it to the filename would only produce an unreadable name.
Future<void> saveMediaFile({
  required Uint8List bytes,
  required String fileName,
  required String mimeType,
  required String shareText,
}) async {
  final blob = web.Blob(
    [bytes.toJS].toJS,
    web.BlobPropertyBag(type: mimeType),
  );
  final url = web.URL.createObjectURL(blob);
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..setAttribute('download', fileName)
    ..style.display = 'none';
  web.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
  // Freed immediately: the click has already handed the bytes to the
  // download manager, and a Blob left alive holds the whole video in memory
  // for the life of the tab.
  web.URL.revokeObjectURL(url);
}
