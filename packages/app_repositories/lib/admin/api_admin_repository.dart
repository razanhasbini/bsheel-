import '../api/api_client.dart';
import 'admin_repository.dart';

class ApiAdminRepository implements AdminRepository {
  const ApiAdminRepository(this._client);

  final ApiClient _client;

  @override
  Future<AdminRoleEnum?> getCurrentUserRole() async {
    try {
      final data = apiObject(await _client.get('admin/me'));
      return AdminRoleEnum.fromDbString(data['role']?.toString());
    } on ApiException catch (error) {
      if (error.statusCode == 403 || error.statusCode == 404) return null;
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> users({
    String? query,
    int limit = 50,
    int offset = 0,
  }) async =>
      apiObjectList(await _client.get('admin/users', query: {
        'q': query,
        'limit': limit,
        'offset': offset,
      },),);

  Future<String> createUser({
    required String email,
    required String password,
    required String username,
    String? displayName,
  }) async {
    final data = apiObject(await _client.post('admin/users', body: {
      'email': email,
      'password': password,
      'username': username,
      'displayName': displayName,
    },),);
    return data['userId'] as String;
  }

  Future<void> deleteUser(String userId) =>
      _client.delete('admin/users/$userId');

  Future<void> setRole(String userId, AdminRoleEnum? role) => _client.put(
        'admin/users/$userId/role',
        body: {
          'role': switch (role) {
            AdminRoleEnum.superAdmin => 'super_admin',
            AdminRoleEnum.moderator => 'moderator',
            null => null,
          },
        },
      );

  Future<void> forceResetPassword(String userId, String newPassword) =>
      _client.post('admin/users/$userId/password', body: {
        'newPassword': newPassword,
        'confirm': true,
      },);

  Future<void> requestPasswordRecovery(String userId) =>
      _client.post('admin/users/$userId/password-recovery');

  Future<void> setAccountStatus(
    String userId,
    String status,
    String reason,
  ) =>
      _client.patch('admin/users/$userId/status', body: {
        'status': status,
        'reason': reason,
      },);

  Future<void> setXp({
    required String userId,
    required int xp,
    required int level,
    required int questsCompleted,
    required String reason,
  }) =>
      _client.patch('admin/users/$userId/xp', body: {
        'xp': xp,
        'level': level,
        'questsCompleted': questsCompleted,
        'reason': reason,
      },);

  Future<int> sendNotification({
    String? targetUserId,
    required String title,
    required String body,
    String type = 'announcement',
  }) async {
    final data = apiObject(await _client.post('admin/notifications', body: {
      'targetUserId': targetUserId,
      'title': title,
      'body': body,
      'type': type,
    },),);
    return (data['recipients'] as num).toInt();
  }

  Future<Map<String, dynamic>> stats() async =>
      apiObject(await _client.get('admin/stats'));

  Future<List<Map<String, dynamic>>> reports({
    String status = 'pending',
    int limit = 50,
    int offset = 0,
  }) async =>
      apiObjectList(await _client.get('admin/reports', query: {
        'status': status,
        'limit': limit,
        'offset': offset,
      },),);

  Future<void> reviewReport(
    String reportId, {
    required String status,
    String? adminNote,
  }) =>
      _client.patch('admin/reports/$reportId', body: {
        'status': status,
        if (adminNote != null) 'adminNote': adminNote,
      },);

  Future<void> removePost(String submissionId, String reason) =>
      _client.post('admin/submissions/$submissionId/remove', body: {
        'reason': reason,
      },);

  Future<List<Map<String, dynamic>>> injections({
    int limit = 50,
    int offset = 0,
  }) async =>
      apiObjectList(await _client.get('admin/injections', query: {
        'limit': limit,
        'offset': offset,
      },),);

  Future<Map<String, dynamic>> injectQuest({
    required String targetUserId,
    required String title,
    required String description,
    required String category,
    required String difficulty,
    required int xpReward,
    required int durationHours,
  }) async =>
      apiObject(await _client.post('admin/injections', body: {
        'targetUserId': targetUserId,
        'title': title,
        'description': description,
        'category': category,
        'difficulty': difficulty,
        'xpReward': xpReward,
        'durationHours': durationHours,
      },),);

  Future<void> cancelInjection(String injectionId) =>
      _client.delete('admin/injections/$injectionId');

  Future<List<Map<String, dynamic>>> config() async =>
      apiObjectList(await _client.get('admin/config'));

  Future<Map<String, dynamic>> setConfig(
    String key, {
    required Object? value,
    String? description,
    bool isPublic = false,
  }) async =>
      apiObject(await _client.put('admin/config/$key', body: {
        'value': value,
        if (description != null) 'description': description,
        'isPublic': isPublic,
      },),);

  Future<List<Map<String, dynamic>>> questOfTheDay({
    int limit = 50,
    int offset = 0,
  }) async =>
      apiObjectList(await _client.get('admin/qotd', query: {
        'limit': limit,
        'offset': offset,
      },),);

  Future<Map<String, dynamic>> setQuestOfTheDay({
    required String questId,
    required String displayDate,
    String? ticketNo,
    int bonusXp = 0,
    String? note,
  }) async =>
      apiObject(await _client.put('admin/qotd', body: {
        'questId': questId,
        'displayDate': displayDate,
        if (ticketNo != null) 'ticketNo': ticketNo,
        'bonusXp': bonusXp,
        if (note != null) 'note': note,
      },),);

  Future<void> deleteQuestOfTheDay(String id) =>
      _client.delete('admin/qotd/$id');

  Future<List<Map<String, dynamic>>> waitlist({
    int limit = 50,
    int offset = 0,
  }) async =>
      apiObjectList(await _client.get('admin/waitlist', query: {
        'limit': limit,
        'offset': offset,
      },),);

  Future<List<Map<String, dynamic>>> suggestions({
    String status = 'pending',
    int limit = 50,
    int offset = 0,
  }) async =>
      apiObjectList(await _client.get('admin/suggestions', query: {
        'status': status,
        'limit': limit,
        'offset': offset,
      },),);

  Future<Map<String, dynamic>> reviewSuggestion(
    String id, {
    required String status,
    int xpReward = 50,
    int durationHours = 4,
  }) async =>
      apiObject(await _client.patch('admin/suggestions/$id', body: {
        'status': status,
        'xpReward': xpReward,
        'durationHours': durationHours,
      },),);
}
