import 'package:app_repositories/app_repositories.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'supabase_provider.dart';

/// Single underlying repo so mobile + admin_web share one read path
/// for admin role lookup. ARC-021.
final adminRepositoryProvider = Provider<AdminRepository>((ref) {
  return SupabaseAdminRepository(ref.watch(supabaseClientProvider));
});

/// True when the signed-in user has a row in `admins`.
final isAdminUserProvider = FutureProvider<bool>((ref) async {
  final role = await ref.watch(adminRoleProvider.future);
  return role != null;
});

/// Returns the admin role enum ('super_admin', 'moderator') or null.
/// Compat shim: callers that read this as a String get
/// `adminRoleProvider.future` → String? via [adminRoleProvider]'s
/// derived view. The legacy String provider is kept by transforming
/// the enum back to its DB string for any code still using it.
final adminRoleProvider = FutureProvider<String?>((ref) async {
  final role = await ref.watch(adminRoleEnumProvider.future);
  switch (role) {
    case AdminRoleEnum.superAdmin:
      return 'super_admin';
    case AdminRoleEnum.moderator:
      return 'moderator';
    case null:
      return null;
  }
});

/// Strongly-typed view of the admin role.
final adminRoleEnumProvider = FutureProvider<AdminRoleEnum?>((ref) async {
  return ref.watch(adminRepositoryProvider).getCurrentUserRole();
});

/// True only when the signed-in user is a super_admin.
final isSuperAdminProvider = FutureProvider<bool>((ref) async {
  final role = await ref.watch(adminRoleEnumProvider.future);
  return role?.isSuperAdmin ?? false;
});
