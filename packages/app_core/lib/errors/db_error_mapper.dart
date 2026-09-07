/// Translates raw Supabase / Postgres / network errors into short
/// user-facing strings.
///
/// Used everywhere in the apps that previously did
/// `SnackBar(content: Text('Failed: $e'))` and leaked Postgres internals
/// (error codes, constraint names, function bodies) to end users.
///
/// Pass an optional [action] verb (e.g. `'save'`, `'delete'`, `'approve'`)
/// for the catch-all fallback message: "Failed to {action}. Please try
/// again."
///
/// The mapper is intentionally string-based — Supabase wraps Postgres
/// errors in a `PostgrestException` whose `.toString()` includes the
/// SQLSTATE code + the `RAISE EXCEPTION` message. That's what we
/// match against. Importing `supabase_flutter` here would force every
/// consumer to depend on it, which app_core doesn't.
library;

String mapDbError(Object error, {String action = 'continue'}) {
  final msg = error.toString();

  // Auth / authorization
  if (_has(msg, '42501') || _has(msg, 'Not authorized') ||
      _has(msg, 'permission denied') || _has(msg, 'Not authenticated')) {
    return 'You don\'t have permission to do that — please sign in again.';
  }

  // Not-found family
  if (_has(msg, 'P0002') || _has(msg, 'not found') ||
      _has(msg, 'No rows returned')) {
    return 'Couldn\'t find what you were looking for. It may have been removed.';
  }

  // App-raised P0001 — usually a friendly message we can pass through.
  if (_has(msg, 'P0001')) {
    // Try to extract the actual exception message after "MESSAGE:" or
    // after the SQLSTATE. PostgrestException stringifies as
    // "PostgrestException(message: ..., code: P0001, ...)".
    final extracted = _extractAfter(msg, 'message:') ??
        _extractAfter(msg, 'ERROR:');
    if (extracted != null && extracted.length < 200) {
      return extracted;
    }
    return 'Action blocked: please try again later.';
  }

  // Domain-specific shapes we already handle nicely.
  if (_has(msg, 'no longer pending')) {
    return 'This was already reviewed by another admin.';
  }
  if (_has(msg, 'rate limit') || _has(msg, 'cooldown')) {
    return 'Slow down — try again in a moment.';
  }
  if (_has(msg, '23505') || _has(msg, 'duplicate key')) {
    return 'That value is already taken. Try a different one.';
  }
  if (_has(msg, '23502') || _has(msg, 'null value')) {
    return 'A required field is missing.';
  }
  if (_has(msg, '23514') || _has(msg, 'check constraint')) {
    return 'That value isn\'t allowed.';
  }

  // Media upload — the R2 worker rejects the container or the declared
  // Content-Type doesn't match the body's magic bytes. Both are the same
  // thing to a user: this file won't upload.
  if (_has(msg, 'Unsupported file format') ||
      _has(msg, 'does not match Content-Type') ||
      _has(msg, 'is not allowed.')) {
    return 'That file format isn\'t supported. Try a JPEG/PNG photo or an MP4 video.';
  }

  // Networking / timeouts
  if (_has(msg, 'SocketException') || _has(msg, 'Failed host lookup') ||
      _has(msg, 'TimeoutException') || _has(msg, 'connection closed')) {
    return 'Network error — check your connection and try again.';
  }

  return 'Failed to $action. Please try again.';
}

bool _has(String haystack, String needle) =>
    haystack.toLowerCase().contains(needle.toLowerCase());

/// Pulls the text following a marker, trimmed and clipped at the next
/// comma / newline so we don't surface stack traces.
String? _extractAfter(String haystack, String marker) {
  final i = haystack.toLowerCase().indexOf(marker.toLowerCase());
  if (i < 0) return null;
  final tail = haystack.substring(i + marker.length).trimLeft();
  // Stop at first delimiter that suggests we've left the human-readable
  // part of the error.
  final stopChars = [',', '\n', ';', ')'];
  var end = tail.length;
  for (final ch in stopChars) {
    final idx = tail.indexOf(ch);
    if (idx >= 0 && idx < end) end = idx;
  }
  final clipped = tail.substring(0, end).trim();
  return clipped.isEmpty ? null : clipped;
}
