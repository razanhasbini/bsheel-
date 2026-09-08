/// Single canonical "x time ago" formatter shared between mobile +
/// admin web. Replaces the seven divergent `_timeAgo` implementations
/// flagged in ARC-020.
///
/// The output is intentionally short ("3m", "5h", "2d", "3w", "2y") so
/// it fits in tight chips and rows. For any single comment / row the
/// output is identical regardless of which surface renders it.
library;

String timeAgo(DateTime when, {DateTime? now}) {
  final ref = now ?? DateTime.now();
  final diff = ref.difference(when);

  if (diff.isNegative) return 'now';
  if (diff.inSeconds < 30) return 'now';
  if (diff.inMinutes < 1) return '${diff.inSeconds}s';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m';
  if (diff.inHours < 24) return '${diff.inHours}h';
  if (diff.inDays < 7) return '${diff.inDays}d';
  if (diff.inDays < 30) return '${(diff.inDays / 7).floor()}w';
  if (diff.inDays < 365) return '${(diff.inDays / 30).floor()}mo';
  return '${(diff.inDays / 365).floor()}y';
}

/// Long form of [timeAgo] with the " ago" suffix ("3m ago", "2d ago").
/// Single source of truth for the `'${timeAgo(dt)} ago'` wrappers that
/// were previously re-implemented per page (feed post details,
/// submission status, admin).
String timeAgoLong(DateTime when, {DateTime? now}) =>
    '${timeAgo(when, now: now)} ago';
