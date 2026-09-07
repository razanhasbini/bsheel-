import 'package:app_repositories/admin/admin_repository.dart';
import 'package:flutter_test/flutter_test.dart';

/// ARC-015 / ARC-021: pin the AdminRoleEnum enum's mapping so a typo in
/// the DB CHECK constraint or a stray manual UPDATE never silently
/// "downgrades" an admin to non-admin in the UI.
void main() {
  group('AdminRoleEnum.fromDbString', () {
    test("'super_admin' maps to AdminRoleEnum.superAdmin", () {
      expect(AdminRoleEnum.fromDbString('super_admin'), AdminRoleEnum.superAdmin);
    });

    test("'moderator' maps to AdminRoleEnum.moderator", () {
      expect(AdminRoleEnum.fromDbString('moderator'), AdminRoleEnum.moderator);
    });

    test('null / unknown role returns null', () {
      expect(AdminRoleEnum.fromDbString(null), isNull);
      expect(AdminRoleEnum.fromDbString(''), isNull);
      expect(AdminRoleEnum.fromDbString('owner'), isNull); // not in CHECK list
      expect(
        AdminRoleEnum.fromDbString('SUPER_ADMIN'),
        isNull,
        reason: 'case-sensitive — DB stores lowercase',
      );
    });
  });

  group('AdminRoleEnum.isSuperAdmin', () {
    test('only superAdmin reports true', () {
      expect(AdminRoleEnum.superAdmin.isSuperAdmin, isTrue);
      expect(AdminRoleEnum.moderator.isSuperAdmin, isFalse);
    });
  });
}
