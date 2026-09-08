import 'package:app_repositories/app_repositories.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/backend/app_backend.dart';
import 'repository_providers.dart';

/// The signed-in user's id, or null. Re-emits on every auth transition.
///
/// [adminRoleEnumProvider] watches this so role resolution is keyed to
/// identity. Without it the role was fetched once, at startup, while still
/// signed out — `GET admin/me` answered 401, the FutureProvider cached that
/// failure for the life of the app, and nothing invalidated it on sign-in.
/// The router's redirect then read `valueOrNull == null` forever and bounced
/// every authenticated route straight back to /login, so a correct login
/// (HTTP 200, tokens stored) left the user sitting on the login page with no
/// error to explain it.
///
/// Keying on identity fixes the class of bug rather than the instance: sign
/// out, or sign in as a different user, and the role is refetched because the
/// dependency changed. There is no invalidation call for a future change to
/// forget.
final authUserIdProvider = StreamProvider<String?>((ref) {
  final repository = ref.watch(authRepositoryProvider);
  return repository.authStateChanges
      .map((state) => state.session?.user.id)
      // Seed the current value so the first read does not sit in `loading`
      // when a session already exists (a page refresh with stored tokens).
      .startWith(repository.currentUser?.id);
});

/// `Stream.startWith` is not in dart:async.
extension _StartWith<T> on Stream<T> {
  Stream<T> startWith(T value) async* {
    yield value;
    yield* this;
  }
}

/// Single underlying repo so mobile + admin_web share one read path
/// for admin role lookup. ARC-021.
final adminRepositoryProvider = Provider<AdminRepository>((ref) {
  return AppBackend.repositories.admin;
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
  // Keyed to identity: a signed-out user has no role, and a sign-in
  // re-runs this with the new token rather than serving the 401 cached
  // at startup. See [authUserIdProvider].
  final userId = await ref.watch(authUserIdProvider.future);
  if (userId == null) return null;
  return ref.watch(adminRepositoryProvider).getCurrentUserRole();
});

/// True only when the signed-in user is a super_admin.
final isSuperAdminProvider = FutureProvider<bool>((ref) async {
  final role = await ref.watch(adminRoleEnumProvider.future);
  return role?.isSuperAdmin ?? false;
});
