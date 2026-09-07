import 'dart:convert';
import 'package:supabase_contracts/supabase_contracts.dart';

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
    this.visibility = 'visible',
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
      status:
          (json[SubmissionColumns.status] as String?) ?? SubmissionStatus.pending,
      reviewedBy: json[SubmissionColumns.reviewedBy] as String?,
      reviewNote: json[SubmissionColumns.reviewNote] as String?,
      submittedAt: _toDateTime(
        json[SubmissionColumns.submittedAt],
      ),
      reviewedAt: _toNullableDateTime(
        json[SubmissionColumns.reviewedAt],
      ),
      appealNote: json[SubmissionColumns.appealNote] as String?,
      appealed: json[SubmissionColumns.appealed] == true,
      showInFeed: json[SubmissionColumns.showInFeed] != false,
      visibility: (json[SubmissionColumns.visibility] as String?) ?? SubmissionVisibility.visible,
      deletedAt: _toNullableDateTime(json[SubmissionColumns.deletedAt]),
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
    final uq = json[Tables.userQuests] ?? json['user_quests'];
    if (uq is Map<String, dynamic>) {
      final q = uq[Tables.quests] ?? uq['quests'];
      if (q is Map<String, dynamic>) {
        return q[QuestColumns.title] as String?;
      }
      if (q is List && q.isNotEmpty && q.first is Map) {
        return (q.first as Map)[QuestColumns.title] as String?;
      }
    }
    return null;
  }

  static String? _readJoinedAuthorField(
    Map<String, dynamic> json,
    String field,
  ) {
    final p = json[Tables.profiles] ?? json['profiles'];
    if (p is Map<String, dynamic>) {
      return p[field] as String?;
    }
    if (p is List && p.isNotEmpty && p.first is Map) {
      return (p.first as Map)[field] as String?;
    }
    return null;
  }

  /// Returns all media URLs. Handles both a single URL string and a
  /// JSON-encoded array (used when multiple files are uploaded).
  List<String> get mediaUrls {
    final trimmed = mediaUrl.trim();
    if (trimmed.startsWith('[')) {
      try {
        return List<String>.from(jsonDecode(trimmed) as List);
      } catch (_) {}
    }
    return [mediaUrl];
  }

  /// Returns the effective media type: 'image', 'video', or 'mixed'.
  String get effectiveMediaType => mediaType;

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
    };
  }

  static DateTime _toDateTime(dynamic value) {
    if (value is DateTime) return value;
    return DateTime.parse(value as String);
  }

  static DateTime? _toNullableDateTime(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    return DateTime.parse(value as String);
  }
}
