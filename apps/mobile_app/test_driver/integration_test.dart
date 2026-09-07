// Driver for `flutter drive` runs of integration_test/figma_capture_test.dart.
//
// Saves each screenshot the test takes via binding.takeScreenshot(name) to
// the directory pointed at by FIGMA_CAPTURE_DIR (defaults to
// build/figma_screenshots/ relative to the app dir).
import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  final outDir = Platform.environment['FIGMA_CAPTURE_DIR'] ??
      '${Directory.current.path}/build/figma_screenshots';
  Directory(outDir).createSync(recursive: true);

  await integrationDriver(
    onScreenshot: (
      String name,
      List<int> bytes, [
      Map<String, Object?>? args,
    ]) async {
      final file = File('$outDir/$name.png');
      await file.writeAsBytes(bytes, flush: true);
      stdout.writeln('[figma] wrote ${file.path} (${bytes.length} bytes)');
      return true;
    },
  );
}
