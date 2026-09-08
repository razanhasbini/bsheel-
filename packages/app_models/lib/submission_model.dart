import 'package:supabase_contracts/supabase_contracts.dart';

import 'src/json_coercions.dart';

class SubmissionModel {
  final String id;
  final String userQuestId;
  final String userId;
  final String mediaUrl;
  final String mediaType;
  final String? caption;
  final String status;
  final String? reviewedBy;
  final String? reviewNote;
  final DateTime submittedAt;
  final DateTime? reviewedAt;
  final String? appealNote;
  final bool appealed;
  final bool showInFeed;
  final String visibility;
  final DateTime? deletedAt;
  // Optional joined fields — populated only when the row was fetched with
  // a select that pulls in `quests.title` / `profiles.*`. Lets us label a
  // submission tile without a second round-trip.
  final String? questTitle;
  final String? authorUsername;
  final String? authorDisplayName;

  const SubmissionModel({
    required this.id,
    required this.userQuestId,
    required this.userId,
    required this.mediaUrl,
    this.mediaType = MediaType.image,
    this.caption,
    required this.status,
    this.reviewedBy,
    this.reviewNote,
    required this.submittedAt,
    this.reviewedAt,
    this.appealNote,
    this.appealed = false,
    this.showInFeed = true,
    this.visibility = SubmissionVisibility.visible,
    this.deletedAt,
    this.questTitle,
    this.authorUsername,
    this.authorDisplayName,
  });

  factory SubmissionModel.fromJson(Map<String, dynamic> json) {
    return SubmissionModel(
      id: (json[SubmissionColumns.id] ?? '').toString(),
      userQuestId: (json[SubmissionColumns.userQuestId] ?? '').toString(),
      userId: (json[SubmissionColumns.userId] ?? '').toString(),
      mediaUrl: (json[SubmissionColumns.mediaUrl] ?? '').toString(),
      mediaType:
          (json[SubmissionColumns.mediaType] as String?) ?? MediaType.image,
      caption: json[SubmissionColumns.caption] as String?,
      status: (json[SubmissionColumns.status] as String?) ??
          SubmissionStatus.pending,
      reviewedBy: json[SubmissionColumns.reviewedBy] as String?,
      reviewNote: json[SubmissionColumns.reviewNote] as String?,
      submittedAt: coerceTimestamp(json[SubmissionColumns.submittedAt]),
      reviewedAt: coerceNullableTimestamp(json[SubmissionColumns.reviewedAt]),
      appealNote: json[SubmissionColumns.appealNote] as String?,
      // `appealed` is `not null default false` (migration 0048), so an
      // absent column means "this select didn't ask" and reads false. A
      // value we cannot parse fails the other way, towards appealed: an
      // appeal we surface needlessly costs a moderator one glance, whereas
      // one we drop leaves a user with no recourse. This used to be
      // `json[...] == true`, which read the string 'true' as NOT appealed.
      appealed: coerceBool(
        json[SubmissionColumns.appealed],
        ifMissing: false,
        ifUnrecognised: true,
      ),
      // `show_in_feed` is `not null default true` (migration 0049), so an
      // absent column reads visible — defaulting a partial select to hidden
      // would blank the feed. An unrecognisable value fails CLOSED: this is
      // the moderator takedown flag, and showing content that was meant to
      // be hidden is the harmful direction. This used to be
      // `json[...] != false`, which read the string 'false' as visible.
      showInFeed: coerceBool(
        json[SubmissionColumns.showInFeed],
        ifMissing: true,
        ifUnrecognised: false,
      ),
      visibility: (json[SubmissionColumns.visibility] as String?) ??
          SubmissionVisibility.visible,
      deletedAt: coerceNullableTimestamp(json[SubmissionColumns.deletedAt]),
      questTitle: _readJoinedQuestTitle(json),
      authorUsername: _readJoinedAuthorField(json, ProfileColumns.username),
      authorDisplayName:
          _readJoinedAuthorField(json, ProfileColumns.displayName),
    );
  }

