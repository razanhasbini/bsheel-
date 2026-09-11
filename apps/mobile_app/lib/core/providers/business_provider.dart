import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app_models/app_models.dart';
import 'package:app_repositories/app_repositories.dart';
import '../backend/app_backend.dart';
import 'auth_session_provider.dart';

final businessRepositoryProvider = Provider<BusinessRepository>((ref) {
  return AppBackend.repositories.business;
});

/// Businesses the signed-in user belongs to.
///
/// Empty for almost everyone, and that is the design: being a business
/// changes nothing about being a player, so this is the only thing the
/// consumer app asks. It is watched by the profile page to decide whether to
/// offer the dashboard at all.
///
/// Failures resolve to an empty list rather than an error. A business card
/// is an addition to someone's profile, and a network blip on this call must
/// not be able to take their profile down with it.
final myBusinessesProvider =
    FutureProvider.autoDispose<List<BusinessSummary>>((ref) async {
  // Rebuilds on sign-in/out, so a signed-out session never serves a stale
  // business card from the previous user.
  final session = ref.watch(authSessionProvider);
  if (session == null) return const [];
  try {
    return await ref.watch(businessRepositoryProvider).mine();
  } catch (_) {
    return const [];
  }
});
