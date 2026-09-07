import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app_models/app_models.dart';
import 'package:app_repositories/app_repositories.dart';
import '../../../core/providers/supabase_provider.dart';

final collabRepositoryProvider = Provider<CollabRepository>((ref) {
  return SupabaseCollabRepository(ref.watch(supabaseClientProvider));
});

final collabGroupStatusProvider =
    FutureProvider.autoDispose.family<CollabGroupStatusModel, String>(
  (ref, userQuestId) async {
    return ref.watch(collabRepositoryProvider).getGroupStatus(userQuestId);
  },
);

final collabGroupDetailsProvider =
    FutureProvider.autoDispose.family<CollabGroupPreviewModel, String>(
  (ref, code) async {
    return ref.watch(collabRepositoryProvider).getGroupDetails(code);
  },
);
