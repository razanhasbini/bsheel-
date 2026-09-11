import 'package:app_contracts/app_contracts.dart';
import 'package:app_core/app_core.dart' show QuestTheme;
import 'package:app_models/app_models.dart';
import 'package:app_repositories/app_repositories.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/core/providers/auth_session_provider.dart';
import 'package:mobile_app/features/feed/presentation/pages/feed_page.dart';
import 'package:mobile_app/features/feed/presentation/providers/feed_provider.dart';
import 'package:mobile_app/features/feed/presentation/providers/post_realtime_provider.dart';
import 'package:mobile_app/l10n/app_localizations.dart';

/// Records what the feed asks the server for, so a sort tap can be checked
/// against the request that left the client rather than only the UI state.
class _RecordingFeedRepository implements FeedRepository {
  final calls = <({
    int limit,
    int offset,
    String sort,
    FeedScope scope,
    String? cursor
  })>[];

  @override
  Future<List<FeedPostModel>> getFeed({
    int limit = 20,
    int offset = 0,
    String sort = 'recent',
    FeedScope scope = FeedScope.all,
    String? cursor,
  }) async {
    calls.add((
      limit: limit,
      offset: offset,
      sort: sort,
      scope: scope,
      cursor: cursor,
    ));
    return _posts;
  }

  @override
  Future<FeedPostModel> getFeedPostDetails(String submissionId) async =>
      _posts.first;
}

/// Only `build()` is faked: `changeSort` stays the real implementation, so
/// the test exercises the production sort path and its repository call.
class _FixtureFeedNotifier extends FeedNotifier {
  @override
  Future<FeedState> build() async => FeedState(posts: _posts, hasMore: false);
}

Widget _app(ProviderContainer container) {
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: QuestTheme.light,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: const FeedPage(),
    ),
  );
}

ProviderContainer _container(_RecordingFeedRepository repository) {
  return ProviderContainer(
    overrides: [
      // Signed out, so the post cards never reach the reactions repository
      // and no avatar/media request is made. The feed content itself comes
      // from the notifier override below.
      authSessionProvider.overrideWith((ref) => null),
      feedRepositoryProvider.overrideWithValue(repository),
      feedProvider.overrideWith(_FixtureFeedNotifier.new),
      // The real one opens a websocket through AppBackend.
      feedRealtimeProvider.overrideWith((ref) {}),
    ],
  );
}

void main() {
  testWidgets('the feed header opens the sort sheet and shows the choice',
      (tester) async {
    // 320dp wide: the narrowest supported phone, where the overlay row is
    // most likely to overflow.
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repository = _RecordingFeedRepository();
    final container = _container(repository);
    addTearDown(container.dispose);

    await tester.pumpWidget(_app(container));
    await tester.pumpAndSettle();

    // On the default ordering the overlay is the bare legacy one: no sort
    // pill, nothing to clear, and the sheet-only sorts are not on screen.
    expect(find.textContaining('SORTED BY'), findsNothing);
    expect(find.text('MOST UPVOTED'), findsNothing);

    // The sheet is reachable: one tap on the filter glyph.
    await tester.tap(find.byIcon(Icons.filter_list_rounded));
    await tester.pumpAndSettle();

    expect(find.text('FILTER FEED'), findsOneWidget);
    for (final label in const [
      'MOST UPVOTED',
      'TRENDY',
      'LEAST UPVOTED',
      'GRAVEYARD',
    ]) {
      expect(find.text(label), findsOneWidget, reason: '$label unreachable');
    }

    // Picking a sheet-only sort must change what the provider requests.
    repository.calls.clear();
    await tester.tap(find.text('MOST UPVOTED'));
    await tester.pumpAndSettle();

    expect(container.read(feedSortProvider), 'top');
    expect(repository.calls, isNotEmpty);
    expect(repository.calls.map((call) => call.sort), everyElement('top'));
    // A new ordering restarts paging. Carrying anything over from the
    // previous sort — an offset, or a keyset cursor minted under the old
    // ordering — would splice two different orderings together.
    expect(repository.calls.map((call) => call.offset), everyElement(0));
    expect(repository.calls.map((call) => call.cursor), everyElement(isNull));

    // And the overlay now says which ordering the user is looking at.
    expect(find.text('SORTED BY MOST UPVOTED'), findsOneWidget);

    // Tapping the pill drops back to the default sort and the pill goes.
    await tester.tap(find.text('SORTED BY MOST UPVOTED'));
    await tester.pumpAndSettle();

    expect(container.read(feedSortProvider), 'recent');
    expect(find.textContaining('SORTED BY'), findsNothing);
    expect(repository.calls.last.sort, 'recent');
  });
}

final _submittedAt = DateTime.utc(2026, 4, 12, 12);

final _posts = <FeedPostModel>[
  FeedPostModel(
    id: 'post-1',
    // Empty on purpose: no media URL means no network image in the test.
    mediaUrl: '',
    mediaType: MediaType.image,
    caption: 'Proof one.',
    submittedAt: _submittedAt,
    userId: 'user-1',
    username: 'bitsheel',
    displayName: 'Bit Sheel',
    questId: 'quest-1',
    questTitle: 'Find a quiet corner',
    questCategory: QuestCategory.social,
    upvoteCount: 5,
    downvoteCount: 1,
    netScore: 4,
  ),
];
