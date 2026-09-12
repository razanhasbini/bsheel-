/// Shared, defensive coercions for the snake_case JSON these models decode.
///
/// Every model in this package used to carry its own private `_toInt` /
/// `_toDateTime` / boolean coercion, and those copies had drifted apart:
/// `'250'` parsed in one model and threw in another, the string `'99.9'`
/// became `0` while the num `99.9` became `99`, and three different rules
/// for a missing timestamp coexisted. The rules live here once so they
/// cannot diverge again. Not exported from `app_models.dart` — this is
/// package-internal.
library;

import 'dart:convert';

// ─── Timestamps ──────────────────────────────────────────────────────────
//
// THE TIMESTAMP RULE FOR THIS PACKAGE (one rule, applied everywhere):
//
//  * A REQUIRED timestamp — `created_at`, `submitted_at`, `assigned_at`,
//    `saved_at`, `display_date`, a collab group's `expires_at` — that is
//    missing, null or unparseable degrades to [epochTimestamp] via
//    [coerceTimestamp]. It must NOT throw: these models decode pages of
//    rows, and a `DateTime.parse(null as String)` TypeError used to take
//    down the entire list instead of degrading the one bad item. The
//    fallback is deterministic (never `DateTime.now()`) and sorts to the
//    bottom of any newest-first list, so a broken row is conspicuous
//    rather than plausibly recent.
//
//  * An OPTIONAL timestamp — `reviewed_at`, `completed_at`, `deleted_at`,
//    `updated_at`, a submission's `expires_at` — becomes null via
//    [coerceNullableTimestamp]. Never `DateTime.now()`: fabricating "now"
//    for a missing `reviewed_at` made an un-reviewed submission look as
//    though it had just been decided.

/// The Unix epoch, in UTC. The single fallback for a required timestamp
/// the wire failed to provide.
final DateTime epochTimestamp = DateTime.utc(1970);

/// Coerces a required timestamp, degrading to [epochTimestamp] rather than
/// throwing. See the timestamp rule above.
DateTime coerceTimestamp(Object? value) =>
    coerceNullableTimestamp(value) ?? epochTimestamp;

/// Coerces an optional timestamp: null / absent / unparseable all become
/// null. See the timestamp rule above.
DateTime? coerceNullableTimestamp(Object? value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value.trim());
  return null;
}

// ─── Integers ────────────────────────────────────────────────────────────

/// Coerces a JSON number to an int, falling back to [defaultValue].
///
/// Accepts a real `int`, any other `num` (truncated toward zero), and a
/// numeric string — PostgREST serialises `bigint` and `numeric` columns as
/// JSON strings, so `'250'` has to parse. A DECIMAL string such as `'99.9'`
/// truncates to `99` exactly like the num `99.9`: `int.tryParse` rejects it
/// outright, which used to turn a `numeric` xp_reward into a silent `0`.
int coerceInt(Object? value, {int defaultValue = 0}) =>
    _tryCoerceInt(value) ?? defaultValue;

/// Same coercion as [coerceInt] but preserves the null/absent distinction:
/// "no value" has to stay distinguishable from `0` (a collab member who
/// never submitted vs. one who submitted instantly).
int? coerceNullableInt(Object? value) => _tryCoerceInt(value);

int? _tryCoerceInt(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.isFinite ? value.toInt() : null;
  if (value is bool) return null;
  final text = value.toString().trim();
  if (text.isEmpty) return null;
  final asInt = int.tryParse(text);
  if (asInt != null) return asInt;
  final asNum = num.tryParse(text);
  if (asNum != null && asNum.isFinite) return asNum.toInt();
  return null;
}

/// Coerces a JSON number to a double, falling back to [defaultValue].
/// PostgREST sends `numeric` (e.g. `hot_score`) as text, so a numeric
/// string has to parse here too.
double coerceDouble(Object? value, {double defaultValue = 0.0}) {
  if (value == null) return defaultValue;
  if (value is double) return value;
  if (value is num) return value.toDouble();
  if (value is bool) return defaultValue;
  return double.tryParse(value.toString().trim()) ?? defaultValue;
}

/// Like [coerceDouble], but keeps "absent" distinct from a real zero.
///
/// Confidence is the case that matters: a verification that was never scored
/// and one the model was 0% sure of are different facts, and a default of
/// 0.0 would print "0% confident" for a decision nobody measured.
double? coerceNullableDouble(Object? value) {
  if (value == null) return null;
  if (value is double) return value;
  if (value is num) return value.toDouble();
  if (value is bool) return null;
  final text = value.toString().trim();
  if (text.isEmpty) return null;
  return double.tryParse(text);
}

// ─── Booleans ────────────────────────────────────────────────────────────

/// Coerces a JSON boolean.
///
///  * a real `bool` is returned as-is;
///  * the strings `'true'` / `'false'` (trimmed, case-insensitive) coerce —
///    a JSONB round-trip or a widened RPC signature can stringify a boolean,
///    and the old `json[...] != false` / `json[...] == true` idioms read
///    `'false'` as visible and `'true'` as not-appealed;
///  * null or absent returns [ifMissing], which should be the column's DB
///    default: absence means "this select did not ask for the column", so it
///    carries no signal about the row and must not be read as one;
///  * anything else returns [ifUnrecognised] (defaulting to [ifMissing]).
///    The row DID carry a value we failed to understand, so this is where a
///    safety-critical flag has to fail CLOSED.
bool coerceBool(
  Object? value, {
  required bool ifMissing,
  bool? ifUnrecognised,
}) {
  if (value is bool) return value;
  if (value == null) return ifMissing;
  if (value is String) {
    final text = value.trim().toLowerCase();
    if (text == 'true') return true;
    if (text == 'false') return false;
  }
  return ifUnrecognised ?? ifMissing;
}

