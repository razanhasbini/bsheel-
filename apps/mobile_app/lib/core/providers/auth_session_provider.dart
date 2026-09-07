import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_repository_provider.dart';

/// Provides the current auth session user, or null if not authenticated.
final authSessionProvider = StateProvider<User?>((ref) {
  return ref.watch(authRepositoryProvider).currentUser;
});
