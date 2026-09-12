import 'dart:async';

import 'package:visibility_detector/visibility_detector.dart';

/// Runs before every test file in this package (flutter_test convention).
///
/// `QuestImpression` wraps quest cards on the feed, home, map and search in a
/// `VisibilityDetector`, which throttles its callbacks through a 500 ms
/// timer. Under the test binding that timer is still pending when a test
/// tears its tree down, and the binding fails the test for it. Zero makes
/// the detector report synchronously, which is also what a test wants: the
/// visibility it asserts on is the visibility of the frame it just pumped.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  VisibilityDetectorController.instance.updateInterval = Duration.zero;
  await testMain();
}
