import 'package:app_repositories/app_repositories.dart' show AuthUser;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_repository_provider.dart';

/// The current auth session user, or null when not authenticated.
final authSessionProvider = StateProvider<AuthUser?>((ref) {
  return ref.watch(authRepositoryProvider).currentUser;
});

/// Whether the signed-in user has a CAMARA-verified phone number on file.
/// False (not just absent) while signed out — the router's mandatory-
/// verification gate only applies once there is a session to gate.
final phoneVerifiedProvider = Provider<bool>((ref) {
  final user = ref.watch(authSessionProvider);
  return user?.userMetadata['phoneVerified'] == true;
});
