/// Media-URL helpers shared across surfaces.
library;

/// True when [url] points at a video asset, judged by file extension.
///
/// Single source of truth for the extension set (mp4 / mov / webm /
/// m4v) that was previously duplicated in four private helpers
/// (reels_card, feed_post_details_page ×2, search_page) — all four
/// used exactly this set, so this is the union.
///
/// Deliberately uses `contains` rather than `endsWith`: R2/Supabase
/// media URLs can carry query strings after the extension. Callers
/// with extra context (e.g. a post's `mediaType`) OR their own
/// fallback on top of this check.
bool isVideoUrl(String url) {
  final l = url.toLowerCase();
  return l.contains('.mp4') ||
      l.contains('.mov') ||
      l.contains('.webm') ||
      l.contains('.m4v');
}
