import { Injectable, NotFoundException } from '@nestjs/common';
import type { ChronologicalCursor } from '../../../common/pagination/cursor.js';
import { DatabaseService, type DatabaseTransaction } from '../../../infrastructure/database/database.service.js';

export interface NotificationRow extends Record<string, unknown> {
  readonly id: string;
  readonly created_at: Date | string;
}

@Injectable()
export class NotificationsRepository {
  constructor(private readonly database: DatabaseService) {}

  async list(userId: string, limit: number, cursor?: ChronologicalCursor): Promise<readonly NotificationRow[]> {
    const result = await this.database.query<NotificationRow>(
      `SELECT n.id, n.user_id, n.title, n.body, n.type, n.reference_id, n.is_read,
              n.created_at, n.actor_id,
              CASE WHEN actor.id IS NULL THEN NULL ELSE json_build_object(
                'username', actor.username::text,
                'avatar_url', actor.avatar_url
              ) END AS actor_profile
       FROM notifications n
       LEFT JOIN profiles actor ON actor.id = n.actor_id
       WHERE n.user_id = $1
         AND ($3::timestamptz IS NULL OR (n.created_at, n.id) < ($3::timestamptz, $4::uuid))
       ORDER BY n.created_at DESC, n.id DESC
       LIMIT $2`,
      [userId, limit + 1, cursor?.createdAt ?? null, cursor?.id ?? null],
    );
    return result.rows;
  }

  async unreadCount(userId: string): Promise<number> {
    const result = await this.database.typed.selectFrom('notifications')
      .select((eb) => eb.fn.countAll().as('count'))
      .where('user_id', '=', userId).where('is_read', '=', false)
      .executeTakeFirstOrThrow();
    return Number(result.count);
  }

  async markRead(userId: string, notificationId: string): Promise<void> {
    await this.database.transaction(async (transaction) => {
      const result = await transaction.query(
        'UPDATE notifications SET is_read = true WHERE id = $1 AND user_id = $2',
        [notificationId, userId],
      );
      if (!result.rowCount) throw new NotFoundException({ code: 'NOTIFICATION_NOT_FOUND', message: 'Notification not found' });
      await this.emitReadEvent(userId, notificationId, transaction);
    });
  }

  async markAllRead(userId: string): Promise<number> {
    return this.database.transaction(async (transaction) => {
      const result = await transaction.query(
        'UPDATE notifications SET is_read = true WHERE user_id = $1 AND NOT is_read',
        [userId],
      );
      if (result.rowCount) await this.emitReadEvent(userId, null, transaction);
      return result.rowCount ?? 0;
    });
  }

  async upsertDeviceToken(userId: string, tokenHash: Buffer, encryptedToken: Buffer, platform: string): Promise<string> {
    const result = await this.database.query<{ id: string }>(
      `INSERT INTO device_tokens (user_id, token_hash, encrypted_token, platform)
       VALUES ($1, $2, $3, $4)
       ON CONFLICT (token_hash) DO UPDATE
       SET user_id = EXCLUDED.user_id, encrypted_token = EXCLUDED.encrypted_token,
           platform = EXCLUDED.platform, last_seen_at = now()
       RETURNING id`,
      [userId, tokenHash, encryptedToken, platform],
    );
    return result.rows[0].id;
  }

  async deleteDeviceToken(userId: string, tokenHash: Buffer): Promise<void> {
    await this.database.typed.deleteFrom('device_tokens')
      .where('user_id', '=', userId).where('token_hash', '=', tokenHash).execute();
  }

  private async emitReadEvent(
    userId: string,
    notificationId: string | null,
    transaction: DatabaseTransaction,
  ): Promise<void> {
    await transaction.query(
      `INSERT INTO outbox_events (aggregate_type, aggregate_id, event_type, payload)
       VALUES ('user', $1, 'notification.read', $2::jsonb)`,
      [userId, JSON.stringify({ userId, notificationId })],
    );
  }
}
