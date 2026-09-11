import 'package:app_models/app_models.dart';
import 'package:app_repositories/app_repositories.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/backend/app_backend.dart';
import '../../../core/providers/auth_session_provider.dart';

final mapRepositoryProvider =
    Provider<MapRepository>((ref) => AppBackend.repositories.map);
final mapCountriesProvider =
    FutureProvider.autoDispose<List<MapCountry>>((ref) {
  ref.watch(authSessionProvider);
  return ref.watch(mapRepositoryProvider).countries();
});
final mapProfileCountriesProvider =
    FutureProvider.autoDispose.family<List<MapCountry>, String>((ref, id) {
  ref.watch(authSessionProvider);
  return ref.watch(mapRepositoryProvider).countries(userId: id);
});
typedef MapFilter = ({
  String? country,
  String? category,
  String search,
  int offset,
  bool savedOnly
});
final mapPlacesProvider =
    FutureProvider.autoDispose.family<List<MapPlace>, MapFilter>((ref, filter) {
  ref.watch(authSessionProvider);
  return ref.watch(mapRepositoryProvider).places(
      country: filter.country,
      category: filter.category,
      search: filter.search,
      offset: filter.offset,
      savedOnly: filter.savedOnly);
});
final mapDetailProvider =
    FutureProvider.autoDispose.family<MapPlaceDetail, String>((ref, id) {
  ref.watch(authSessionProvider);
  return ref.watch(mapRepositoryProvider).detail(id);
});

/// The unfiltered first page of places, for the layers that must not follow
/// the user's filters: the fog cut-outs around confirmed discoveries and the
/// "places here" count. Same family as the filtered list, so a filter of
/// "everything" shares the request rather than doubling it.
const MapFilter mapAllPlacesFilter =
    (country: null, category: null, search: '', offset: 0, savedOnly: false);

/// World + per-country exploration, backend-authoritative. Watched by the map
/// and usable by the profile, so the two never disagree.
final mapProgressProvider = FutureProvider.autoDispose<MapProgress>((ref) {
  ref.watch(authSessionProvider);
  return ref.watch(mapRepositoryProvider).progress();
});

/// One country's trending / discovery quests, hidden count and collections.
final mapDiscoverProvider =
    FutureProvider.autoDispose.family<MapCountryDiscovery, String>((ref, code) {
  ref.watch(authSessionProvider);
  return ref.watch(mapRepositoryProvider).discover(code);
});

/// Whether the page loads OpenStreetMap tiles. Widget tests turn it off: the
/// test HTTP client answers every tile with 400 and the map is still fully
/// exercisable on its fog, pins and sheets alone.
final mapTilesEnabledProvider = Provider<bool>((ref) => true);
