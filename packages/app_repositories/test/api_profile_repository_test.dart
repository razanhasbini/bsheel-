import 'dart:convert';

import 'package:app_models/app_models.dart';
import 'package:app_repositories/app_repositories.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

/// What `PATCH profiles/me` actually puts on the wire.
///
/// A field can exist on the model, be set by the UI, and never be sent —
/// the request body is written by hand, so nothing in the type system
/// notices. The country is exactly that kind of field: #50's tourism
/// analytics has no other data source, so if it silently stops being sent
/// the feature reports "nobody has shared a country" forever and looks like
/// a server bug.
void main() {
  ProfileModel profile({String? countryCode}) => ProfileModel(
        id: 'u1',
        username: 'player',
        displayName: 'Player',
        createdAt: DateTime.utc(2026, 1, 1),
        countryCode: countryCode,
      );

  Future<Map<String, dynamic>> capturedBody(ProfileModel input) async {
    Map<String, dynamic>? body;
    final repository = ApiProfileRepository(
      ApiClient(
        baseUrl: Uri.parse('https://api.example.test/api/v1/'),
        tokenStore: InMemoryApiTokenStore(),
        httpClient: MockClient((request) async {
          expect(request.url.path, '/api/v1/profiles/me');
          body = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({'success': true, 'data': input.toJson()}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      ),
    );
    await repository.updateProfile(input);
    return body!;
  }

  test('sends the declared country', () async {
    final body = await capturedBody(profile(countryCode: 'LB'));

    expect(body['countryCode'], 'LB');
  });

  // Sent as an explicit null rather than omitted, because the server reads
  // an absent key as "leave alone". Omitting it would make clearing your
  // country impossible — the save would appear to work and change nothing.
  test('sends an explicit null when the country is cleared', () async {
    final body = await capturedBody(profile());

    expect(body.containsKey('countryCode'), isTrue);
    expect(body['countryCode'], isNull);
  });

  test('reads the country back off the response', () async {
    final repository = ApiProfileRepository(
      ApiClient(
        baseUrl: Uri.parse('https://api.example.test/api/v1/'),
        tokenStore: InMemoryApiTokenStore(),
        httpClient: MockClient((request) async => http.Response(
              jsonEncode({
                'success': true,
                'data': profile(countryCode: 'QA').toJson(),
              }),
              200,
              headers: {'content-type': 'application/json'},
            )),
      ),
    );

    final updated = await repository.updateProfile(profile(countryCode: 'QA'));
    expect(updated.countryCode, 'QA');
  });
}
