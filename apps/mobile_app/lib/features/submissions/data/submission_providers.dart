import 'package:app_core/app_core.dart' show AppLogger;
import 'package:app_models/app_models.dart';
import 'package:app_repositories/app_repositories.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/auth_session_provider.dart';
import '../../../core/backend/app_backend.dart';

final submissionsRepositoryProvider = Provider<SubmissionsRepository>((ref) {
  return AppBackend.repositories.submissions;
});

// SWR cache so a transient fetch failure keeps last known submissions
// on screen instead of flashing an empty state.
List<SubmissionModel>? _lastGoodUserSubmissions;

/// Drops the module-scoped SWR cache. Call on sign-out so the next user
/// on the same device can't see the previous user's submissions briefly.
void resetSubmissionsCache() {
  _lastGoodUserSubmissions = null;
}

final userSubmissionsProvider =
    FutureProvider<List<SubmissionModel>>((ref) async {
  // Keep dependency so auth changes re-evaluate this provider.
  final user = ref.watch(authSessionProvider);
  if (user == null) {
    _lastGoodUserSubmissions = null;
    return const [];
  }

  final repository = ref.watch(submissionsRepositoryProvider);
  try {
    final fresh = await repository
        .getUserSubmissions(user.id)
        .timeout(const Duration(seconds: 8));
    _lastGoodUserSubmissions = fresh;
    return fresh;
  } catch (e) {
    if (_lastGoodUserSubmissions != null) {
      AppLogger.warning('[UserSubmissions] Fetch failed, serving cached: $e');
      return _lastGoodUserSubmissions!;
    }
    rethrow;
  }
});

/// Submissions for a specific user (used when viewing another profile).
final userSubmissionsByUserProvider = FutureProvider.autoDispose
    .family<List<SubmissionModel>, String>((ref, userId) async {
  final repository = ref.watch(submissionsRepositoryProvider);
  return repository.getUserSubmissions(userId);
});

final submissionByIdProvider =
    FutureProvider.autoDispose.family<SubmissionModel?, String>((
  ref,
  submissionId,
) async {
  final repository = ref.watch(submissionsRepositoryProvider);
  return repository.getSubmission(submissionId);
});
