import 'package:admin_web/features/agent_evidence/domain/evidence_wording.dart';
import 'package:flutter_test/flutter_test.dart';

/// How CAMARA evidence reads to a person.
///
/// The console showed "WHERE THE NETWORK PUT IT · CONTRADICTED" on all three
/// capabilities at once. Two problems: a location is not a thing that can be
/// contradicted, and one measurement — the device was in Budapest — read as
/// three separate accusations. The word is the pipeline's internal ranking
/// and it does not belong on screen.
void main() {
  group('the answer fits the question', () {
    test('each capability answers in its own words', () {
      expect(capabilityAnswer('GEOFENCING', 'CONTRADICTED'), 'NEVER ENTERED');
      expect(capabilityAnswer('LOCATION_RETRIEVAL', 'CONTRADICTED'),
          'SOMEWHERE ELSE');
      expect(capabilityAnswer('LOCATION_VERIFICATION', 'CONTRADICTED'), 'NO');
    });

    // The regression itself, stated as a rule rather than as three strings:
    // no capability, in any outcome, may put the internal verdict on screen.
    test('never shows the internal verdict words', () {
      const capabilities = [
        'GEOFENCING',
        'LOCATION_RETRIEVAL',
        'LOCATION_VERIFICATION',
        'ADDITIONAL',
      ];
      const outcomes = ['SUPPORTED', 'CONTRADICTED', 'UNAVAILABLE', 'ERROR'];
      for (final capability in capabilities) {
        for (final outcome in outcomes) {
          final answer = capabilityAnswer(capability, outcome);
          expect(answer, isNot(contains('CONTRADICT')),
              reason: '$capability/$outcome');
          expect(answer, isNot(contains('SUPPORTED')),
              reason: '$capability/$outcome');
          expect(answer, isNot(contains('UNAVAILABLE')),
              reason: '$capability/$outcome');
        }
      }
    });

    // A missing signal is not an accusation. It must not borrow the words of
    // one, and the page must not colour it like one either.
    test('an absent signal says nothing happened, not that something failed',
        () {
      expect(capabilityAnswer('GEOFENCING', 'UNAVAILABLE'), 'NOT WATCHED');
      expect(capabilityAnswer('LOCATION_RETRIEVAL', 'UNAVAILABLE'), 'NO FIX');
      expect(capabilityAnswer('LOCATION_VERIFICATION', 'ERROR'),
          'NETWORK COULD NOT SAY');
    });
  });

  group('the detail states what was measured', () {
    // Budapest to the Sheikh Zayed Grand Mosque — the exact case on screen.
    // A distance is a fact a reader can weigh; a pair of coordinates is one
    // they have to look up.
    test('turns a reported fix into a distance from the quest', () {
      final line = capabilityMeasurement(
        capability: 'LOCATION_RETRIEVAL',
        outcome: 'CONTRADICTED',
        detail: {
          'coordinates': {'latitude': 47.48627, 'longitude': 19.07915},
        },
        placeName: 'Sheikh Zayed Grand Mosque',
        placeLatitude: 24.4128,
        placeLongitude: 54.4750,
      );
      expect(line, contains('Sheikh Zayed Grand Mosque'));
      expect(line, contains('km'));
      expect(line, isNot(contains('47.48')));
    });

    test('falls back to coordinates when the quest has no geography', () {
      final line = capabilityMeasurement(
        capability: 'LOCATION_RETRIEVAL',
        outcome: 'CONTRADICTED',
        detail: {
          'coordinates': {'latitude': 47.48627, 'longitude': 19.07915},
        },
      );
      expect(line, contains('47.48627'));
    });

    test('says what the geofence did, not what it proved', () {
      expect(
        capabilityMeasurement(
            capability: 'GEOFENCING',
            outcome: 'CONTRADICTED',
            detail: {'events': []}),
        contains('never crossed into it'),
      );
      expect(
        capabilityMeasurement(
            capability: 'GEOFENCING',
            outcome: 'SUPPORTED',
            detail: {
              'events': [
                {'type': 'ENTER'}
              ]
            }),
        contains('1 entry/exit'),
      );
    });

    // Reachability is context about the network and never about the player.
    // The sentence has to carry that, because the chip beside it cannot.
    test('reachability disclaims itself', () {
      final line = capabilityMeasurement(
        capability: 'ADDITIONAL',
        outcome: 'SUPPORTED',
        detail: {
          'reachable': true,
          'connectivity': ['DATA']
        },
      );
      expect(line, contains('context only'));
      expect(line, contains('DATA'));
    });

    test('an unavailable capability claims nothing', () {
      expect(
        capabilityMeasurement(
            capability: 'LOCATION_VERIFICATION',
            outcome: 'UNAVAILABLE',
            detail: null),
        'the network would not answer either way',
      );
    });
  });

  group('distance', () {
    test('is null when either end is missing, never zero', () {
      expect(
        distanceFromDestination(
            coordinates: {'latitude': 1.0, 'longitude': 2.0}),
        isNull,
      );
      expect(
        distanceFromDestination(
            coordinates: const {}, placeLatitude: 1, placeLongitude: 2),
        isNull,
      );
    });

    test('reads at the scale it is', () {
      expect(readableDistance(420), '420 m');
      expect(readableDistance(2400), '2.4 km');
      expect(readableDistance(3180000), '3180 km');
    });
  });
}
