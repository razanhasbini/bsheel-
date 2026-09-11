import 'package:app_models/app_models.dart';
import 'package:app_repositories/app_repositories.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'session_providers.dart';

/// One accumulating page of published proof.
///
/// A single `FutureProvider` could only ever hold the first page, so a
/// business with fifty community posts saw twenty and nothing saying there
/// were more. Silently truncating somebody's data is worse than making them
/// press a button for it.
class ProofFeed {
  const ProofFeed({
    this.items = const [],
    this.cursor,
    this.loading = false,
    this.loadingMore = false,
    this.error,
  });

  final List<BusinessPublicProof> items;

  /// Null once the last page has been read — which is also how "there is
  /// no more" is distinguished from "there might be".
  final BusinessProofCursor? cursor;
  final bool loading, loadingMore;
  final Object? error;

  bool get hasMore => cursor != null;

  ProofFeed copyWith({
    List<BusinessPublicProof>? items,
    Object? cursor = _unset,
    bool? loading,
    bool? loadingMore,
    Object? error = _unset,
  }) =>
      ProofFeed(
        items: items ?? this.items,
        cursor: cursor == _unset ? this.cursor : cursor as BusinessProofCursor?,
        loading: loading ?? this.loading,
        loadingMore: loadingMore ?? this.loadingMore,
        error: error == _unset ? this.error : error,
      );

  static const _unset = Object();
}

class ProofController extends StateNotifier<ProofFeed> {
  ProofController(this._read, this._businessId) : super(const ProofFeed()) {
    refresh();
  }

  final BusinessRepositoryReader _read;
  final String _businessId;

  Future<void> refresh() async {
    state = const ProofFeed(loading: true);
    try {
      final page = await _read().proof(_businessId);
      state = ProofFeed(items: page.items, cursor: page.nextCursor);
    } catch (error) {
      state = ProofFeed(error: error);
    }
  }

  Future<void> loadMore() async {
    final cursor = state.cursor;
    // Guarded against a double tap and against running past the end; both
    // would duplicate rows in the list.
    if (cursor == null || state.loadingMore || state.loading) return;
    state = state.copyWith(loadingMore: true, error: null);
    try {
      final page = await _read().proof(_businessId, cursor: cursor);
      state = state.copyWith(
        items: [...state.items, ...page.items],
        cursor: page.nextCursor,
        loadingMore: false,
      );
    } catch (error) {
      // Keeps what is already on screen and keeps the cursor, so a failed
      // page can be retried without losing the pages before it.
      state = state.copyWith(loadingMore: false, error: error);
    }
  }
}

/// Indirection so the controller takes a reader rather than a Ref, which
/// keeps it constructible in a test without a container.
typedef BusinessRepositoryReader = BusinessRepository Function();

final proofControllerProvider = StateNotifierProvider.autoDispose
    .family<ProofController, ProofFeed, String>((ref, businessId) {
  return ProofController(
      () => ref.read(businessRepositoryProvider), businessId);
});
