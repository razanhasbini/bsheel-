import 'package:app_models/app_models.dart';
import 'package:app_contracts/app_contracts.dart';
import 'package:test/test.dart';

Map<String, dynamic> profileRow({Map<String, dynamic> overrides = const {}}) =>
    {
      ProfileColumns.id: 'user-1',
      ProfileColumns.username: 'ada',
      ProfileColumns.displayName: 'Ada L.',
      ProfileColumns.avatarUrl: 'https://cdn.test/ada.jpg',
      ProfileColumns.bio: 'builds things',
      ProfileColumns.xp: 1250,
      ProfileColumns.level: 5,
      ProfileColumns.questsCompleted: 17,
      ProfileColumns.createdAt: '2026-01-01T00:00:00Z',
      ProfileColumns.updatedAt: '2026-05-03T12:00:00Z',
      ProfileColumns.profileCompleted: true,
      ProfileColumns.ageVerified: true,
      ProfileColumns.analyticsConsentAt: '2026-02-02T10:00:00Z',
      ...overrides,
    };

ProfileModel parse({Map<String, dynamic> overrides = const {}}) =>
    ProfileModel.fromJson(profileRow(overrides: overrides));

void main() {
  group('ProfileModel.fromJson', () {
    test('parses the full wire row', () {
      final profile = parse();

      expect(profile.id, 'user-1');
      expect(profile.username, 'ada');
      expect(profile.displayName, 'Ada L.');
      expect(profile.avatarUrl, 'https://cdn.test/ada.jpg');
      expect(profile.bio, 'builds things');
      expect(profile.xp, 1250);
      expect(profile.level, 5);
      expect(profile.questsCompleted, 17);
      expect(profile.createdAt, DateTime.utc(2026, 1, 1));
      expect(profile.updatedAt, DateTime.utc(2026, 5, 3, 12));
      expect(profile.profileCompleted, isTrue);
      expect(profile.ageVerified, isTrue);
      expect(profile.analyticsConsentAt, DateTime.utc(2026, 2, 2, 10));
    });

    test('id / username / display_name are hard requirements', () {
      // Identity columns keep their non-nullable `as String` cast: a row
      // with no id is not a profile, so there is nothing to degrade to.
      // (created_at deliberately no longer belongs in this list — see the
      // next test.)
      for (final key in [
        ProfileColumns.id,
        ProfileColumns.username,
        ProfileColumns.displayName,
      ]) {
        final row = profileRow()..remove(key);
        expect(
          () => ProfileModel.fromJson(row),
          throwsA(isA<TypeError>()),
          reason: 'a missing $key should throw',
        );
      }
    });

    test('a missing or malformed created_at degrades to the epoch', () {
      // Regression guard. created_at used to be `DateTime.parse(x as
      // String)`, so one row with a NULL/garbage timestamp threw a
      // TypeError that took down the whole list parse. A required timestamp
      // now falls back to the Unix epoch: deterministic, and it sorts to
      // the bottom of a newest-first list instead of looking recent.
      final epoch = DateTime.utc(1970);
      final missing = profileRow()..remove(ProfileColumns.createdAt);

      expect(ProfileModel.fromJson(missing).createdAt, epoch);
      expect(
          parse(overrides: {ProfileColumns.createdAt: null}).createdAt, epoch);
      expect(
          parse(overrides: {ProfileColumns.createdAt: 'yesterday'}).createdAt,
          epoch);
      expect(parse(overrides: {ProfileColumns.createdAt: 42}).createdAt, epoch);
    });

    test('an unparseable updated_at becomes null, not the epoch', () {
      // Optional timestamps degrade to null so "never updated" stays
      // distinguishable from "updated at some fallback date".
      expect(parse(overrides: {ProfileColumns.updatedAt: 'nope'}).updatedAt,
          isNull);
    });

    test('nullable text columns survive being absent', () {
      final row = profileRow()
        ..remove(ProfileColumns.avatarUrl)
        ..remove(ProfileColumns.bio)
        ..remove(ProfileColumns.updatedAt)
        ..remove(ProfileColumns.analyticsConsentAt);
      final profile = ProfileModel.fromJson(row);

      expect(profile.avatarUrl, isNull);
      expect(profile.bio, isNull);
      expect(profile.updatedAt, isNull);
      expect(profile.analyticsConsentAt, isNull);
    });

    group('numeric coercion', () {
      test('xp defaults to 0 and level defaults to 1 when null', () {
        final profile = parse(overrides: {
          ProfileColumns.xp: null,
          ProfileColumns.level: null,
          ProfileColumns.questsCompleted: null,
        });

        expect(profile.xp, 0);
        expect(profile.level, 1);
        expect(profile.questsCompleted, 0);
      });

      test('numeric strings parse', () {
        final profile = parse(overrides: {
          ProfileColumns.xp: '900',
          ProfileColumns.level: '4',
        });

        expect(profile.xp, 900);
        expect(profile.level, 4);
      });

      test('doubles truncate toward zero', () {
        expect(parse(overrides: {ProfileColumns.xp: 1250.9}).xp, 1250);
      });

      test('garbage falls back to each column default, not to 0', () {
        // level must never be 0 — the UI divides by it when drawing the
        // XP-to-next-level bar.
        final profile = parse(overrides: {
          ProfileColumns.xp: 'lots',
          ProfileColumns.level: 'five',
        });

        expect(profile.xp, 0);
        expect(profile.level, 1);
      });

      test('a decimal string truncates instead of collapsing to 0', () {
        // Regression guard. int.tryParse rejects '1250.9', so the old
        // per-model _toInt turned PostgREST's numeric-as-text into 0.
        expect(parse(overrides: {ProfileColumns.xp: '1250.9'}).xp, 1250);
      });

      test('a stringly-typed boolean flag coerces instead of throwing', () {
        // Regression guard. `as bool?` was a hard cast, so a JSONB
        // round-trip that stringified the flag threw on the whole row.
        expect(
          parse(overrides: {ProfileColumns.profileCompleted: 'true'})
              .profileCompleted,
          isTrue,
        );
        expect(
          parse(overrides: {ProfileColumns.ageVerified: 'false'}).ageVerified,
          isFalse,
        );
      });
    });

    group('consent / gating flags fail closed', () {
      test('null and missing profile_completed read as false', () {
        expect(
          parse(overrides: {ProfileColumns.profileCompleted: null})
              .profileCompleted,
          isFalse,
        );
        final row = profileRow()..remove(ProfileColumns.profileCompleted);
        expect(ProfileModel.fromJson(row).profileCompleted, isFalse);
      });

      test('null and missing age_verified read as false', () {
        expect(
          parse(overrides: {ProfileColumns.ageVerified: null}).ageVerified,
          isFalse,
        );
        final row = profileRow()..remove(ProfileColumns.ageVerified);
        expect(ProfileModel.fromJson(row).ageVerified, isFalse);
      });

      test('a null analytics_consent_at means no consent yet', () {
        expect(
          parse(overrides: {ProfileColumns.analyticsConsentAt: null})
              .analyticsConsentAt,
          isNull,
        );
      });
    });
  });

  group('ProfileModel.toJson', () {
    test('emits all 13 columns with ISO-8601 timestamps', () {
      final json = parse().toJson();

      expect(json.keys, hasLength(13));
      expect(json[ProfileColumns.createdAt], '2026-01-01T00:00:00.000Z');
      expect(json[ProfileColumns.updatedAt], '2026-05-03T12:00:00.000Z');
      expect(
        json[ProfileColumns.analyticsConsentAt],
        '2026-02-02T10:00:00.000Z',
      );
      expect(json[ProfileColumns.ageVerified], true);
    });

    test('round-trips without drift', () {
      final original = parse();
      final restored = ProfileModel.fromJson(original.toJson());

      expect(restored.id, original.id);
      expect(restored.username, original.username);
      expect(restored.displayName, original.displayName);
      expect(restored.avatarUrl, original.avatarUrl);
      expect(restored.bio, original.bio);
      expect(restored.xp, original.xp);
      expect(restored.level, original.level);
      expect(restored.questsCompleted, original.questsCompleted);
      expect(restored.createdAt, original.createdAt);
      expect(restored.updatedAt, original.updatedAt);
      expect(restored.profileCompleted, original.profileCompleted);
      expect(restored.ageVerified, original.ageVerified);
      expect(restored.analyticsConsentAt, original.analyticsConsentAt);
    });
  });

  group('ProfileModel.copyWith', () {
    test('a no-arg copy preserves every field', () {
      final original = parse();
      final copy = original.copyWith();

      expect(copy.id, original.id);
      expect(copy.username, original.username);
      expect(copy.displayName, original.displayName);
      expect(copy.avatarUrl, original.avatarUrl);
      expect(copy.bio, original.bio);
      expect(copy.xp, original.xp);
      expect(copy.level, original.level);
      expect(copy.questsCompleted, original.questsCompleted);
      expect(copy.createdAt, original.createdAt);
      expect(copy.updatedAt, original.updatedAt);
      expect(copy.profileCompleted, original.profileCompleted);
      expect(copy.ageVerified, original.ageVerified);
      expect(copy.analyticsConsentAt, original.analyticsConsentAt);
    });

    test('overrides the fields it is given', () {
      final copy = parse().copyWith(
        username: 'grace',
        xp: 9999,
        level: 12,
        profileCompleted: false,
      );

      expect(copy.username, 'grace');
      expect(copy.xp, 9999);
      expect(copy.level, 12);
      expect(copy.profileCompleted, isFalse);
    });

    test('the sentinel lets an explicit null actually clear a field', () {
      // This is the whole point of the _sentinel default: "remove my avatar"
      // has to be distinguishable from "don't touch my avatar".
      final cleared = parse().copyWith(
        avatarUrl: null,
        bio: null,
        updatedAt: null,
        analyticsConsentAt: null,
      );

      expect(cleared.avatarUrl, isNull);
      expect(cleared.bio, isNull);
      expect(cleared.updatedAt, isNull);
      expect(cleared.analyticsConsentAt, isNull);
      // ...and the untouched fields are still there.
      expect(cleared.username, 'ada');
      expect(cleared.xp, 1250);
    });

    test('omitting a nullable field keeps its existing non-null value', () {
      final copy = parse().copyWith(xp: 1);

      expect(copy.avatarUrl, 'https://cdn.test/ada.jpg');
      expect(copy.bio, 'builds things');
      expect(copy.analyticsConsentAt, DateTime.utc(2026, 2, 2, 10));
    });

    test('a sentinel field can also be set to a new value', () {
      final copy = parse().copyWith(
        avatarUrl: 'https://cdn.test/new.jpg',
        analyticsConsentAt: DateTime.utc(2026, 7, 7),
      );

      expect(copy.avatarUrl, 'https://cdn.test/new.jpg');
      expect(copy.analyticsConsentAt, DateTime.utc(2026, 7, 7));
    });
  });

  group('ProfileModel value equality', () {
    // Regression guard. Equality used to be identity, so a profile re-fetch
    // that changed nothing still rebuilt every widget watching it.
    test('two profiles parsed from the same row are equal', () {
      expect(parse(), parse());
      expect(parse().hashCode, parse().hashCode);
    });

    test('a no-arg copyWith is equal to its original', () {
      final original = parse();
      expect(original.copyWith(), original);
    });

    test('any differing field breaks equality', () {
      expect(parse().copyWith(xp: 1), isNot(parse()));
      expect(parse().copyWith(avatarUrl: null), isNot(parse()));
    });
  });
}
