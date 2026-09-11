import 'package:app_models/app_models.dart';
import '../api/api_client.dart';
import '../media/api_media_signer.dart';

/// Business / destination accounts (#14) and their analytics (#50).
///
/// Every call here is scoped by the caller's own membership on the server —
/// there is no place or business parameter that widens it. A non-member gets
/// a 404 rather than a 403, so "not found" from these methods means "not
/// yours", and the UI must not treat it as a missing record.
abstract class BusinessRepository {
  /// Businesses the signed-in user belongs to. Empty for almost everyone,
  /// which is the point: the app is identical for everyone else.
  Future<List<BusinessSummary>> mine();

  Future<List<BusinessMember>> members(String businessId);

  /// Owner-only on the server. A manager who could appoint members could
  /// appoint itself an owner.
  Future<void> addMember(String businessId, String userId,
      {BusinessMemberRole role = BusinessMemberRole.manager});
  Future<void> removeMember(String businessId, String userId);

  Future<BusinessAnalyticsSummary> analyticsSummary(String businessId);
  Future<List<BusinessDailyPoint>> daily(String businessId, {int days = 30});
  Future<List<BusinessQuestPerformance>> questPerformance(String businessId);
  Future<List<BusinessPlacePerformance>> placePerformance(String businessId);
  Future<BusinessVisitorOrigins> visitorOrigins(String businessId);

  /// Published proof at the business's places. [cursor] continues a page.
  Future<BusinessProofPage> proof(String businessId,
      {int limit = 20, BusinessProofCursor? cursor});
}

class ApiBusinessRepository implements BusinessRepository {
  ApiBusinessRepository(this._client);
  final ApiClient _client;

  String _analytics(String businessId, String route) =>
      'businesses/$businessId/analytics/$route';

  @override
  Future<List<BusinessSummary>> mine() async =>
      apiObjectList(await _client.get('businesses/me'))
          .map(BusinessSummary.fromJson)
          .toList();

  @override
  Future<List<BusinessMember>> members(String businessId) async =>
      apiObjectList(await _client.get('businesses/$businessId/members'))
          .map(BusinessMember.fromJson)
          .toList();

  @override
  Future<void> addMember(String businessId, String userId,
          {BusinessMemberRole role = BusinessMemberRole.manager}) async =>
      _client.post('businesses/$businessId/members',
          body: {'userId': userId, 'role': role.name});

  @override
  Future<void> removeMember(String businessId, String userId) async =>
      _client.delete('businesses/$businessId/members/$userId');

  @override
  Future<BusinessAnalyticsSummary> analyticsSummary(String businessId) async =>
      BusinessAnalyticsSummary.fromJson(
          apiObject(await _client.get(_analytics(businessId, 'summary'))));

  @override
  Future<List<BusinessDailyPoint>> daily(String businessId,
          {int days = 30}) async =>
      apiObjectList(await _client
              .get(_analytics(businessId, 'daily'), query: {'days': days}))
          .map(BusinessDailyPoint.fromJson)
          .toList();

  @override
  Future<List<BusinessQuestPerformance>> questPerformance(
          String businessId) async =>
      apiObjectList(await _client.get(_analytics(businessId, 'quests')))
          .map(BusinessQuestPerformance.fromJson)
          .toList();

  @override
  Future<List<BusinessPlacePerformance>> placePerformance(
          String businessId) async =>
      apiObjectList(await _client.get(_analytics(businessId, 'places')))
          .map(BusinessPlacePerformance.fromJson)
          .toList();

  @override
  Future<BusinessVisitorOrigins> visitorOrigins(String businessId) async =>
      BusinessVisitorOrigins.fromJson(
          apiObject(await _client.get(_analytics(businessId, 'countries'))));

  /// Signs the media keys before handing rows to the model.
  ///
  /// The API returns object keys, exactly as the feed does; `POST
  /// /media/sign` turns one into a URL an image widget can load. Doing it
  /// here means no screen ever holds an unsigned key and wonders why the
  /// picture is blank.
  @override
  Future<BusinessProofPage> proof(String businessId,
      {int limit = 20, BusinessProofCursor? cursor}) async {
    final data =
        apiObject(await _client.get(_analytics(businessId, 'proof'), query: {
      'limit': limit,
      if (cursor != null) 'beforeSubmittedAt': cursor.beforeSubmittedAt,
      if (cursor != null) 'beforeId': cursor.beforeId,
    }));
    final items = ((data['items'] as List?) ?? const [])
        .cast<Map<String, dynamic>>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
    final keys = items
        .map((row) => row['mediaUrl'] as String? ?? '')
        .where((key) => key.isNotEmpty)
        .toSet()
        .toList();
    if (keys.isNotEmpty) {
      final signed = await ApiMediaSigner(_client).signMany(keys);
      for (final row in items) {
        final key = row['mediaUrl'] as String?;
        if (key != null && key.isNotEmpty) row['mediaUrl'] = signed[key] ?? '';
      }
    }
    return BusinessProofPage.fromJson({...data, 'items': items});
  }
}
