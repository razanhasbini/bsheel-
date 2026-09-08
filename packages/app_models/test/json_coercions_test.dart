import 'package:app_models/src/json_coercions.dart';
import 'package:test/test.dart';

/// Direct tests for the shared coercions. Nine models used to carry their
/// own drifted copies of these rules; these tests pin the one shared
/// implementation so the drift cannot come back.
void main() {
  group('coerceInt', () {
    test('passes ints through and truncates other nums toward zero', () {
      expect(coerceInt(7), 7);
      expect(coerceInt(99.9), 99);
      expect(coerceInt(-99.9), -99);
    });

    test('parses integer and decimal strings', () {
      expect(coerceInt('250'), 250);
      // Regression guard: int.tryParse rejects '99.9', which used to make a
      // PostgREST numeric-as-text column silently read 0.
      expect(coerceInt('99.9'), 99);
      expect(coerceInt('  42  '), 42);
      expect(coerceInt('-5'), -5);
    });

    test('falls back for null, blanks, bools and garbage', () {
      expect(coerceInt(null), 0);
      expect(coerceInt(''), 0);
      expect(coerceInt('   '), 0);
      expect(coerceInt(true), 0);
      expect(coerceInt('lots'), 0);
      expect(coerceInt(null, defaultValue: 4), 4);
      expect(coerceInt('lots', defaultValue: 4), 4);
    });

    test('a non-finite double falls back instead of throwing', () {
      // double.infinity.toInt() throws UnsupportedError.
      expect(coerceInt(double.infinity), 0);
      expect(coerceInt(double.nan, defaultValue: 4), 4);
    });

    test('coerceNullableInt keeps null distinguishable from 0', () {
      expect(coerceNullableInt(null), isNull);
      expect(coerceNullableInt('garbage'), isNull);
      expect(coerceNullableInt(0), 0);
      expect(coerceNullableInt('421.5'), 421);
    });
  });

  group('coerceDouble', () {
    test('widens ints and parses numeric strings', () {
      expect(coerceDouble(3), 3.0);
      expect(coerceDouble('2.5'), 2.5);
    });

    test('falls back for null, bools and garbage', () {
      expect(coerceDouble(null), 0.0);
      expect(coerceDouble(true), 0.0);
      expect(coerceDouble('hot'), 0.0);
    });
  });

  group('coerceTimestamp', () {
    test('parses strings and passes DateTimes through', () {
      expect(
        coerceTimestamp('2026-05-03T12:00:00Z'),
        DateTime.utc(2026, 5, 3, 12),
      );
      final at = DateTime.utc(2026, 1, 1);
      expect(coerceTimestamp(at), at);
    });

    test('degrades a required timestamp to the epoch, never to now', () {
      for (final bad in <Object?>[null, '', 'tomorrow', 42, true]) {
        expect(
          coerceTimestamp(bad),
          epochTimestamp,
          reason: '$bad should degrade to the epoch',
        );
      }
      expect(epochTimestamp, DateTime.utc(1970));
      expect(epochTimestamp.isUtc, isTrue);
    });

    test('an optional timestamp degrades to null', () {
      expect(coerceNullableTimestamp(null), isNull);
      expect(coerceNullableTimestamp('never'), isNull);
      expect(coerceNullableTimestamp(42), isNull);
      expect(
        coerceNullableTimestamp('2026-05-03T12:00:00Z'),
        DateTime.utc(2026, 5, 3, 12),
      );
    });
  });

  group('coerceBool', () {
    test('real booleans read through regardless of the fallbacks', () {
      expect(coerceBool(true, ifMissing: false), isTrue);
      expect(coerceBool(false, ifMissing: true), isFalse);
    });

    test('the strings "true" / "false" coerce, case- and space-insensitively',
        () {
      expect(coerceBool('true', ifMissing: false), isTrue);
      expect(coerceBool(' TRUE ', ifMissing: false), isTrue);
      expect(coerceBool('false', ifMissing: true), isFalse);
      expect(coerceBool('False', ifMissing: true), isFalse);
    });

    test('null uses ifMissing', () {
      expect(coerceBool(null, ifMissing: true), isTrue);
      expect(coerceBool(null, ifMissing: false), isFalse);
      // ifUnrecognised must not hijack the missing case.
      expect(
        coerceBool(null, ifMissing: true, ifUnrecognised: false),
        isTrue,
      );
    });

    test('anything else uses ifUnrecognised, defaulting to ifMissing', () {
      expect(
        coerceBool(1, ifMissing: true, ifUnrecognised: false),
        isFalse,
      );
      expect(
        coerceBool('yes', ifMissing: false, ifUnrecognised: true),
        isTrue,
      );
      expect(coerceBool(1, ifMissing: true), isTrue);
    });
  });

  group('coerceEmbed', () {
    test('accepts the object shape', () {
      expect(coerceEmbed(<String, dynamic>{'a': 1}), {'a': 1});
    });

    test('accepts the single-element array shape', () {
      expect(
        coerceEmbed(<dynamic>[
          <String, dynamic>{'a': 1},
        ]),
        {'a': 1},
      );
    });

    test('casts a loosely-typed map', () {
      expect(coerceEmbed(<dynamic, dynamic>{'a': 1}), {'a': 1});
    });

    test('yields null for an empty array, a scalar or null', () {
      expect(coerceEmbed(<dynamic>[]), isNull);
      expect(coerceEmbed('profiles'), isNull);
      expect(coerceEmbed(null), isNull);
    });
  });

  group('normalizeQuestDurationHours', () {
    test('mirrors the DB CHECK range of 1..168', () {
      expect(minQuestDurationHours, 1);
      expect(maxQuestDurationHours, 168);
      expect(normalizeQuestDurationHours(1), 1);
      expect(normalizeQuestDurationHours(168), 168);
      expect(normalizeQuestDurationHours(169), 168);
      expect(normalizeQuestDurationHours(100000), 168);
    });

    test('an unusable value takes the column default', () {
      for (final bad in <Object?>[0, -3, null, 'abc', false]) {
        expect(
          normalizeQuestDurationHours(bad),
          defaultQuestDurationHours,
          reason: 'duration_hours=$bad',
        );
      }
    });

    test('numeric strings and nums are accepted', () {
      expect(normalizeQuestDurationHours('12'), 12);
      expect(normalizeQuestDurationHours(6.4), 6);
    });
  });

  group('decodeMediaUrls', () {
    test('a bare URL yields one element', () {
      expect(decodeMediaUrls('https://cdn.test/a.jpg'),
          ['https://cdn.test/a.jpg']);
    });

    test('a JSON array yields every URL in order', () {
      expect(decodeMediaUrls('["a.jpg","b.mp4"]'), ['a.jpg', 'b.mp4']);
      expect(decodeMediaUrls('  ["a.jpg"]  '), ['a.jpg']);
    });

    test('blank and null yield an empty list, never [""]', () {
      expect(decodeMediaUrls(null), isEmpty);
      expect(decodeMediaUrls(''), isEmpty);
      expect(decodeMediaUrls('   '), isEmpty);
    });

    test('malformed JSON falls back to the raw value', () {
      expect(decodeMediaUrls('["a.jpg"'), ['["a.jpg"']);
      expect(decodeMediaUrls('[1,2]'), ['[1,2]']);
    });
  });

  group('deriveMediaTypeFromUrls', () {
    test('classifies single-kind and mixed lists', () {
      expect(deriveMediaTypeFromUrls(['a.jpg', 'b.png']), 'image');
      expect(deriveMediaTypeFromUrls(['a.mp4', 'b.mov']), 'video');
      expect(deriveMediaTypeFromUrls(['a.jpg', 'b.mp4']), 'mixed');
    });

    test('ignores a query string or fragment', () {
      expect(
        deriveMediaTypeFromUrls(['https://cdn.test/a.JPG?token=x&y=1']),
        'image',
      );
      expect(deriveMediaTypeFromUrls(['https://cdn.test/a.mp4#t=2']), 'video');
    });

    test('yields null when any URL cannot be classified', () {
      expect(deriveMediaTypeFromUrls([]), isNull);
      expect(deriveMediaTypeFromUrls(['a.jpg', 'opaque-key']), isNull);
      expect(deriveMediaTypeFromUrls(['a.jpg', 'notes.txt']), isNull);
      expect(deriveMediaTypeFromUrls(['a.']), isNull);
      expect(deriveMediaTypeFromUrls(['.jpg']), isNull);
    });
  });
}
