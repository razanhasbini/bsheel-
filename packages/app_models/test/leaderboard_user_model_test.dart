import 'package:app_models/app_models.dart';
import 'package:app_contracts/app_contracts.dart';
import 'package:test/test.dart';

Map<String, dynamic> leaderboardRow({
  Map<String, dynamic> overrides = const {},
}) =>
    {
      LeaderboardRpcColumns.rank: 3,
      LeaderboardRpcColumns.userId: 'user-1',
      ProfileColumns.username: 'ada',
      ProfileColumns.displayName: 'Ada L.',
      ProfileColumns.avatarUrl: 'https://cdn.test/ada.jpg',
      ProfileColumns.xp: 1250,
      ProfileColumns.level: 5,
      ProfileColumns.questsCompleted: 17,
      ...overrides,
    };

void main() {
  group('LeaderboardUserModel.fromJson', () {
    test('parses the get_leaderboard row', () {
      final row = LeaderboardUserModel.fromJson(leaderboardRow());

      expect(row.rank, 3);
      expect(row.userId, 'user-1');
      expect(row.username, 'ada');
      expect(row.displayName, 'Ada L.');
      expect(row.avatarUrl, 'https://cdn.test/ada.jpg');
      expect(row.xp, 1250);
      expect(row.level, 5);
      expect(row.questsCompleted, 17);
    });

    test('an entirely empty row degrades instead of throwing', () {
      // Every column here is coerced, so unlike most models in this package
      // the leaderboard never explodes on a partial RPC response.
      final row = LeaderboardUserModel.fromJson(const <String, dynamic>{});

      expect(row.rank, 0);
      expect(row.userId, isEmpty);
      expect(row.username, isEmpty);
      expect(row.displayName, isEmpty);
      expect(row.avatarUrl, isNull);
      expect(row.xp, 0);
      expect(row.level, 1);
      expect(row.questsCompleted, 0);
    });

    test('level falls back to 1, exactly like ProfileModel', () {
      // Regression guard. This model used to default level to 0 while
      // ProfileModel defaulted to 1, so the same NULL-level user rendered
      // "LVL 0" on the leaderboard and "LVL 1" on their own profile.
      // Levels are 1-based everywhere in the product.
      for (final bad in <Object?>[null, 'five', '']) {
        expect(
          LeaderboardUserModel.fromJson(leaderboardRow(overrides: {
            ProfileColumns.level: bad,
          })).level,
          1,
          reason: 'level=$bad should fall back to 1',
        );
      }
      final row = leaderboardRow()..remove(ProfileColumns.level);
      expect(LeaderboardUserModel.fromJson(row).level, 1);
    });

    test('bigint-as-string ranks and counts parse', () {
      // PostgREST serialises bigint/numeric as JSON strings.
      final row = LeaderboardUserModel.fromJson(leaderboardRow(overrides: {
        LeaderboardRpcColumns.rank: '3',
        ProfileColumns.xp: '1250',
        ProfileColumns.questsCompleted: '17',
      }));

      expect(row.rank, 3);
      expect(row.xp, 1250);
      expect(row.questsCompleted, 17);
    });

    test('doubles truncate and garbage falls back to 0', () {
      final row = LeaderboardUserModel.fromJson(leaderboardRow(overrides: {
        LeaderboardRpcColumns.rank: 3.9,
        ProfileColumns.xp: 'lots',
      }));

      expect(row.rank, 3);
      expect(row.xp, 0);
    });

    test('a decimal-string xp truncates like the num does', () {
      // Regression guard. The old per-model _toInt used int.tryParse only,
      // so PostgREST's numeric-as-text '1250.9' silently became 0.
      expect(
        LeaderboardUserModel.fromJson(leaderboardRow(overrides: {
          ProfileColumns.xp: '1250.9',
        })).xp,
        1250,
      );
    });

    test('a numeric user_id stringifies', () {
      expect(
        LeaderboardUserModel.fromJson(leaderboardRow(overrides: {
          LeaderboardRpcColumns.userId: 42,
        })).userId,
        '42',
      );
    });
  });

  group('LeaderboardUserModel.toJson', () {
    test('emits the 8 RPC columns', () {
      final json = LeaderboardUserModel.fromJson(leaderboardRow()).toJson();

      expect(json.keys.toSet(), {
        LeaderboardRpcColumns.rank,
        LeaderboardRpcColumns.userId,
        ProfileColumns.username,
        ProfileColumns.displayName,
        ProfileColumns.avatarUrl,
        ProfileColumns.xp,
        ProfileColumns.level,
        ProfileColumns.questsCompleted,
      });
      expect(json[LeaderboardRpcColumns.rank], 3);
    });

    test('round-trips without drift', () {
      final original = LeaderboardUserModel.fromJson(leaderboardRow());
      final restored = LeaderboardUserModel.fromJson(original.toJson());

      expect(restored.rank, original.rank);
      expect(restored.userId, original.userId);
      expect(restored.username, original.username);
      expect(restored.displayName, original.displayName);
      expect(restored.avatarUrl, original.avatarUrl);
      expect(restored.xp, original.xp);
      expect(restored.level, original.level);
      expect(restored.questsCompleted, original.questsCompleted);
    });

    test('a null avatar_url survives the round-trip as null', () {
      final original = LeaderboardUserModel.fromJson(leaderboardRow(
        overrides: {ProfileColumns.avatarUrl: null},
      ));

      expect(original.toJson()[ProfileColumns.avatarUrl], isNull);
      expect(
          LeaderboardUserModel.fromJson(original.toJson()).avatarUrl, isNull);
    });
  });

  group('LeaderboardUserModel value equality', () {
    // Regression guard. Equality used to be identity, so a re-fetch that
    // produced a byte-identical leaderboard still rebuilt every row.
    test('two rows parsed from the same payload are equal', () {
      final a = LeaderboardUserModel.fromJson(leaderboardRow());
      final b = LeaderboardUserModel.fromJson(leaderboardRow());

      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('a differing field breaks equality', () {
      final a = LeaderboardUserModel.fromJson(leaderboardRow());
      final b = LeaderboardUserModel.fromJson(leaderboardRow(overrides: {
        ProfileColumns.xp: 1251,
      }));

      expect(a, isNot(b));
    });
  });
}
