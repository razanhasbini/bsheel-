import 'package:app_models/app_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/backend/app_backend.dart';

/// Journeys this player is walking.
///
/// The single source for Home, the Active card and the map, so they cannot
/// disagree about where a journey is. Invalidate it after anything that
/// changes progression — continuing, or acknowledging an unlock.
final activeJourneysProvider =
    FutureProvider.autoDispose<List<JourneyRun>>((ref) async {
  return AppBackend.repositories.journeys.active();
});

/// The journey to show on Home, if any.
///
/// One at a time: Home has room for one hero, and a journey with something
/// the player can act on right now beats one waiting on a moderator or on a
/// teammate. Without that ordering the card could sit on a journey that
/// offers no action while another has a checkpoint ready.
final featuredJourneyProvider = Provider.autoDispose<JourneyRun?>((ref) {
  final runs = ref.watch(activeJourneysProvider).valueOrNull ?? const [];
  if (runs.isEmpty) return null;
  final actionable = runs.where((r) => r.canContinue).toList();
  if (actionable.isNotEmpty) return actionable.first;
  return runs.first;
});

/// A journey the server still owes this player an unlock moment for.
///
/// Read from the run rather than from local storage: a checkpoint approved
/// while the app was closed must still get its celebration, and reinstalling
/// must not replay one already seen. Only the backend knows both.
final unseenUnlockProvider = Provider.autoDispose<JourneyRun?>((ref) {
  final runs = ref.watch(activeJourneysProvider).valueOrNull ?? const [];
  for (final run in runs) {
    if (run.unseenUnlock != null) return run;
  }
  return null;
});
