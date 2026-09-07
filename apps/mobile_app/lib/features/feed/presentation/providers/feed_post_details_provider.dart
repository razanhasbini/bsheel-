import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app_models/app_models.dart';
import 'feed_provider.dart';

final feedPostDetailsProvider = FutureProvider.autoDispose
    .family<FeedPostModel, String>((ref, submissionId) async {
  try {
    return await ref.watch(feedRepositoryProvider).getFeedPostDetails(submissionId);
  } catch (e, st) {
    if (kDebugMode) debugPrint('[FeedPostDetails] ERROR loading $submissionId: $e\n$st');
    rethrow;
  }
});
