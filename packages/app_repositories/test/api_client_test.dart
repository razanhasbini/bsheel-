import 'dart:convert';

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