  /// Pulls `quests.title` from a Supabase select with the shape
  /// `user_quests:user_quests(quests:quests(title))`. Falls back through
  /// the alternate non-aliased and array-shaped responses.
  static String? _readJoinedQuestTitle(Map<String, dynamic> json) {
    final userQuest =
        coerceEmbed(json[Tables.userQuests] ?? json['user_quests']);
    if (userQuest == null) return null;
    final quest = coerceEmbed(userQuest[Tables.quests] ?? userQuest['quests']);
    return quest?[QuestColumns.title] as String?;
  }

  static String? _readJoinedAuthorField(
    Map<String, dynamic> json,
    String field,
  ) {
    final profile = coerceEmbed(json[Tables.profiles] ?? json['profiles']);
    return profile?[field] as String?;
  }

  /// Returns all media URLs. Handles both a single URL string and a
  /// JSON-encoded array (used when multiple files are uploaded). An empty
  /// `media_url` yields `[]`, not `['']`.
  List<String> get mediaUrls => decodeMediaUrls(mediaUrl);

  /// The effective media type: `'image'`, `'video'` or `'mixed'`.
  ///
  /// Implemented as the doc comment always promised rather than relaxing
  /// the doc to match the old bare pass-through, because 'mixed' is a real
  /// part of the shared contract ([MediaType.mixed]) that the submit page
  /// computes at write time — so a reader that can never report it is the
  /// side that is wrong. Rows written before that logic landed still store
  /// `'image'` for an image+video upload, and this getter recovers them.
  ///
  /// Derivation only overrides the stored value when EVERY URL can be
  /// classified by extension; an extension-less storage key or an unknown
  /// container leaves the stored [mediaType] authoritative rather than
  /// guessing.
  String get effectiveMediaType =>
      deriveMediaTypeFromUrls(mediaUrls) ?? mediaType;

  /// Serialises every column [fromJson] reads.
  ///
  /// The moderation columns (`appealed`, `appeal_note`, `show_in_feed`,
  /// `visibility`, `deleted_at`) used to be read but never written, so a
  /// read-modify-write through `toJson` silently reset a takedown to
  /// visible. The joined `quests.title` / `profiles.*` fields are NOT
  /// emitted: they belong to other tables and would be rejected as unknown
  /// columns on an insert or update of `submissions`.
  Map<String, dynamic> toJson() {
    return {
      SubmissionColumns.id: id,
      SubmissionColumns.userQuestId: userQuestId,
      SubmissionColumns.userId: userId,
      SubmissionColumns.mediaUrl: mediaUrl,
      SubmissionColumns.mediaType: mediaType,
      SubmissionColumns.caption: caption,
      SubmissionColumns.status: status,
      SubmissionColumns.reviewedBy: reviewedBy,
      SubmissionColumns.reviewNote: reviewNote,
      SubmissionColumns.submittedAt: submittedAt.toIso8601String(),
      SubmissionColumns.reviewedAt: reviewedAt?.toIso8601String(),
      SubmissionColumns.appealNote: appealNote,
      SubmissionColumns.appealed: appealed,
      SubmissionColumns.showInFeed: showInFeed,
      SubmissionColumns.visibility: visibility,
      SubmissionColumns.deletedAt: deletedAt?.toIso8601String(),
    };
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SubmissionModel &&
        other.id == id &&
        other.userQuestId == userQuestId &&
        other.userId == userId &&
        other.mediaUrl == mediaUrl &&
        other.mediaType == mediaType &&
        other.caption == caption &&
        other.status == status &&
        other.reviewedBy == reviewedBy &&
        other.reviewNote == reviewNote &&
        other.submittedAt == submittedAt &&
        other.reviewedAt == reviewedAt &&
        other.appealNote == appealNote &&
        other.appealed == appealed &&
        other.showInFeed == showInFeed &&
        other.visibility == visibility &&
        other.deletedAt == deletedAt &&
        other.questTitle == questTitle &&
        other.authorUsername == authorUsername &&
        other.authorDisplayName == authorDisplayName;
  }

  @override
  int get hashCode => Object.hashAll([
        id,
        userQuestId,
        userId,
        mediaUrl,
        mediaType,
        caption,
        status,
        reviewedBy,
        reviewNote,
        submittedAt,
        reviewedAt,
        appealNote,
        appealed,
        showInFeed,
        visibility,
        deletedAt,
        questTitle,
        authorUsername,
        authorDisplayName,
      ]);
}
