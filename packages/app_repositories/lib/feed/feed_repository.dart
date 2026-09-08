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
  Future<List<FeedPostModel>> getFeed({
    int limit = 20,
    int offset = 0,
    String sort = 'recent',
    FeedScope scope = FeedScope.all,
  });
  Future<FeedPostModel> getFeedPostDetails(String submissionId);
}
