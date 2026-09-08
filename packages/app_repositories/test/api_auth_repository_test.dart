import 'dart:convert';

import 'package:app_repositories/app_repositories.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

String jwt(Map<String, Object?> payload) {
  final header = base64Url
      .encode(utf8.encode(jsonEncode({'alg': 'HS256'})))
      .replaceAll('=', '');
  final body =
      base64Url.encode(utf8.encode(jsonEncode(payload))).replaceAll('=', '');
  return '$header.$body.fixture-signature';
}

http.Response success(Object? data, [int status = 200]) => http.Response(
      jsonEncode({
        'success': true,
        'data': data,
        'meta': {'requestId': 'auth-test'},
      }),
      status,
      headers: {'content-type': 'application/json'},
    );

void main() {
  test(
      'logs in, persists the Nest token pair, and emits the compatible auth view',
      () async {
    final store = InMemoryApiTokenStore();
    final accessToken = jwt({
      'sub': '018d7df0-e97b-7ae1-bae2-4423f4b05b85',
      'email': 'user@example.test',
      'role': 'user',
      'iat': 1700000000,
      'exp': 2000000000,
    });
    final client = ApiClient(
      baseUrl: Uri.parse('https://api.example.test/api/v1/'),
      tokenStore: store,
      httpClient: MockClient((request) async {
        expect(request.url.path, '/api/v1/auth/login');
        expect(jsonDecode(request.body), {
          'email': 'user@example.test',
          'password': 'Strong-Pass-123!',
        });
        return success({
          'accessToken': accessToken,
          'refreshToken': 'refresh-token',
          'expiresIn': 900,
        });
      }),
    );
    final repository = ApiAuthRepository(client, store);
    final event = repository.authStateChanges.first;
    final response = await repository.signInWithEmail(
      ' USER@example.test ',
      'Strong-Pass-123!',
    );

    expect(response.user?.id, '018d7df0-e97b-7ae1-bae2-4423f4b05b85');
    expect(response.user?.email, 'user@example.test');
    expect(response.session?.accessToken, accessToken);
    expect((await store.read())?.refreshToken, 'refresh-token');
    expect((await event).event, AuthChangeEvent.signedIn);
  });

  test('preserves confirmation-required signup as a sessionless response',
      () async {
    final store = InMemoryApiTokenStore();
    final repository = ApiAuthRepository(
      ApiClient(
        baseUrl: Uri.parse('https://api.example.test/api/v1/'),
        tokenStore: store,
        httpClient: MockClient((request) async {
          expect(jsonDecode(request.body)['ageVerified'], isTrue);
          return success({'confirmationRequired': true}, 201);
        }),
      ),
      store,
    );
    final response = await repository.signUpWithEmail(
      'new@example.test',
      'Strong-Pass-123!',
      data: {
        'username': 'new_user',
        'display_name': 'New User',
        'age_verified': true,
      },
    );
    expect(response.session, isNull);
    expect(response.user, isNull);
    expect(await store.read(), isNull);
  });

  test('completes password recovery with the one-time Nest action token',
      () async {
    final store = InMemoryApiTokenStore();
    final repository = ApiAuthRepository(
      ApiClient(
        baseUrl: Uri.parse('https://api.example.test/api/v1/'),
        tokenStore: store,
        httpClient: MockClient((request) async {
          expect(request.url.path, '/api/v1/auth/password-recovery/complete');
          expect(request.headers['authorization'], isNull);
          expect(jsonDecode(request.body), {
            'token': 'recovery_token_fixture_12345678901234567890',
            'newPassword': 'Replacement-Pass-481!',
          });
          return success(null, 204);
        }),
      ),
      store,
    );

    await repository.completePasswordRecovery(
      'recovery_token_fixture_12345678901234567890',
      'Replacement-Pass-481!',
    );
    expect(await store.read(), isNull);
  });

  test('completes email confirmation without an authenticated session',
      () async {
    final store = InMemoryApiTokenStore();
    final repository = ApiAuthRepository(
      ApiClient(
        baseUrl: Uri.parse('https://api.example.test/api/v1/'),
        tokenStore: store,
        httpClient: MockClient((request) async {
          expect(request.url.path, '/api/v1/auth/email-confirmation/complete');
          expect(request.headers['authorization'], isNull);
          expect(jsonDecode(request.body), {
            'token': 'confirmation_token_fixture_1234567890123456',
          });
          return success(null, 204);
        }),
      ),
      store,
    );

    await repository.completeEmailConfirmation(
      'confirmation_token_fixture_1234567890123456',
    );
    expect(await store.read(), isNull);
  });
}
