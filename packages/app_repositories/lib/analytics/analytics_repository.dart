import '../api/api_client.dart';

/// One exposure event, as the client reports it (#81 §28).
///
/// [clientEventId] must be a fresh UUID per event: the server's idempotency
/// key is `(user, clientEventId)`, so reusing one silently drops the event —
/// and generating it on the client is what makes a retried flush safe.
class AnalyticsEvent {
  const AnalyticsEvent({
    required this.clientEventId,
    required this.eventType,
    required this.questId,
    required this.surface,
    required this.occurredAt,
    this.sourceSubmissionId,
  });

  /// The post this was raised from, when there was one — a BSHEEEL pressed
  /// on a feed card, a quest opened from a post. What lets the server say
  /// "this post led to that completion". Null for events with no post.
  final String? sourceSubmissionId;

  final String clientEventId;

  /// One of `quest_impression`, `quest_detail_view`, `quest_bsheeel`,
  /// `quest_share`. A closed set on the server; an unknown type is a 400 for
  /// the whole batch.
  final String eventType;
  final String questId;

  /// `feed`, `map`, `home`, `search`, `country` or `quest_detail`.
  final String surface;
  final DateTime occurredAt;

  Map<String, dynamic> toJson() => {
        'clientEventId': clientEventId,
        'eventType': eventType,
        'questId': questId,
        'surface': surface,
        'occurredAt': occurredAt.toUtc().toIso8601String(),
        if (sourceSubmissionId != null)
          'sourceSubmissionId': sourceSubmissionId,
      };
}

/// What one of the viewer's own posts led to (server-computed; counts only).
class PostAttribution {
  const PostAttribution({
    required this.detailViews,
    required this.viewers,
    required this.bsheeels,
    required this.shares,
    required this.activations,
    required this.completions,
  });

  factory PostAttribution.fromJson(Map<String, dynamic> json) =>
      PostAttribution(
        detailViews: (json['detailViews'] as num?)?.toInt() ?? 0,
        viewers: (json['viewers'] as num?)?.toInt() ?? 0,
        bsheeels: (json['bsheeels'] as num?)?.toInt() ?? 0,
        shares: (json['shares'] as num?)?.toInt() ?? 0,
        activations: (json['activations'] as num?)?.toInt() ?? 0,
        completions: (json['completions'] as num?)?.toInt() ?? 0,
      );

  final int detailViews;
  final int viewers;
  final int bsheeels;
  final int shares;
  final int activations;
  final int completions;

  bool get isEmpty =>
      viewers == 0 &&
      bsheeels == 0 &&
      shares == 0 &&
      activations == 0 &&
      completions == 0;
}

abstract class AnalyticsRepository {
  /// Reports a batch. Bounded at 200 by the server.
  Future<void> record(List<AnalyticsEvent> events);

  /// What one of the caller's own posts led to. 404 (thrown) for a post
  /// that is not theirs — the server does not confirm other people's posts
  /// have numbers.
  Future<PostAttribution> attributionForPost(String submissionId);
}

class ApiAnalyticsRepository implements AnalyticsRepository {
  ApiAnalyticsRepository(this._client);
  final ApiClient _client;

  @override
  Future<void> record(List<AnalyticsEvent> events) async {
    if (events.isEmpty) return;
    await _client.post('analytics/events', body: {
      'events': events.map((event) => event.toJson()).toList(),
    });
  }

  @override
  Future<PostAttribution> attributionForPost(String submissionId) async =>
      PostAttribution.fromJson(
        apiObject(
            await _client.get('analytics/attribution/posts/$submissionId')),
      );
}
