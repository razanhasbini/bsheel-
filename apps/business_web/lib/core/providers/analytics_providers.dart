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

final questPerformanceProvider = FutureProvider.autoDispose
    .family<List<BusinessQuestPerformance>, String>((ref, businessId) {
  return ref.watch(businessRepositoryProvider).questPerformance(businessId);
});

final placePerformanceProvider = FutureProvider.autoDispose
    .family<List<BusinessPlacePerformance>, String>((ref, businessId) {
  return ref.watch(businessRepositoryProvider).placePerformance(businessId);
});

final visitorOriginsProvider = FutureProvider.autoDispose
    .family<BusinessVisitorOrigins, String>((ref, businessId) {
  return ref.watch(businessRepositoryProvider).visitorOrigins(businessId);
});

final publicProofProvider = FutureProvider.autoDispose
    .family<BusinessProofPage, String>((ref, businessId) {
  return ref.watch(businessRepositoryProvider).proof(businessId);
});
