import 'dart:convert';

import 'package:app_repositories/app_repositories.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  test('reads pre-auth flags and normalizes JSON scalar values', () async {
    final repository = ApiPublicConfigRepository(
      ApiClient(
        baseUrl: Uri.parse('https://api.example.test/api/v1/'),
        tokenStore: InMemoryApiTokenStore(),
        httpClient: MockClient((request) async {
          expect(request.url.path, '/api/v1/config');
          expect(request.headers['authorization'], isNull);
          return http.Response(
            jsonEncode({
              'success': true,
              'data': [
                {'key': 'maintenance_mode', 'value': true},
                {'key': 'maintenance_message', 'value': 'Back soon'},
                {'key': 'update_required_build', 'value': 75},
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      ),
    );

    expect(await repository.getConfig(), {
      'maintenance_mode': 'true',
      'maintenance_message': 'Back soon',
      'update_required_build': '75',
    });
  });
}
