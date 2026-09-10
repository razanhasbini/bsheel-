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

  test('parses the frame the server actually sends', () {
    // This is a verbatim capture from the deployed gateway. The previous
    // version of this test invented `aggregateType`, `aggregateId` and
    // `occurredAt`, which the server had never sent — so it passed while
    // every real event was being discarded. Assert the real shape.
    final event = RealtimeDomainEvent.tryParse({
      'messageId': 'a0a21c6c-0000-4000-8000-000000000001',
      'type': 'notification.created',
      'data': {'notificationId': 'notification-1', 'userId': 'user-1'},
      'aggregateType': 'notification',
      'aggregateId': 'notification-1',
      'occurredAt': '2026-09-07T11:00:00.000Z',
    });

    expect(event, isNotNull);
    expect(event?.type, 'notification.created');
    expect(event?.data['userId'], 'user-1');
    expect(event?.aggregateType, 'notification');
    expect(event?.occurredAt.isUtc, isTrue);
  });

  test('still parses when only type and data are present', () {
    // The two fields every consumer reads. A payload missing the aggregate
    // metadata must degrade those fields, not drop the event — that failure
    // mode silenced the whole feature once already.
    final event = RealtimeDomainEvent.tryParse({
      'messageId': 'a0a21c6c-0000-4000-8000-000000000002',
      'type': 'submission.approved',
      'data': {'submissionId': 'submission-1', 'userId': 'user-1'},
    });

    expect(event, isNotNull);
    expect(event?.type, 'submission.approved');
    expect(event?.data['submissionId'], 'submission-1');
    expect(event?.aggregateType, 'submission', reason: 'derived from the type');
    expect(event?.occurredAt.isUtc, isTrue);
  });

  test('drops only what it cannot use: no type, or data that is not a map', () {
    expect(RealtimeDomainEvent.tryParse(null), isNull);
    expect(RealtimeDomainEvent.tryParse('a string'), isNull);
    // No data.
    expect(
      RealtimeDomainEvent.tryParse({'type': 'submission.created'}),
      isNull,
    );
    // data present but not an object.
    expect(
      RealtimeDomainEvent.tryParse({
        'type': 'submission.created',
        'data': 'not-an-object',
      }),
      isNull,
    );
    // No type.
    expect(
      RealtimeDomainEvent.tryParse({
        'data': {'submissionId': 's1'}
      }),
      isNull,
    );
    // An unparseable occurredAt is tolerated, not fatal.
    final tolerated = RealtimeDomainEvent.tryParse({
      'type': 'submission.created',
      'data': {'submissionId': 's1'},
      'occurredAt': 'not-a-date',
    });
    expect(tolerated, isNotNull);
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
