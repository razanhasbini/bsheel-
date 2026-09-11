import 'package:app_core/app_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

/// Why the map has no live position to draw, when it has none.
enum LiveLocationStatus {
  /// Still asking the OS, or the first fix has not arrived yet.
  pending,

  /// Streaming fixes.
  live,

  /// Location services are switched off for the whole device.
  serviceOff,

  /// The user declined this time; asking again is allowed.
  denied,

  /// The user declined permanently; only Settings can change it.
  deniedForever,

  /// The platform has no location plugin (web, tests) or it failed.
  unavailable,
}

class LiveLocation {
  const LiveLocation(this.status, {this.point, this.accuracyM});
  final LiveLocationStatus status;
  final LatLng? point;
  final double? accuracyM;

  static const pending = LiveLocation(LiveLocationStatus.pending);
}

/// The device's own position, for drawing the player on the map.
///
/// This is device GPS and nothing more: it moves the avatar bubble and tells
/// the player how far a quest is. It never counts as being somewhere — that
/// judgement belongs to the network, through the geofence the server opens
/// when a quest is assigned.
///
/// Emits a status while permission is unresolved so the page can explain
/// what to do instead of drawing nothing; `autoDispose` stops the GPS the
/// moment the map is left.
final liveLocationProvider =
    StreamProvider.autoDispose<LiveLocation>((ref) async* {
  yield LiveLocation.pending;
  try {
    if (!await Geolocator.isLocationServiceEnabled()) {
      yield const LiveLocation(LiveLocationStatus.serviceOff);
      return;
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    switch (permission) {
      case LocationPermission.denied:
        yield const LiveLocation(LiveLocationStatus.denied);
        return;
      case LocationPermission.deniedForever:
        yield const LiveLocation(LiveLocationStatus.deniedForever);
        return;
      case LocationPermission.unableToDetermine:
        yield const LiveLocation(LiveLocationStatus.unavailable);
        return;
      case LocationPermission.whileInUse:
      case LocationPermission.always:
        break;
    }

    // A last known fix lands the avatar immediately; the stream then walks
    // it to where the player actually is.
    final last = await Geolocator.getLastKnownPosition();
    if (last != null) {
      yield LiveLocation(
        LiveLocationStatus.live,
        point: LatLng(last.latitude, last.longitude),
        accuracyM: last.accuracy,
      );
    }
    yield* Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        // Five metres: enough to read as "walking" on the map without
        // repainting on GPS jitter while the phone sits on a table.
        distanceFilter: 5,
      ),
    ).map((position) => LiveLocation(
          LiveLocationStatus.live,
          point: LatLng(position.latitude, position.longitude),
          accuracyM: position.accuracy,
        ));
  } catch (error) {
    // MissingPluginException on platforms without geolocator, or a plugin
    // failure. The map is still fully usable without the player's dot.
    AppLogger.error('[Map] live location unavailable', error);
    yield const LiveLocation(LiveLocationStatus.unavailable);
  }
});
