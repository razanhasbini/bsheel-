import { Injectable } from '@nestjs/common';
import { DatabaseService } from '../database/database.service.js';

export interface NotificationDelivery {
  readonly notificationId: string;
  readonly deviceTokenId: string;
  readonly encryptedToken: Buffer;
  readonly title: string;
  readonly body: string;
}

export interface PasswordRecoveryDelivery {
  readonly email: string;
  readonly encryptedToken: Buffer;
}

@Injectable()
export class DomainEventsRepository {
  constructor(private readonly database: DatabaseService) {}

  async wasProcessed(consumer: string, messageId: string): Promise<boolean> {
    const result = await this.database.query(
      'SELECT 1 FROM processed_messages WHERE consumer = $1 AND message_id = $2',
      [consumer, messageId],
    );
    return Boolean(result.rowCount);
  }

  async prepareNotification(notificationId: string, userId: string): Promise<void> {
    await this.database.query(
      `INSERT INTO notification_deliveries (notification_id, device_token_id)
       SELECT n.id, token.id
       FROM notifications n
       JOIN device_tokens token ON token.user_id = n.user_id
       WHERE n.id = $1 AND n.user_id = $2
       ON CONFLICT DO NOTHING`,
      [notificationId, userId],
    );
  }

  async pendingNotificationDeliveries(notificationId: string): Promise<readonly NotificationDelivery[]> {
    const result = await this.database.query<NotificationDelivery>(
      `SELECT delivery.notification_id AS "notificationId",
              delivery.device_token_id AS "deviceTokenId",
              token.encrypted_token AS "encryptedToken",
              notification.title,
              notification.body
       FROM notification_deliveries delivery
       JOIN notifications notification ON notification.id = delivery.notification_id
       JOIN device_tokens token ON token.id = delivery.device_token_id
       WHERE delivery.notification_id = $1 AND delivery.status = 'pending'
       ORDER BY token.created_at, token.id`,
      [notificationId],
    );
    return result.rows;
  }

  async markDeliverySucceeded(notificationId: string, deviceTokenId: string, messageName?: string): Promise<void> {
    await this.database.query(
      `UPDATE notification_deliveries
       SET status = 'delivered', attempts = attempts + 1, fcm_message_name = $3,
           last_error = NULL, delivered_at = now(), updated_at = now()
       WHERE notification_id = $1 AND device_token_id = $2 AND status = 'pending'`,
      [notificationId, deviceTokenId, messageName ?? null],
    );
  }

  async markDeliveryFailed(
    notificationId: string,
    deviceTokenId: string,
    error: string,
    invalidToken: boolean,
  ): Promise<void> {
    await this.database.transaction(async (transaction) => {
      await transaction.query(
        `UPDATE notification_deliveries
         SET status = CASE WHEN $4 THEN 'invalid' ELSE 'pending' END,
             attempts = attempts + 1, last_error = $3, updated_at = now()
         WHERE notification_id = $1 AND device_token_id = $2 AND status = 'pending'`,
        [notificationId, deviceTokenId, error.slice(0, 2000), invalidToken],
      );
      if (invalidToken) {
        await transaction.query('DELETE FROM device_tokens WHERE id = $1', [deviceTokenId]);
      }
    });
  }

  async markProcessed(consumer: string, messageId: string): Promise<void> {
    await this.database.query(
      `INSERT INTO processed_messages (consumer, message_id)
       VALUES ($1, $2) ON CONFLICT DO NOTHING`,
      [consumer, messageId],
    );
  }

  async passwordRecoveryDelivery(tokenId: string): Promise<PasswordRecoveryDelivery | null> {
    const result = await this.database.query<PasswordRecoveryDelivery>(
      `SELECT users.email::text, token.encrypted_token AS "encryptedToken"
       FROM auth_action_tokens token
       JOIN users ON users.id = token.user_id
       WHERE token.id = $1 AND token.purpose = 'password_recovery'
         AND token.consumed_at IS NULL AND token.expires_at > now()
         AND users.status = 'active' AND users.deleted_at IS NULL`,
      [tokenId],
    );
    return result.rows[0] ?? null;
  }

