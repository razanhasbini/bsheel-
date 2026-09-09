import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../comments/presentation/widgets/comments_section.dart';

/// Total comments on a post — top-level plus replies — or `0` when the
/// count cannot be resolved.
///
/// The feed card and the post-detail action row both show `◌ 23`, and the
/// feed payload carries no comment count, so the number has to come from
/// the comments provider. Wrapping it here does two things a raw
/// `ref.watch(commentsProvider(id))` in `build` does not:
///
/// * a failure degrades to `0` instead of taking the whole card down. A
///   comment count is the least important thing on the card; it must never
///   be what stops a post from rendering.
/// * the arithmetic (`1 + replies.length` per thread) lives in one place
///   rather than being repeated on both surfaces.
///
/// Reading it does subscribe to the post's comments, so only the cards the
/// list has actually built pay for it.
final feedCommentCountProvider =
    Provider.autoDispose.family<int, String>((ref, submissionId) {
  try {
    return ref.watch(commentsProvider(submissionId)).maybeWhen(
          data: (comments) =>
              comments.fold<int>(0, (sum, c) => sum + 1 + c.replies.length),
          orElse: () => 0,
        );
  } catch (_) {
    // The comments repository itself was unavailable (an uninitialised
    // backend, for instance). Show no count rather than no post.
    return 0;
  }
});
