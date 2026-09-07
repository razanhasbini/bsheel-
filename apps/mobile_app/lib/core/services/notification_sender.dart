import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:supabase_contracts/supabase_contracts.dart';
import '../backend/backend_config.dart';

/// Sends an in-app notification to a specific user via the server-side RPC.
/// FCM token lookup and push delivery happen server-side — no client reads
/// from private.profile_tokens.
Future<void> sendNotificationToUser({
  required String targetUserId,
  required String title,
  required String body,
  required String type,
  String? referenceId,
}) async {
  // Nest follow/comment commands create their side-effect notifications in the
  // same transaction/outbox flow. Re-sending here would duplicate them.
  if (BackendConfig.usesNest) return;
  final client = Supabase.instance.client;

  // Don't notify yourself
  final currentUser = client.auth.currentUser;
  if (currentUser?.id == targetUserId) return;

  try {
    await client.rpc(
      RpcNames.sendNotification,
      params: {
        'p_target_user_id': targetUserId,
        'p_type': type,
        'p_title': title,
        'p_body': body,
        if (referenceId != null)
          'p_data': {'reference_id': referenceId}
        else
          'p_data': null,
      },
    );
  } catch (e) {
    if (kDebugMode) {
      debugPrint('[Notification] RPC send_notification failed: $e');
    }
  }
}
