import 'package:app_models/app_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'session_providers.dart';

/// Every analytics read is keyed by business id, so switching business
/// re-fetches rather than showing the previous one's figures.
final analyticsSummaryProvider = FutureProvider.autoDispose
    .family<BusinessAnalyticsSummary, String>((ref, businessId) {
  return ref.watch(businessRepositoryProvider).analyticsSummary(businessId);
});

/// What the completion chart covers: a rolling preset, or an explicit
/// range once someone picks dates.
///
/// One provider for both so the chart cannot end up showing a range while
/// a preset button looks selected.
class DailyWindowSelection {
  const DailyWindowSelection.preset(this.days)
      : from = null,
        to = null;
  const DailyWindowSelection.range(String this.from, String this.to)
      : days = 30;

  final int days;
  final String? from;
  final String? to;

  bool get isRange => from != null && to != null;
}

final dailyWindowProvider = StateProvider<DailyWindowSelection>(
    (ref) => const DailyWindowSelection.preset(30));

final dailyProvider = FutureProvider.autoDispose
    .family<BusinessDailySeries, String>((ref, businessId) {
  final selection = ref.watch(dailyWindowProvider);
  return ref.watch(businessRepositoryProvider).daily(
        businessId,
        days: selection.days,
        from: selection.from,
        to: selection.to,
      );
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

/// Free-text filter over the place cards — name, city, country.
///
/// Unlike the quest list this needs no cap warning: the endpoint returns
/// every place the business owns, with no limit, so the filter always sees
/// all of them.
final placeFilterProvider = StateProvider<String>((ref) => '');

enum PlaceSort { completions, visitors, saves, name }

final placeSortProvider =
    StateProvider<PlaceSort>((ref) => PlaceSort.completions);

final visitorOriginsProvider = FutureProvider.autoDispose
    .family<BusinessVisitorOrigins, String>((ref, businessId) {
  return ref.watch(businessRepositoryProvider).visitorOrigins(businessId);
});

// Published proof is paged and accumulating, so it lives in
// proof_controller.dart rather than here: a FutureProvider can only hold
// the first page.
