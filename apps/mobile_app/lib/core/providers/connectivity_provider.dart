import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Single source of truth for network state.
///
/// Emits `true` while the device has any active connectivity type.
/// Seeded with the current snapshot so the first read isn't AsyncLoading.
final connectivityProvider = StreamProvider<bool>((ref) {
  final controller = Connectivity();
  late final StreamController<List<ConnectivityResult>> sc;
  sc = StreamController<List<ConnectivityResult>>(
    onListen: () async {
      try {
        final initial = await controller.checkConnectivity();
        if (!sc.isClosed) sc.add(initial);
      } catch (_) {/* ignore initial-snapshot errors */}
      unawaited(sc.addStream(controller.onConnectivityChanged));
    },
    onCancel: () => sc.close(),
  );
  ref.onDispose(sc.close);
  return sc.stream.map(
    (results) => results.any((r) => r != ConnectivityResult.none),
  );
});

/// True when the device has no network connectivity at all.
/// Unknown (stream not ready yet) counts as online so the UI never
/// flashes the offline panel during startup.
final isOfflineProvider = Provider<bool>((ref) {
  return ref.watch(connectivityProvider).valueOrNull == false;
});
