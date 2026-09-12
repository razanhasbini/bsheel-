import 'dart:math' as math;

import 'package:app_models/app_models.dart';

/// How CAMARA evidence is described to a person.
///
/// Pulled out of the page because it is the part that was wrong, and the
/// part worth pinning with tests. SUPPORTED / CONTRADICTED / UNAVAILABLE are
/// the pipeline's internal words for "this argues for the claim", "against
/// it" and "it says nothing", and they are the right words *there* — the
/// policy layer has to rank them and does.
///
/// On screen they were wrong twice over. A location is not a thing that can
/// be contradicted, so "WHERE THE NETWORK PUT IT · CONTRADICTED" answered no
/// question anyone had asked. And stamping the same word on all three
/// capabilities turned one measurement — the device was in Budapest — into
/// what looked like three separate accusations.
///
/// So each capability answers in its own terms, and "contradicted" is not
/// among them. Which way the evidence cuts is carried by colour, where it
/// cannot be mistaken for a description of what was measured.

/// The answer to the capability's own question, in its own words.
String capabilityAnswer(String capability, String outcome) =>
    switch ((capability, outcome)) {
      ('GEOFENCING', 'SUPPORTED') => 'ENTERED',
      ('GEOFENCING', 'CONTRADICTED') => 'NEVER ENTERED',
      ('GEOFENCING', _) => 'NOT WATCHED',
      ('LOCATION_RETRIEVAL', 'SUPPORTED') => 'AT THE PLACE',
      ('LOCATION_RETRIEVAL', 'CONTRADICTED') => 'SOMEWHERE ELSE',
      ('LOCATION_RETRIEVAL', _) => 'NO FIX',
      ('LOCATION_VERIFICATION', 'SUPPORTED') => 'YES',
      ('LOCATION_VERIFICATION', 'CONTRADICTED') => 'NO',
      ('LOCATION_VERIFICATION', _) => 'NETWORK COULD NOT SAY',
      (_, 'SUPPORTED') => 'READ',
      (_, 'CONTRADICTED') => 'AGAINST',
      _ => 'NO ANSWER',
    };

/// What was actually measured, in a sentence.
///
/// Prefers the measurement to the verdict wherever it has one: a distance
/// beats a pair of coordinates, because "3,180 km away" is a fact a reader
/// can weigh and "47.486, 19.079" is one they have to look up.
String capabilityMeasurement({
  required String capability,
  required String outcome,
  required Object? detail,
  String? placeName,
  double? placeLatitude,
  double? placeLongitude,
}) {
  final map = detail is Map ? detail : const {};
  final where = placeName ?? 'the destination';

  if (capability == 'GEOFENCING') {
    final events = map['events'];
    // An UNAVAILABLE geofence also carries an empty event list, and "the
    // geofence was live and never fired" is the opposite of what happened
    // — nothing was watching. Only an ACTIVE fence with no events means
    // the device stayed out.
    if (events is! List || outcome == 'UNAVAILABLE') {
      return 'no geofence covered this attempt';
    }
    if (events.isEmpty) {
      return 'the geofence was live for the whole quest and the device never '
          'crossed into it';
    }
    return '${events.length} entry/exit event(s) while the quest was live';
  }

  if (capability == 'LOCATION_RETRIEVAL') {
    final coordinates = map['coordinates'];
    if (coordinates is! Map) return 'the network returned no position';
    final away = distanceFromDestination(
      coordinates: coordinates,
      placeLatitude: placeLatitude,
      placeLongitude: placeLongitude,
    );
    if (away == null) {
      return 'the network placed the device at '
          '${coordinates['latitude']}, ${coordinates['longitude']}';
    }
    return outcome == 'SUPPORTED'
        ? 'the network placed the device ${readableDistance(away)} from '
            '$where — inside the area'
        : 'the network placed the device ${readableDistance(away)} from $where';
  }

  if (capability == 'LOCATION_VERIFICATION') {
    return switch (outcome) {
      'SUPPORTED' => 'the network confirmed the device was inside the area',
      'CONTRADICTED' =>
        'the network answered no — the device was not inside the area',
      _ => 'the network would not answer either way',
    };
  }

  if (map['reachable'] != null) {
    // Context, never a verdict. Device reachability says nothing about
    // whether a quest was done, and the sentence must not let anyone read
    // it as though it did.
    final reachable = map['reachable'] == true;
    final connectivity = (map['connectivity'] as List? ?? const []).join(', ');
    return reachable
        ? 'the handset was on the network'
            '${connectivity.isEmpty ? '' : ' ($connectivity)'}'
            ' — context only, not evidence either way'
        : 'the handset was off the network — context only, not evidence '
            'either way';
  }

  return outcome == 'UNAVAILABLE'
      ? 'no signal was gathered'
      : outcome.toLowerCase();
}

/// How far a reported fix landed from where the quest actually was.
/// Null when either end is missing — never zero, which would read as "there".
double? distanceFromDestination({
  required Map<Object?, Object?> coordinates,
  double? placeLatitude,
  double? placeLongitude,
}) {
  final lat = coerceNullableDouble(coordinates['latitude']);
  final lon = coerceNullableDouble(coordinates['longitude']);
  if (lat == null ||
      lon == null ||
      placeLatitude == null ||
      placeLongitude == null) {
    return null;
  }
  const earthRadiusMeters = 6371000.0;
  double radians(double degrees) => degrees * math.pi / 180;
  final dLat = radians(placeLatitude - lat);
  final dLon = radians(placeLongitude - lon);
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(radians(lat)) *
          math.cos(radians(placeLatitude)) *
          math.sin(dLon / 2) *
          math.sin(dLon / 2);
  return earthRadiusMeters * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}

String readableDistance(double meters) => meters >= 10000
    ? '${(meters / 1000).round()} km'
    : meters >= 1000
        ? '${(meters / 1000).toStringAsFixed(1)} km'
        : '${meters.round()} m';
