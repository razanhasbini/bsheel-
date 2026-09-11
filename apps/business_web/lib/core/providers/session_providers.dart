import 'package:app_models/app_models.dart';
import 'package:app_repositories/app_repositories.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../backend/app_backend.dart';

final authRepositoryProvider =
    Provider<AuthRepository>((ref) => AppBackend.repositories.auth);

final businessRepositoryProvider =
    Provider<BusinessRepository>((ref) => AppBackend.repositories.business);

/// The signed-in user, or null. Poked by the login flow so the router
/// re-evaluates the moment a session appears or is cleared.
final sessionProvider = StateProvider<AuthUser?>(
    (ref) => ref.watch(authRepositoryProvider).currentUser);

/// Businesses this user may act for.
///
/// This is the whole gate for the app: an empty list means the signed-in
/// person is not a business member, and there is nothing here for them.
/// Unlike the mobile card, failures are **not** swallowed — this app is
/// the dashboard, so a failed read is the screen's subject rather than a
/// missing ornament, and the router must be able to tell "not a member"
/// from "could not ask".
final myBusinessesProvider = FutureProvider<List<BusinessSummary>>((ref) async {
  final session = ref.watch(sessionProvider);
  if (session == null) return const [];
  return ref.watch(businessRepositoryProvider).mine();
});

/// Which business the dashboard is showing.
///
/// Almost every member belongs to exactly one. The `?business=` query
/// parameter the mobile app appends selects among several; an id that is
/// not the caller's simply does not match and the first is used, because
/// the server would refuse it anyway.
final selectedBusinessIdProvider = StateProvider<String?>((ref) => null);

/// The business currently on screen, resolved against what the caller may
/// actually see rather than trusted from the URL.
final activeBusinessProvider = Provider<BusinessSummary?>((ref) {
  final businesses = ref.watch(myBusinessesProvider).valueOrNull ?? const [];
  if (businesses.isEmpty) return null;
  final requested = ref.watch(selectedBusinessIdProvider);
  return businesses.firstWhere(
    (business) => business.id == requested,
    orElse: () => businesses.first,
  );
});
