import '../api/api_client.dart';
import '../media/api_media_signer.dart';
import 'admin_repository.dart';

class ApiAdminRepository implements AdminRepository {
  ApiAdminRepository(this._client) : _media = ApiMediaSigner(_client);

  final ApiClient _client;
  final ApiMediaSigner _media;

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

  /// Admin user list: profile fields plus email, account status and admin
  /// role in one round-trip. Avatars are private objects, so they come back
  /// as signed URLs ready to render.
  Future<List<Map<String, dynamic>>> users({
    String? query,
    int limit = 50,
    int offset = 0,
  }) async {
    final rows = apiObjectList(
      await _client.get(
        'admin/users',
        query: {
          'q': query,
          'limit': limit,
          'offset': offset,
        },
      ),
    );
    return Future.wait(rows.map((row) async {
      final avatar = row['avatar_url']?.toString();
      if (avatar == null || avatar.isEmpty) return row;
      return {...row, 'avatar_url': await _media.signNullable(avatar)};
    }));
  }

  Future<String> createUser({
    required String email,
    required String password,
    required String username,
    String? displayName,
  }) async {
    final data = apiObject(
      await _client.post(
        'admin/users',
        body: {
          'email': email,
          'password': password,
          'username': username,
          'displayName': displayName,
        },
      ),
    );
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
      _client.post(
        'admin/users/$userId/password',
        body: {
          'newPassword': newPassword,
          'confirm': true,
        },
      );

  Future<void> requestPasswordRecovery(String userId) =>
      _client.post('admin/users/$userId/password-recovery');

  Future<void> setAccountStatus(
    String userId,
    String status,
    String reason,
  ) =>
      _client.patch(
        'admin/users/$userId/status',
        body: {
          'status': status,
          'reason': reason,
        },
      );

  /// Edits the admin-editable profile fields in one audited request.
  /// Throws with code `USERNAME_TAKEN` when the new username is in use.
  Future<void> updateUserProfile(
    String userId, {
    String? username,
    String? displayName,
    String? bio,
    int? xp,
    int? level,
    int? questsCompleted,
    required String reason,
  }) =>
      _client.patch(
        'admin/users/$userId/profile',
        body: {
          if (username != null) 'username': username,
          if (displayName != null) 'displayName': displayName,
          if (bio != null) 'bio': bio,
          if (xp != null) 'xp': xp,
          if (level != null) 'level': level,
          if (questsCompleted != null) 'questsCompleted': questsCompleted,
          'reason': reason,
        },
      );

  Future<void> setXp({
    required String userId,
    required int xp,
    required int level,
    required int questsCompleted,
    required String reason,
  }) =>
      _client.patch(
        'admin/users/$userId/xp',
        body: {
          'xp': xp,
          'level': level,
          'questsCompleted': questsCompleted,
          'reason': reason,
        },
      );

  Future<int> sendNotification({
    String? targetUserId,
    required String title,
    required String body,
    String type = 'announcement',
  }) async {
    // Omitting the target broadcasts to every active user in one
    // transaction, with push fanout handled by the outbox worker.
    final data = apiObject(
      await _client.post(
        'admin/notifications',
        body: {
          if (targetUserId != null) 'targetUserId': targetUserId,
          'title': title,
          'body': body,
          'type': type,
        },
      ),
    );
    return (data['recipients'] as num).toInt();
  }

  /// Recent automatic notifications for the admin activity view.
  /// Announcements are excluded — they have their own page.
  Future<List<Map<String, dynamic>>> notifications({
    int limit = 50,
    int offset = 0,
  }) async =>
      apiObjectList(
        await _client.get(
          'admin/notifications',
          query: {'limit': limit, 'offset': offset},
        ),
      );

  Future<Map<String, dynamic>> stats() async =>
      apiObject(await _client.get('admin/stats'));

  /// XP reconciliation rows: stored profile totals beside what the
  /// approved quest history implies.
  Future<List<Map<String, dynamic>>> xpAudit({
    int limit = 500,
    int offset = 0,
  }) async =>
      apiObjectList(
        await _client.get(
          'admin/xp-audit',
          query: {'limit': limit, 'offset': offset},
        ),
      );

  Future<List<Map<String, dynamic>>> reports({
    String status = 'pending',
    int limit = 50,
    int offset = 0,
  }) async =>
      apiObjectList(
        await _client.get(
          'admin/reports',
          query: {
            'status': status,
            'limit': limit,
            'offset': offset,
          },
        ),
      );

  Future<void> reviewReport(
    String reportId, {
    required String status,
    String? adminNote,
  }) =>
      _client.patch(
        'admin/reports/$reportId',
        body: {
          'status': status,
          if (adminNote != null) 'adminNote': adminNote,
        },
      );

  Future<void> removePost(String submissionId, String reason) => _client.post(
        'admin/submissions/$submissionId/remove',
        body: {
          'reason': reason,
        },
      );

  Future<List<Map<String, dynamic>>> injections({
    int limit = 50,
    int offset = 0,
  }) async =>
      apiObjectList(
        await _client.get(
          'admin/injections',
          query: {
            'limit': limit,
            'offset': offset,
          },
        ),
      );

  Future<Map<String, dynamic>> injectQuest({
    required String targetUserId,
    required String title,
    required String description,
    required String category,
    required String difficulty,
    required int xpReward,
    required int durationHours,
  }) async =>
      apiObject(
        await _client.post(
          'admin/injections',
          body: {
            'targetUserId': targetUserId,
            'title': title,
            'description': description,
            'category': category,
            'difficulty': difficulty,
            'xpReward': xpReward,
            'durationHours': durationHours,
          },
        ),
      );

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
      apiObject(
        await _client.put(
          'admin/config/$key',
          body: {
            'value': value,
            if (description != null) 'description': description,
            'isPublic': isPublic,
          },
        ),
      );

  Future<List<Map<String, dynamic>>> questOfTheDay({
    int limit = 50,
    int offset = 0,
  }) async =>
      apiObjectList(
        await _client.get(
          'admin/qotd',
          query: {
            'limit': limit,
            'offset': offset,
          },
        ),
      );

  Future<Map<String, dynamic>> setQuestOfTheDay({
    required String questId,
    required String displayDate,
    String? ticketNo,
    int bonusXp = 0,
    String? note,
  }) async =>
      apiObject(
        await _client.put(
          'admin/qotd',
          body: {
            'questId': questId,
            'displayDate': displayDate,
            if (ticketNo != null) 'ticketNo': ticketNo,
            'bonusXp': bonusXp,
            if (note != null) 'note': note,
          },
        ),
      );

  Future<void> deleteQuestOfTheDay(String id) =>
      _client.delete('admin/qotd/$id');

  Future<List<Map<String, dynamic>>> waitlist({
    int limit = 50,
    int offset = 0,
  }) async =>
      apiObjectList(
        await _client.get(
          'admin/waitlist',
          query: {
            'limit': limit,
            'offset': offset,
          },
        ),
      );

  Future<List<Map<String, dynamic>>> suggestions({
    String status = 'pending',
    int limit = 50,
    int offset = 0,
  }) async =>
      apiObjectList(
        await _client.get(
          'admin/suggestions',
          query: {
            'status': status,
            'limit': limit,
            'offset': offset,
          },
        ),
      );

  Future<Map<String, dynamic>> reviewSuggestion(
    String id, {
    required String status,
    int xpReward = 50,
    int durationHours = 4,
  }) async =>
      apiObject(
        await _client.patch(
          'admin/suggestions/$id',
          body: {
            'status': status,
            'xpReward': xpReward,
            'durationHours': durationHours,
          },
        ),
      );

  // ── Map destinations ────────────────────────────────────────────
  // `super_admin` only on the server. A moderator's call answers 403,
  // so the console gates the page rather than letting every action fail.

  /// Every map place, newest first, capped at 500 by the server.
  ///
  /// Each row is the `map_places` record joined with its country, so it
  /// also carries `country_name` and `geometry_id`. Unlike the public
  /// `map/places` list this one includes unpublished and `hidden` places
  /// and does **not** carry a `quest_count`.
  Future<List<Map<String, dynamic>>> adminMapPlaces() async =>
      apiObjectList(await _client.get('map/admin/places'));

  /// Creates a place and upserts the country it belongs to in the same
  /// transaction, so a first destination in a new country needs no
  /// separate call. Returns the inserted row.
  ///
  /// The server re-validates every bound: `countryCode` two uppercase
  /// letters, `geometryId` three digits, `name` 1..160, `description`
  /// ≤2000, `city` ≤100, latitude -85..85, longitude -180..180 and
  /// `radiusM` 25..10000.
  Future<Map<String, dynamic>> createMapPlace({
    required String countryCode,
    required String countryName,
    required String geometryId,
    required String name,
    required String category,
    required double latitude,
    required double longitude,
    String description = '',
    String city = '',
    int radiusM = 250,
    bool isPublished = false,
  }) async =>
      apiObject(
        await _client.post(
          'map/admin/places',
          body: {
            'countryCode': countryCode,
            'countryName': countryName,
            'geometryId': geometryId,
            'name': name,
            'description': description,
            'city': city,
            'category': category,
            'latitude': latitude,
            'longitude': longitude,
            'radiusM': radiusM,
            'isPublished': isPublished,
          },
        ),
      );

  /// Points one quest at [placeId].
  ///
  /// A quest has at most one destination, so linking a quest that is
  /// already linked elsewhere moves it. The server refuses a quest that
  /// already has attempts with `QUEST_ALREADY_STARTED` — reassigning a
  /// live quest would retroactively move discovery. There is no unlink
  /// endpoint.
  Future<void> linkQuestToPlace(
    String placeId, {
    required String questId,
    bool requiresVerification = true,
  }) async {
    await _client.post(
      'map/admin/places/$placeId/quests',
      body: {
        'questId': questId,
        'requiresVerification': requiresVerification,
      },
    );
  }
}
