import 'package:app_models/app_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'session_providers.dart';

/// Every analytics read is keyed by business id, so switching business
/// re-fetches rather than showing the previous one's figures.
final analyticsSummaryProvider = FutureProvider.autoDispose
    .family<BusinessAnalyticsSummary, String>((ref, businessId) {
  return ref.watch(businessRepositoryProvider).analyticsSummary(businessId);
});

/// The window the completion chart covers. 30 days by default; the server
/// bounds it at 365 because the series is generated per day.
final dailyWindowProvider = StateProvider<int>((ref) => 30);

final dailyProvider = FutureProvider.autoDispose
    .family<List<BusinessDailyPoint>, String>((ref, businessId) {
  final days = ref.watch(dailyWindowProvider);
  return ref.watch(businessRepositoryProvider).daily(businessId, days: days);
});

/// The server caps this at 100 per request. Asking for the cap means the
/// filter below works over everything a business realistically has, and the
/// UI can say so when the list is actually truncated rather than pretending
/// the filter saw all of it.
const questPageSize = 100;

final questPerformanceProvider = FutureProvider.autoDispose
    .family<List<BusinessQuestPerformance>, String>((ref, businessId) {
  return ref
      .watch(businessRepositoryProvider)
      .questPerformance(businessId, limit: questPageSize);
});

/// Free-text filter over the loaded quest rows — title and place.
///
/// Applied on the client, over rows already fetched. That is honest only
/// because the fetch asks for the server's maximum and the section says so
/// when it hit it; a client-side filter over a partial list would quietly
/// answer "no quests match" about quests it had never seen.
final questFilterProvider = StateProvider<String>((ref) => '');

enum QuestSort { completions, starts, rate, title }

final questSortProvider =
    StateProvider<QuestSort>((ref) => QuestSort.completions);

final placePerformanceProvider = FutureProvider.autoDispose
    .family<List<BusinessPlacePerformance>, String>((ref, businessId) {
  return ref.watch(businessRepositoryProvider).placePerformance(businessId);
});

final visitorOriginsProvider = FutureProvider.autoDispose
    .family<BusinessVisitorOrigins, String>((ref, businessId) {
  return ref.watch(businessRepositoryProvider).visitorOrigins(businessId);
});

// Published proof is paged and accumulating, so it lives in
// proof_controller.dart rather than here: a FutureProvider can only hold
// the first page.
