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
  });

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
      };
}

abstract class AnalyticsRepository {
  /// Reports a batch. Bounded at 200 by the server.
  Future<void> record(List<AnalyticsEvent> events);
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
}
