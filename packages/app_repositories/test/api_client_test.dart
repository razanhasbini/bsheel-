import 'dart:convert';
import 'dart:io';

import 'package:app_repositories/app_repositories.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

http.Response envelope(Object? data, {int status = 200}) => http.Response(
      jsonEncode({
        'success': true,
        'data': data,
        'meta': {
          'requestId': 'test-request',
          'timestamp': '2026-01-01T00:00:00Z',
        },
      }),
      status,
      headers: {'content-type': 'application/json'},
    );

void main() {
  sessionExpiryTests();

  test('unwraps the response envelope and attaches the access token', () async {
    final tokens = InMemoryApiTokenStore();
    await tokens.write(
      const ApiTokenPair(
        accessToken: 'access-one',
        refreshToken: 'refresh-one',
        expiresIn: 900,
      ),
    );
    final client = ApiClient(
      baseUrl: Uri.parse('https://api.example.test/api/v1'),
      tokenStore: tokens,
      httpClient: MockClient((request) async {
        expect(
          request.url.toString(),
          'https://api.example.test/api/v1/profiles/me',
        );
        expect(request.headers['authorization'], 'Bearer access-one');
        return envelope({'id': 'user-one'});
      }),
    );

    expect(apiObject(await client.get('profiles/me'))['id'], 'user-one');
  });

  test('maps the stable error envelope', () async {
    final client = ApiClient(
      baseUrl: Uri.parse('https://api.example.test/api/v1/'),
      tokenStore: InMemoryApiTokenStore(),
      httpClient: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'success': false,
            'error': {
              'code': 'QUEST_NOT_FOUND',
              'message': 'Quest not found',
              'details': {'field': 'questId'},
            },
            'meta': {'requestId': 'request-42'},
          }),
          404,
        ),
      ),
    );

    await expectLater(
      client.get('quests/missing'),
      throwsA(
        isA<ApiException>()
            .having((error) => error.statusCode, 'statusCode', 404)
            .having((error) => error.code, 'code', 'QUEST_NOT_FOUND')
            .having((error) => error.requestId, 'requestId', 'request-42'),
      ),
    );
  });

  test('rotates a refresh token once and retries the original request',
      () async {
    final tokens = InMemoryApiTokenStore();
    await tokens.write(
      const ApiTokenPair(
        accessToken: 'expired-access',
        refreshToken: 'refresh-one',
        expiresIn: 900,
      ),
    );
    var protectedCalls = 0;
    var refreshCalls = 0;
    final client = ApiClient(
      baseUrl: Uri.parse('https://api.example.test/api/v1/'),
      tokenStore: tokens,
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/auth/refresh')) {
          refreshCalls++;
          expect(jsonDecode(request.body)['refreshToken'], 'refresh-one');
          return envelope({
            'accessToken': 'fresh-access',
            'refreshToken': 'refresh-two',
            'expiresIn': 900,
          });
        }
        protectedCalls++;
        if (request.headers['authorization'] == 'Bearer expired-access') {
          return http.Response(
            jsonEncode({
              'success': false,
              'error': {'code': 'UNAUTHORIZED', 'message': 'Expired'},
            }),
            401,
          );
        }
        expect(request.headers['authorization'], 'Bearer fresh-access');
        return envelope({'ok': true});
      }),
    );

    expect(apiObject(await client.get('profiles/me'))['ok'], isTrue);
    expect(refreshCalls, 1);
    expect(protectedCalls, 2);
    expect((await tokens.read())?.refreshToken, 'refresh-two');
  });
}

http.Response failure(int status, String code) => http.Response(
      jsonEncode({
        'success': false,
        'error': {'code': code, 'message': code},
        'meta': {
          'requestId': 'test-request',
          'timestamp': '2026-01-01T00:00:00Z',
        },
      }),
      status,
      headers: {'content-type': 'application/json'},
    );

/// A session that cannot be refreshed has to be announced, not merely
/// returned as `false`.
///
/// The bug these pin: a refused refresh token left the app holding a dead
/// access token with nothing told to the router. Every read 401ed, each
/// screen fell back to whatever it had cached, and a quest approved minutes
/// earlier in the admin panel still read "pending" in the app no matter how
/// many times it was refreshed — the app was not failing to see the new
/// state, it was failing to ask for it.
void sessionExpiryTests() {
  Future<({bool expired, bool cleared})> refreshOutcome({
    required http.Response refreshResponse,
    bool throwNetworkError = false,
  }) async {
    final tokens = InMemoryApiTokenStore();
    await tokens.write(
      const ApiTokenPair(
        accessToken: 'dead',
        refreshToken: 'dead-refresh',
        expiresIn: 900,
      ),
    );
    var expired = false;
    final client = ApiClient(
      baseUrl: Uri.parse('https://api.example.test/api/v1'),
      tokenStore: tokens,
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/auth/refresh')) {
          if (throwNetworkError) throw const SocketException('offline');
          return refreshResponse;
        }
        return failure(401, 'UNAUTHORIZED');
      }),
    );
    client.onSessionExpired = () => expired = true;
    try {
      await client.get('quests/active');
    } catch (_) {
      // The read still fails; what matters is what happened to the session.
    }
    return (expired: expired, cleared: await tokens.read() == null);
  }

  test('a refused refresh token ends the session and says so', () async {
    final result = await refreshOutcome(
      refreshResponse: failure(401, 'INVALID_REFRESH_TOKEN'),
    );
    expect(result.expired, isTrue, reason: 'the router must be told');
    expect(result.cleared, isTrue, reason: 'a dead token must not be kept');
  });

  test('a 403 on refresh ends the session too', () async {
    final result = await refreshOutcome(
      refreshResponse: failure(403, 'ACCOUNT_RESTRICTED'),
    );
    expect(result.expired, isTrue);
    expect(result.cleared, isTrue);
  });

  test('a server fault does NOT sign the user out', () async {
    // The other half of the rule. Clearing on every failure logs people out
    // over a bad gateway and loses their place for no reason.
    final result = await refreshOutcome(
      refreshResponse: failure(500, 'INTERNAL'),
    );
    expect(result.expired, isFalse,
        reason: 'a 500 is the server, not the session');
    expect(result.cleared, isFalse);
  });

  test('being offline does NOT sign the user out', () async {
    final result = await refreshOutcome(
      refreshResponse: failure(200, 'unused'),
      throwNetworkError: true,
    );
    expect(result.expired, isFalse);
    expect(result.cleared, isFalse);
  });

  test('a 2xx that is not a token pair ends the session', () async {
    // A broken contract, not a transient fault: retrying it forever leaves
    // the app in exactly the stale state this all exists to prevent.
    final result = await refreshOutcome(refreshResponse: envelope('not-a-map'));
    expect(result.expired, isTrue);
    expect(result.cleared, isTrue);
  });
}
