import 'package:app_models/app_models.dart';

import '../api/api_client.dart';
import '../media/api_media_signer.dart';
import 'notifications_repository.dart';

class ApiNotificationsRepository implements NotificationsRepository {
  ApiNotificationsRepository(this._client) : _media = ApiMediaSigner(_client);

  final ApiClient _client;
  final ApiMediaSigner _media;

  @override
  Future<List<NotificationModel>> getNotifications(String userId) async {
    final page = apiObject(await _client.get('notifications', query: {
      'limit': 50,
    },),);
    final rows = apiObjectList(page['items']);
    final avatarValues = rows.map((row) {
      final actor = row['actor_profile'];
      return actor is Map ? actor['avatar_url']?.toString() ?? '' : '';
    });
    final signed = await _media.signMany(avatarValues);
    return rows.map((row) {
      final actor = row['actor_profile'];
      if (actor is! Map) return NotificationModel.fromJson(row);
      final actorMap = Map<String, dynamic>.from(actor);
      final avatar = actorMap['avatar_url']?.toString();
      return NotificationModel.fromJson({
        ...row,
        'actor_profile': {
          ...actorMap,
          'avatar_url': avatar == null ? null : signed[avatar] ?? avatar,
        },
      });
    }).toList(growable: false);
  }

  @override
  Future<int> getUnreadCount(String userId) async {
    final data = apiObject(await _client.get('notifications/unread-count'));
    return (data['count'] as num?)?.toInt() ?? 0;
  }

  @override
  Future<void> markAsRead(String notificationId) async {
    await _client.patch('notifications/$notificationId/read');
  }

  @override
  Future<void> markAllAsRead(String userId) async {
    await _client.patch('notifications/read-all');
  }
}
