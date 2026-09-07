import 'package:flutter_riverpod/flutter_riverpod.dart';

/// UX-002: stores the deep-link path the user was trying to reach when
/// the auth redirect bounced them to /login.
///
/// Set by the router redirect whenever a logged-out user lands on a
/// route that requires auth. Consumed by that same redirect in
/// `app_router.dart`: when a freshly-logged-in user is about to be sent
/// to /home, it calls `consume()` — which returns the saved path (and
/// clears it) — so navigation lands on the originally-intended URL.
///
/// Routes that are themselves part of the auth flow (login / signup /
/// forgot / reset / onboarding / splash) are intentionally not saved
/// — there's no useful "intended destination" if the user was already
/// on an auth screen.
class PendingDeepLink extends StateNotifier<String?> {
  PendingDeepLink() : super(null);

  /// Save the user's intended URI. No-op if the URI looks like an auth
  /// route or splash, so we don't accidentally bounce the user back to
  /// `/login` after they sign in.
  void save(String uri) {
    if (_isAuthLike(uri) || uri.isEmpty || uri == '/') return;
    state = uri;
  }

  /// Read + clear in one call. Returns null if nothing was queued.
  String? consume() {
    final saved = state;
    state = null;
    return saved;
  }

  bool _isAuthLike(String uri) {
    const authPrefixes = [
      '/login',
      '/signup',
      '/forgot-password',
      '/reset-password',
      '/onboarding',
      '/splash',
    ];
    return authPrefixes.any((p) => uri == p || uri.startsWith('$p/'));
  }
}

final pendingDeepLinkProvider =
    StateNotifierProvider<PendingDeepLink, String?>((ref) {
  return PendingDeepLink();
});
