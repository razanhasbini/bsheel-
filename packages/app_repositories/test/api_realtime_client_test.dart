import 'package:app_repositories/app_repositories.dart';
import 'package:test/test.dart';

void main() {
  test('derives the Socket.IO namespace from direct and proxied API URLs', () {
    expect(
      realtimeEndpointFromApi(
        Uri.parse('https://api.example.test/api/v1/'),
      ).toString(),
      'https://api.example.test/realtime',
    );
    expect(
      realtimeEndpointFromApi(
        Uri.parse('https://example.test/bsheel/api/v1'),
      ).toString(),
      'https://example.test/bsheel/realtime',
    );
  });

  test('parses a valid domain event into an immutable typed boundary', () {
    final event = RealtimeDomainEvent.tryParse({
      'type': 'notification.created',
      'aggregateType': 'notification',
      'aggregateId': 'notification-1',
      'data': {'notificationId': 'notification-1', 'userId': 'user-1'},
      'occurredAt': '2026-09-07T11:00:00.000Z',
    });

    expect(event?.type, 'notification.created');
    expect(event?.data['userId'], 'user-1');
    expect(event?.occurredAt.isUtc, isTrue);
  });

  test('drops malformed or incomplete realtime payloads', () {
    expect(RealtimeDomainEvent.tryParse(null), isNull);
    expect(
      RealtimeDomainEvent.tryParse({'type': 'submission.created'}),
      isNull,
    );
    expect(
      RealtimeDomainEvent.tryParse({
        'type': 'submission.created',
        'aggregateType': 'submission',
        'aggregateId': 'submission-1',
        'data': 'not-an-object',
        'occurredAt': 'not-a-date',
      }),
      isNull,
    );
  });

  test('fails closed when connecting without a persisted session', () async {
    final client = ApiClient(
      baseUrl: Uri.parse('https://api.example.test/api/v1/'),
      tokenStore: InMemoryApiTokenStore(),
    );
    final realtime = ApiRealtimeClient(client);

    await expectLater(
      realtime.connect(),
      throwsA(
        isA<RealtimeException>()
            .having((error) => error.code, 'code', 'NO_SESSION'),
      ),
    );
    expect(
      realtime.status,
      RealtimeConnectionStatus.authenticationRequired,
    );
    realtime.dispose();
    client.close();
  });
}