  async emailConfirmationDelivery(tokenId: string): Promise<PasswordRecoveryDelivery | null> {
    const result = await this.database.query<PasswordRecoveryDelivery>(
      `SELECT users.email::text, token.encrypted_token AS "encryptedToken"
       FROM auth_action_tokens token
       JOIN users ON users.id = token.user_id
       WHERE token.id = $1 AND token.purpose = 'email_confirmation'
         AND token.consumed_at IS NULL AND token.expires_at > now()
         AND users.email_verified_at IS NULL
         AND users.status = 'active' AND users.deleted_at IS NULL`,
      [tokenId],
    );
    return result.rows[0] ?? null;
  }

  async privacyExport(exportId: string, userId: string): Promise<Record<string, unknown> | null> {
    const result = await this.database.query<{ document: Record<string, unknown> }>(
      `SELECT jsonb_build_object(
         'export_version', '1',
         'exported_at', to_jsonb(now()),
         'user_id', to_jsonb(request.user_id),
         'profile', (SELECT to_jsonb(profile) FROM profiles profile WHERE profile.id = request.user_id),
         'user_quests', COALESCE((SELECT jsonb_agg(to_jsonb(item) ORDER BY item.assigned_at)
                                  FROM user_quests item WHERE item.user_id = request.user_id), '[]'::jsonb),
         'submissions', COALESCE((SELECT jsonb_agg(to_jsonb(item) ORDER BY item.submitted_at)
                                  FROM submissions item WHERE item.user_id = request.user_id), '[]'::jsonb),
         'comments', COALESCE((SELECT jsonb_agg(to_jsonb(item) ORDER BY item.created_at)
                               FROM comments item WHERE item.user_id = request.user_id), '[]'::jsonb),
         'reactions', COALESCE((SELECT jsonb_agg(to_jsonb(item) ORDER BY item.created_at)
                                FROM reactions item WHERE item.user_id = request.user_id), '[]'::jsonb),
         'follows_following', COALESCE((SELECT jsonb_agg(to_jsonb(item) ORDER BY item.created_at)
                                       FROM follows item WHERE item.follower_id = request.user_id), '[]'::jsonb),
         'follows_followers', COALESCE((SELECT jsonb_agg(to_jsonb(item) ORDER BY item.created_at)
                                       FROM follows item WHERE item.following_id = request.user_id), '[]'::jsonb),
         'notifications', COALESCE((SELECT jsonb_agg(to_jsonb(item) ORDER BY item.created_at)
                                    FROM notifications item WHERE item.user_id = request.user_id), '[]'::jsonb)
       ) AS document
       FROM gdpr_export_log request
       WHERE request.id = $1 AND request.user_id = $2 AND request.completed_at IS NULL`,
      [exportId, userId],
    );
    return result.rows[0]?.document ?? null;
  }

  async completePrivacyExport(exportId: string, userId: string, objectKey: string): Promise<void> {
    await this.database.query(
      `UPDATE gdpr_export_log
       SET completed_at = now(), object_key = $3, expires_at = now() + interval '7 days'
       WHERE id = $1 AND user_id = $2 AND completed_at IS NULL`,
      [exportId, userId, objectKey],
    );
  }

  async accountMediaKeys(requestId: string, userId: string): Promise<readonly string[] | null> {
    const request = await this.database.query(
      `SELECT 1 FROM account_delete_requests
       WHERE id = $1 AND user_id = $2 AND completed_at IS NULL AND cancelled_at IS NULL
         AND execute_after <= now()`,
      [requestId, userId],
    );
    if (!request.rowCount) return null;
    const media = await this.database.query<{ object_key: string }>(
      `SELECT object_key FROM media_objects
       WHERE user_id = $1 AND status <> 'deleted' ORDER BY created_at, id`,
      [userId],
    );
    return media.rows.map((row) => row.object_key);
  }

  async deleteAccount(requestId: string, userId: string): Promise<void> {
    await this.database.transaction(async (transaction) => {
      const request = await transaction.query(
        `SELECT 1 FROM account_delete_requests
         WHERE id = $1 AND user_id = $2 AND completed_at IS NULL AND cancelled_at IS NULL
           AND execute_after <= now() FOR UPDATE`,
        [requestId, userId],
      );
      if (!request.rowCount) return;
      await transaction.query('DELETE FROM users WHERE id = $1', [userId]);
    });
  }
}
