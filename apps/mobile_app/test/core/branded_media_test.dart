import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/core/config/branded_media.dart';

/// A saved photo has to carry its own context.
///
/// Once an image is in somebody's camera roll it travels without the app —
/// no link, no caption field, nothing. If the band is not drawn into the
/// pixels then a reposted proof says nothing about the quest, the place, or
/// Bsheel.
Future<Uint8List> solidImage(int width, int height) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    ui.Paint()..color = const ui.Color(0xFF3366AA),
  );
  final image = await recorder.endRecording().toImage(width, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

Future<ui.Image> decode(Uint8List bytes) async =>
    (await (await ui.instantiateImageCodec(bytes)).getNextFrame()).image;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('adds a band below the photo rather than covering it', () async {
    final source = await solidImage(1080, 1080);
    final branded = await BrandedMedia.brand(
      source,
      questTitle: 'Fold a manoushe with the baker',
      country: 'Lebanon',
      caption: 'Did it before the bakery even opened.',
    );
    expect(branded, isNotNull);

    final out = await decode(branded!);
    // Same width, taller: the proof itself is untouched and the band is
    // extra canvas. Covering the photo would hide the one thing a proof
    // image exists to show.
    expect(out.width, 1080);
    expect(out.height, greaterThan(1080));
  });

  test('scales a small photo up so the caption stays legible', () async {
    final branded = await BrandedMedia.brand(
      await solidImage(240, 240),
      questTitle: 'Watch the sunrise',
    );
    final out = await decode(branded!);
    expect(out.width, 1080);
  });

  test('a taller band when there is a caption to fit', () async {
    final source = await solidImage(800, 800);
    final bare = await decode((await BrandedMedia.brand(
      source,
      questTitle: 'Watch the sunrise',
    ))!);
    final withCaption = await decode((await BrandedMedia.brand(
      source,
      questTitle: 'Watch the sunrise',
      caption: 'Woke up at five for this and it was worth every minute.',
    ))!);
    expect(withCaption.height, greaterThan(bare.height));
  });

  test('renders with no country and no caption', () async {
    // Most quests can be done anywhere; the band must not assume geography.
    final branded = await BrandedMedia.brand(
      await solidImage(600, 900),
      questTitle: 'Do 50 push-ups before noon',
    );
    expect(branded, isNotNull);
    final out = await decode(branded!);
    expect(out.height, greaterThan(900));
  });

  test('returns null for bytes that are not an image', () async {
    // The caller then saves the original rather than failing the download —
    // a photo without the band is still the photo they asked for.
    final branded = await BrandedMedia.brand(
      Uint8List.fromList([1, 2, 3, 4, 5]),
      questTitle: 'Watch the sunrise',
    );
    expect(branded, isNull);
  });
}
