import 'package:app_repositories/app_repositories.dart' show AuthUser;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_repository_provider.dart';

/// The current auth session user, or null when not authenticated.
final authSessionProvider = StateProvider<AuthUser?>((ref) {
  return ref.watch(authRepositoryProvider).currentUser;
});
