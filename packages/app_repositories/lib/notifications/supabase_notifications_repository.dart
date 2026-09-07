import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:app_models/app_models.dart';
import 'package:supabase_contracts/supabase_contracts.dart';
import 'notifications_repository.dart';

class SupabaseNotificationsRepository implements NotificationsRepository {
  final SupabaseClient client;
  SupabaseNotificationsRepository(this.client);

  @override
  Future<List<NotificationModel>> getNotifications(String userId) async {
    final data = await client
        .from(Tables.notifications)
        .select(
          '*, actor_profile:profiles!notifications_actor_id_fkey(username, avatar_url)',
        )
        .eq(NotificationColumns.userId, userId)
        .order(NotificationColumns.createdAt, ascending: false)
        .limit(50) as List<dynamic>;
    return data
        .map(
          (row) =>
              NotificationModel.fromJson(row as Map<String, dynamic>),
        )
        .toList();
  }

  @override
  Future<int> getUnreadCount(String userId) async {
    final data = await client
        .from(Tables.notifications)
        .select()
        .eq(NotificationColumns.userId, userId)
        .eq(NotificationColumns.isRead, false)
        .count();
    return data.count;
  }

  @override
  Future<void> markAsRead(String notificationId) async {
    await client
        .from(Tables.notifications)
        .update({NotificationColumns.isRead: true})
        .eq(NotificationColumns.id, notificationId);
  }

  @override
  Future<void> markAllAsRead(String userId) async {
    await client
        .from(Tables.notifications)
        .update({NotificationColumns.isRead: true})
        .eq(NotificationColumns.userId, userId)
        .eq(NotificationColumns.isRead, false);
  }
}
