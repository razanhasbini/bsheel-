import 'src/json_coercions.dart';

/// One stop of a journey posted to the feed as a single route (0047).
///
/// Deliberately thin. A stop is an ordinary submission that already exists
/// in its own right — verified on its own evidence, appealable on its own
/// terms — and this carries only what the feed card needs to draw it in
/// sequence. Anything more would be a second copy of a submission, and the
/// two would drift.
class JourneyPostStop {
  const JourneyPostStop({
    required this.submissionId,
    required this.stepOrder,
    required this.mediaUrl,
    required this.mediaType,
    this.caption,
    this.questTitle,
    this.placeName,
    this.submittedAt,
  });

  final String submissionId;
  final int stepOrder;
  final String mediaUrl;
  final String mediaType;
  final String? caption;

  /// What the checkpoint asked for, so a route reads as a story rather than
  /// as three unlabelled photographs.
  final String? questTitle;

  /// Where it was, when the checkpoint had a destination.
  final String? placeName;

  final DateTime? submittedAt;

  /// Every media URL for this stop — a stop can carry several files, the
  /// same as any submission.
  List<String> get mediaUrls => decodeMediaUrls(mediaUrl);

  factory JourneyPostStop.fromJson(Map<String, dynamic> json) =>
      JourneyPostStop(
        submissionId: (json['submission_id'] ?? '').toString(),
        stepOrder: coerceInt(json['step_order']),
        mediaUrl: (json['media_url'] ?? '').toString(),
        mediaType: (json['media_type'] as String?) ?? 'image',
        caption: json['caption'] as String?,
        questTitle: json['quest_title'] as String?,
        placeName: json['place_name'] as String?,
        submittedAt: coerceNullableTimestamp(json['submitted_at']),
      );

  @override
  bool operator ==(Object other) =>
      other is JourneyPostStop &&
      other.submissionId == submissionId &&
      other.stepOrder == stepOrder &&
      other.mediaUrl == mediaUrl;

  @override
  int get hashCode => Object.hash(submissionId, stepOrder, mediaUrl);
}
