import 'package:app_models/app_models.dart';
import 'package:supabase_contracts/supabase_contracts.dart';
import 'package:test/test.dart';

Map<String, dynamic> adminRow({Map<String, dynamic> overrides = const {}}) => {
      AdminColumns.id: 'admin-row-1',
      AdminColumns.userId: 'user-1',
      AdminColumns.role: AdminRole.superAdmin,
      AdminColumns.createdAt: '2026-05-03T12:00:00Z',
      ...overrides,
    };

void main() {
  group('AdminModel.fromJson', () {
    test('parses the row', () {
      final admin = AdminModel.fromJson(adminRow());

      expect(admin.id, 'admin-row-1');
      expect(admin.userId, 'user-1');
      expect(admin.role, 'super_admin');
      expect(admin.createdAt, DateTime.utc(2026, 5, 3, 12));
    });

    test('a null or missing role degrades to moderator, not super_admin', () {
      // The privilege default has to fail closed.
      expect(
        AdminModel.fromJson(adminRow(overrides: {AdminColumns.role: null}))
            .role,
        AdminRole.moderator,
      );
      final row = adminRow()..remove(AdminColumns.role);
      expect(AdminModel.fromJson(row).role, AdminRole.moderator);
    });

    test('missing id / user_id coerce to empty strings', () {
      final admin = AdminModel.fromJson({
        AdminColumns.createdAt: '2026-05-03T12:00:00Z',
      });

      expect(admin.id, isEmpty);
      expect(admin.userId, isEmpty);
      expect(admin.role, AdminRole.moderator);
    });

    test('a missing or malformed created_at degrades to the epoch', () {
      // Regression guard. created_at used to be parsed with a hard cast, so
      // one bad row threw a TypeError instead of degrading that row.
      final epoch = DateTime.utc(1970);

      expect(AdminModel.fromJson({}).createdAt, epoch);
      expect(
        AdminModel.fromJson(adminRow(overrides: {
          AdminColumns.createdAt: 'a while back',
        })).createdAt,
        epoch,
      );
    });

    test('a non-string role throws (hard cast)', () {
      expect(
        () => AdminModel.fromJson(adminRow(overrides: {AdminColumns.role: 1})),
        throwsA(isA<TypeError>()),
      );
    });
  });

  group('AdminModel role predicates', () {
    test('super_admin is a super admin and not a moderator', () {
      final admin = AdminModel.fromJson(adminRow());

      expect(admin.isSuperAdmin, isTrue);
      expect(admin.isModerator, isFalse);
    });

    test('moderator is a moderator and not a super admin', () {
      final admin = AdminModel.fromJson(adminRow(overrides: {
        AdminColumns.role: AdminRole.moderator,
      }));

      expect(admin.isSuperAdmin, isFalse);
      expect(admin.isModerator, isTrue);
    });

    test('an unrecognised role satisfies neither predicate', () {
      // ACTUAL behaviour: an off-contract role value (e.g. from a widened
      // CHECK constraint) reads as neither, so every admin-only surface
      // fails closed. Both predicates are exact-match, not hierarchical —
      // a super_admin is NOT also treated as a moderator.
      final admin = AdminModel.fromJson(adminRow(overrides: {
        AdminColumns.role: 'reviewer',
      }));

      expect(admin.isSuperAdmin, isFalse);
      expect(admin.isModerator, isFalse);
    });

    test('the role casing is significant', () {
      final admin = AdminModel.fromJson(adminRow(overrides: {
        AdminColumns.role: 'SUPER_ADMIN',
      }));

      expect(admin.isSuperAdmin, isFalse);
    });
  });

  group('AdminModel.toJson', () {
    test('emits all 4 columns and round-trips', () {
      final original = AdminModel.fromJson(adminRow());
      final json = original.toJson();

      expect(json.keys.toSet(), {
        AdminColumns.id,
        AdminColumns.userId,
        AdminColumns.role,
        AdminColumns.createdAt,
      });
      expect(json[AdminColumns.createdAt], '2026-05-03T12:00:00.000Z');

      final restored = AdminModel.fromJson(json);
      expect(restored.id, original.id);
      expect(restored.userId, original.userId);
      expect(restored.role, original.role);
      expect(restored.createdAt, original.createdAt);
      // Value equality (it used to be identity, so this was never true).
      expect(restored, original);
      expect(restored.hashCode, original.hashCode);
    });

    test('a differing role breaks equality', () {
      expect(
        AdminModel.fromJson(adminRow(overrides: {
          AdminColumns.role: AdminRole.moderator,
        })),
        isNot(AdminModel.fromJson(adminRow())),
      );
    });
  });
}