// ─── PostgREST embeds ────────────────────────────────────────────────────

/// Normalises an embedded (joined) row.
///
/// PostgREST returns an embed as an object for a to-one relationship and as
/// an array when it cannot prove the relationship is to-one, and which one
/// you get depends on the FK hint in the select. Every model that reads a
/// join has to tolerate both shapes: `SubmissionModel` did, while
/// `NotificationModel` and `CommentModel` hard-cast to `Map` and threw on
/// the array form.
Map<String, dynamic>? coerceEmbed(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return value.cast<String, dynamic>();
  if (value is List) {
    for (final element in value) {
      if (element is Map<String, dynamic>) return element;
      if (element is Map) return element.cast<String, dynamic>();
    }
  }
  return null;
}

// ─── Quest duration ─────────────────────────────────────────────────────

/// Lower bound of the `quests_duration_hours_range` DB CHECK
/// (`check (duration_hours between 1 and 168)`, migration 0026).
const int minQuestDurationHours = 1;

/// Upper bound of that same DB CHECK — 168 hours, i.e. 7 days.
const int maxQuestDurationHours = 168;

/// The `quests.duration_hours` column default (migration 0026).
const int defaultQuestDurationHours = 4;

/// Clamps `duration_hours` into the range the database already enforces.
///
/// Mirrors the `quests_duration_hours_range` CHECK
/// (`duration_hours between 1 and 168`) client-side so the countdown timer
/// can never be handed a value the DB would have rejected. Applied by every
/// model that carries a duration; `QuestModel` used to apply only the floor
/// and the QOTD / collab-preview models applied neither.
///
/// Below the floor (including the `0` a missing int coerces to) is
/// indistinguishable from "unset", so it takes [defaultValue]. Above the
/// ceiling is a real but out-of-range intent, so it clamps to
/// [maxQuestDurationHours] rather than collapsing to the default.
int normalizeQuestDurationHours(
  Object? value, {
  int defaultValue = defaultQuestDurationHours,
}) {
  final hours = coerceInt(value, defaultValue: defaultValue);
  if (hours < minQuestDurationHours) return defaultValue;
  if (hours > maxQuestDurationHours) return maxQuestDurationHours;
  return hours;
}

// ─── Media URL payloads ─────────────────────────────────────────────────

/// Decodes the `media_url` column into the list of URLs it carries.
///
/// The column holds either a single URL or a JSON-encoded array (written
/// when several files are uploaded for one submission). A blank column
/// yields `[]`, never `['']`: the three copies of this getter disagreed,
/// and the two that returned `['']` made a UI guarding on
/// `mediaUrls.isEmpty` render a blank image for a submission with no media.
/// A malformed array falls back to the raw value so a bad row still shows
/// something instead of vanishing.
List<String> decodeMediaUrls(String? raw) {
  if (raw == null) return const [];
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return const [];
  if (trimmed.startsWith('[')) {
    try {
      return List<String>.from(jsonDecode(trimmed) as List);
    } catch (_) {
      // Not a valid JSON string array — fall through to the raw value.
    }
  }
  return [raw];
}

const Set<String> _videoExtensions = {
  'mp4',
  'mov',
  'm4v',
  'webm',
  'avi',
  'mkv',
  '3gp',
  'mpeg',
  'mpg',
};

const Set<String> _imageExtensions = {
  'jpg',
  'jpeg',
  'png',
  'gif',
  'webp',
  'heic',
  'heif',
  'bmp',
  'avif',
  'tiff',
};

/// Derives `'image' | 'video' | 'mixed'` from a list of media URLs, or null
/// when the URLs cannot all be classified with confidence (an
/// extension-less storage key, an unknown container) — in which case the
/// caller should keep the `media_type` the row actually stored.
String? deriveMediaTypeFromUrls(List<String> urls) {
  if (urls.isEmpty) return null;
  var hasImage = false;
  var hasVideo = false;
  for (final url in urls) {
    final extension = _extensionOf(url);
    if (_videoExtensions.contains(extension)) {
      hasVideo = true;
    } else if (_imageExtensions.contains(extension)) {
      hasImage = true;
    } else {
      return null;
    }
  }
  if (hasImage && hasVideo) return 'mixed';
  return hasVideo ? 'video' : 'image';
}

String? _extensionOf(String url) {
  // Strip a query string / fragment first: signed storage URLs carry a
  // token after `?` that would otherwise swallow the extension.
  var path = url.trim();
  for (final separator in ['#', '?']) {
    final index = path.indexOf(separator);
    if (index != -1) path = path.substring(0, index);
  }
  final slash = path.lastIndexOf('/');
  final name = slash == -1 ? path : path.substring(slash + 1);
  final dot = name.lastIndexOf('.');
  if (dot <= 0 || dot == name.length - 1) return null;
  return name.substring(dot + 1).toLowerCase();
}

// ─── Domain defaults ────────────────────────────────────────────────────

/// The level a user is on when the wire value is missing, null or garbage.
///
/// Levels are 1-based everywhere in the product (`level_for_xp` returns 1
/// for 0 XP, and the profile UI divides by the level when drawing the
/// XP-to-next-level bar). `ProfileModel` defaulted to 1 while
/// `LeaderboardUserModel` defaulted to 0, so the same NULL-level user
/// rendered "LVL 1" on their profile and "LVL 0" on the leaderboard.
const int defaultLevel = 1;
