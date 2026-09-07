import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app_repositories/app_repositories.dart';
import '../config/env.dart';
import 'supabase_provider.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return SupabaseAuthRepository(
    ref.watch(supabaseClientProvider),
    googleIosClientId: Env.googleIosClientId,
    googleWebClientId: Env.googleWebClientId,
  );
});
