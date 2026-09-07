/// Admin role lookup, shared between mobile and admin web.
///
/// Defines a tiny enum + read method so both apps can reason about
/// the caller's admin role without each rolling its own provider that
/// reads the `admins` table directly. Solves ARC-021.
///
/// Named `AdminRoleEnum` (not `AdminRole`) because supabase_contracts
/// already exposes an abstract-final `AdminRole` class with static
/// constants for the DB string values. The two are complementary — the
/// enum here is the typed in-memory shape, the constants over there are
/// the wire-format strings.
abstract class AdminRepository {
  Future<AdminRoleEnum?> getCurrentUserRole();
}

enum AdminRoleEnum {
  superAdmin,
  moderator;

  static AdminRoleEnum? fromDbString(String? raw) {
    switch (raw) {
      case 'super_admin':
        return AdminRoleEnum.superAdmin;
      case 'moderator':
        return AdminRoleEnum.moderator;
      default:
        return null;
    }
  }

  bool get isSuperAdmin => this == AdminRoleEnum.superAdmin;
}
