import 'package:app_models/app_models.dart';

/// Which feed scope the caller wants. Maps to the `p_scope` parameter
/// on the get_feed RPC introduced in migration 0135 (ARC-011).
enum FeedScope {
  /// Global public feed across all approved posts.
  all,

  /// Only posts authored by users the caller follows.
  following,
}

extension FeedScopeRpc on FeedScope {
  String get rpcValue {
    switch (this) {
      case FeedScope.all:
        return 'all';
      case FeedScope.following:
        return 'following';
    }
  }
}

abstract class FeedRepository {
  /// One page of the feed.
  ///
  /// Pass [cursor] — the `nextCursor` of the last row you received — rather
  /// than [offset]. The server implements keyset pagination and returns a
  /// cursor per row; paging by offset duplicates and skips cards whenever a
  /// score changes between pages, which happens constantly on a live feed.
  /// [offset] is kept for the first page and for callers that do not paginate.
  Future<List<FeedPostModel>> getFeed({
    int limit = 20,
    int offset = 0,
    String? cursor,
    String sort = 'recent',
    FeedScope scope = FeedScope.all,
  });
  Future<FeedPostModel> getFeedPostDetails(String submissionId);
}
