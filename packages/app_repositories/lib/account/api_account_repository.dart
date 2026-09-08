import '../api/api_client.dart';
import '../media/api_media_signer.dart';

typedef BlockedProfile = ({
  String id,
  String username,
  String displayName,
  String? avatarUrl,
  DateTime blockedAt,
});

class ApiAccountRepository {
  ApiAccountRepository(this._client) : _media = ApiMediaSigner(_client);

  final ApiClient _client;
  final ApiMediaSigner _media;

  Future<String> accountStatus() async {
    final data = apiObject(await _client.get('profiles/me/account-status'));
    return data['status'] as String;
  }

  Future<DateTime?> setAnalyticsConsent(bool consented) async {
    final data = apiObject(
      await _client.patch(
        'profiles/me/analytics-consent',
        body: {'consented': consented},
      ),
    );
    final value = data['analytics_consent_at'];
    return value == null ? null : DateTime.parse(value as String);
  }

  Future<DateTime> acceptTerms() async {
    final data = apiObject(await _client.post('profiles/me/accept-terms'));
    return DateTime.parse(data['accepted_terms_at'] as String);
  }

  Future<void> blockUser(
    String userId, {
    String reason = 'Blocked by user',
  }) async {
    await _client.post('social/users/$userId/block', body: {'reason': reason});
  }

  Future<void> unblockUser(String userId) async {
    await _client.delete('social/users/$userId/block');
  }

  Future<List<BlockedProfile>> blockedUsers() async {
    final rows = <Map<String, dynamic>>[];
    const pageSize = 100;
    for (var offset = 0;; offset += pageSize) {
      final page = apiObjectList(
        await _client.get(
          'social/blocked-users',
          query: {'limit': pageSize, 'offset': offset},
        ),
      );
      rows.addAll(page);
      if (page.length < pageSize) break;
    }
    final signed = await _media.signMany(
      rows.map((row) => row['avatar_url']?.toString() ?? ''),
    );
    return rows.map((row) {
      final avatar = row['avatar_url']?.toString();
      return (
        id: row['id'] as String,
        username: row['username']?.toString() ?? '',
        displayName: row['display_name']?.toString() ?? '',
        avatarUrl: avatar == null ? null : signed[avatar] ?? avatar,
        blockedAt: DateTime.parse(row['blocked_at'] as String),
      );
    }).toList(growable: false);
  }

  Future<String> reportContent({
    required String type,
    required String id,
    required String reason,
  }) async {
    final data = apiObject(
      await _client.post(
        'social/reports',
        body: {
          'reportedType': type,
          'reportedId': id,
          'reason': reason,
        },
      ),
    );
    return data['id'] as String;
  }

  Future<String> registerDeviceToken(String token, String platform) async {
    final data = apiObject(
      await _client.post(
        'notifications/devices',
        body: {
          'token': token,
          'platform': platform,
        },
      ),
    );
    return data['id'] as String;
  }

  Future<void> deleteDeviceToken(String token) async {
    await _client.delete('notifications/devices', body: {'token': token});
  }

  Future<Map<String, dynamic>> requestExport() async =>
      apiObject(await _client.post('account/exports'));

  Future<List<Map<String, dynamic>>> exports() async =>
      apiObjectList(await _client.get('account/exports'));

  Future<Map<String, dynamic>> requestDeletion() async => apiObject(
        await _client.post(
          'account/deletion',
          body: const {'confirmation': 'DELETE'},
        ),
      );
}
