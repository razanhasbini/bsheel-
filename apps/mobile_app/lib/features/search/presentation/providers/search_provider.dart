import 'package:app_models/app_models.dart';
import 'package:app_repositories/app_repositories.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/providers/auth_session_provider.dart';
import '../../../../core/providers/supabase_provider.dart';

final searchRepositoryProvider = Provider<SearchRepository>((ref) {
  return SupabaseSearchRepository(ref.watch(supabaseClientProvider));
});

/// Raw text in the search field. Trimmed before any query runs.
final searchQueryProvider = StateProvider<String>((ref) => '');

// ── Recent searches ─────────────────────────────────────────────────────────

const _recentKey = 'search.recent';
const _recentMax = 8;

class RecentSearchesNotifier extends StateNotifier<List<String>> {
  RecentSearchesNotifier() : super(const []) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getStringList(_recentKey) ?? const [];
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_recentKey, state);
  }

  Future<void> add(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;
    final lower = trimmed.toLowerCase();
    final without =
        state.where((q) => q.toLowerCase() != lower).toList(growable: true);
    without.insert(0, trimmed);
    if (without.length > _recentMax) without.removeRange(_recentMax, without.length);
    state = without;
    await _persist();
  }

  Future<void> clear() async {
    state = const [];
    await _persist();
  }
}

final recentSearchesProvider =
    StateNotifierProvider<RecentSearchesNotifier, List<String>>(
        (ref) => RecentSearchesNotifier());

class SearchResults {
  const SearchResults({
    required this.users,
    required this.quests,
    required this.posts,
  });
  final List<ProfileModel> users;
  final List<QuestModel> quests;
  final List<SubmissionModel> posts;

  bool get isEmpty => users.isEmpty && quests.isEmpty && posts.isEmpty;

  static const empty =
      SearchResults(users: [], quests: [], posts: []);
}

final searchResultsProvider =
    FutureProvider.autoDispose<SearchResults>((ref) async {
  final rawQuery = ref.watch(searchQueryProvider).trim();
  if (rawQuery.isEmpty) return SearchResults.empty;
  // Sanitize PostgREST/ilike metacharacters so a user typing `100%` or
  // `foo_bar` doesn't get a wildcard search by accident, and the
  // underlying RPC sees literal text. Backslash is also escaped so
  // we don't terminate a stringly-interpolated SQL pattern.
  final query = rawQuery
      .replaceAll('\\', r'\\')
      .replaceAll('%', r'\%')
      .replaceAll('_', r'\_');
  // Min-length guard: 1-2 char queries hit a giant trigram index and
  // return mostly junk anyway. Wait until the user has typed at least
  // 2 characters before firing the cross-table search.
  if (query.length < 2) return SearchResults.empty;

  // Debounce: if the user keeps typing within 280ms, this closure is replaced
  // by a newer one before the network call fires, so we save requests.
  await Future<void>.delayed(const Duration(milliseconds: 280));
  if (ref.read(searchQueryProvider).trim() != rawQuery) return SearchResults.empty;

  final repo = ref.read(searchRepositoryProvider);
  final currentUser = ref.read(authSessionProvider);
  final currentUserId = currentUser?.id ?? '';

  final results = await Future.wait([
    repo.searchUsers(query),
    repo.searchQuests(query),
    if (currentUserId.isNotEmpty)
      repo.searchPosts(query, currentUserId: currentUserId)
    else
      Future<List<SubmissionModel>>.value(const []),
  ]);
  return SearchResults(
    users: results[0] as List<ProfileModel>,
    quests: results[1] as List<QuestModel>,
    posts: results[2] as List<SubmissionModel>,
  );
});
