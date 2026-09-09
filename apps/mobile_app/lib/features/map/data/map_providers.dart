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
final mapProfileCountriesProvider=FutureProvider.autoDispose.family<List<MapCountry>,String>((ref,id){
  ref.watch(authSessionProvider);
  return ref.watch(mapRepositoryProvider).countries(userId:id);
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
      offset: filter.offset,savedOnly:filter.savedOnly);
});
final mapDetailProvider =
    FutureProvider.autoDispose.family<MapPlaceDetail, String>((ref, id) {
  ref.watch(authSessionProvider);
  return ref.watch(mapRepositoryProvider).detail(id);
});
