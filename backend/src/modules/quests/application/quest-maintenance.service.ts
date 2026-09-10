import { Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import type { Environment } from '../../../config/environment.js';
import {
  DatabaseService,
  type DatabaseTransaction,
} from '../../../infrastructure/database/database.service.js';

export interface QuestMaintenanceOutcome {
  readonly expired: number;
  readonly warned: number;
}

@Injectable()
export class QuestMaintenanceService {
  constructor(
    private readonly database: DatabaseService,
    private readonly config: ConfigService<Environment, true>,
  ) {}

  async expireAndWarn(): Promise<QuestMaintenanceOutcome> {
    const batchSize = this.config.get('QUEST_MAINTENANCE_BATCH_SIZE', {
      infer: true,
    });
    return this.database.transaction(async (transaction) => {
      const expired = await transaction.query<{ id: string; user_id: string }>(
        `WITH due AS (
           SELECT id FROM user_quests
           WHERE status = 'assigned' AND expires_at < now()
           ORDER BY expires_at, id LIMIT $1 FOR UPDATE SKIP LOCKED
         )
         UPDATE user_quests uq
            SET status = 'expired', version = version + 1
           FROM due WHERE uq.id = due.id
         RETURNING uq.id, uq.user_id`,
        [batchSize],
      );
      for (const assignment of expired.rows) {
        await this.notify(
          assignment.user_id,
          'Quest gone. Poof. 💨',
          'Time ran out. Pull a new one and try again. No streak shame here.',
          'quest_expired',
          assignment.id,
          transaction,
        );
        await this.emit(
          'quest',
          assignment.id,
          'quest.expired',
          { userId: assignment.user_id, userQuestId: assignment.id },
          transaction,
        );
      }

      const warned = await transaction.query<{ id: string; user_id: string }>(
        `WITH candidates AS (
           SELECT uq.id, uq.user_id
           FROM user_quests uq
           WHERE uq.status = 'assigned'
             AND uq.expires_at BETWEEN now() + interval '25 minutes' AND now() + interval '35 minutes'
             AND NOT EXISTS (
               SELECT 1 FROM notifications n
               WHERE n.user_id = uq.user_id
                 AND n.type = 'quest_timer_warning'
                 AND n.reference_id = uq.id
             )
           ORDER BY uq.expires_at, uq.id LIMIT $1 FOR UPDATE OF uq SKIP LOCKED
         ), inserted AS (
           INSERT INTO notifications (user_id, title, body, type, reference_id)
           SELECT user_id, '⏰ 30 minutes. That''s it.',
                  'Your quest is about to peace out. Move.',
                  'quest_timer_warning', id
           FROM candidates
           RETURNING id, user_id
         )
         INSERT INTO outbox_events (aggregate_type, aggregate_id, event_type, payload)
         SELECT 'notification', id, 'notification.created',
                jsonb_build_object('notificationId', id, 'userId', user_id)
         FROM inserted
         RETURNING aggregate_id AS id, payload->>'userId' AS user_id`,
        [batchSize],
      );

      return {
        expired: expired.rowCount ?? 0,
        warned: warned.rowCount ?? 0,
      };
    });
  }

  async remindPendingReviews(): Promise<{ reminded: number; pending: number }> {
    return this.database.transaction(async (transaction) => {
      const pending = await transaction.query<{ count: number }>(
        `SELECT count(*)::integer AS count FROM submissions
         WHERE status = 'pending' AND submitted_at < now() - interval '24 hours'`,
      );
      const count = pending.rows[0].count;
      if (count === 0) return { reminded: 0, pending: 0 };

      const reminders = await transaction.query(
        `WITH inserted AS (
           INSERT INTO notifications (user_id, title, body, type)
           SELECT a.user_id,
                  format('⚠️ %s submissions are getting stale.', $1::integer),
                  'These have been sitting in the queue for over 24 hours. Time to triage.',
                  'pending_review_reminder'
           FROM admins a
           WHERE NOT EXISTS (
             SELECT 1 FROM notifications n
             WHERE n.user_id = a.user_id
               AND n.type = 'pending_review_reminder'
               AND n.created_at > now() - interval '24 hours'
           )
           RETURNING id, user_id
         )
         INSERT INTO outbox_events (aggregate_type, aggregate_id, event_type, payload)
         SELECT 'notification', id, 'notification.created',
                jsonb_build_object('notificationId', id, 'userId', user_id)
         FROM inserted`,
        [count],
      );
      return { reminded: reminders.rowCount ?? 0, pending: count };
    });
  }

  private async notify(
    userId: string,
    title: string,
    body: string,
    type: string,
    referenceId: string,
    transaction: DatabaseTransaction,
  ): Promise<void> {
    const notification = await transaction.query<{ id: string }>(
      `INSERT INTO notifications (user_id, title, body, type, reference_id)
       VALUES ($1, $2, $3, $4, $5) RETURNING id`,
      [userId, title, body, type, referenceId],
    );
    await this.emit(
      'notification',
      notification.rows[0].id,
      'notification.created',
      { notificationId: notification.rows[0].id, userId },
      transaction,
    );
  }

  private async emit(
    aggregateType: string,
    aggregateId: string,
    eventType: string,
    payload: Record<string, unknown>,
    transaction: DatabaseTransaction,
  ): Promise<void> {
    await transaction.query(
      `INSERT INTO outbox_events (aggregate_type, aggregate_id, event_type, payload)
       VALUES ($1, $2, $3, $4::jsonb)`,
      [aggregateType, aggregateId, eventType, JSON.stringify(payload)],
    );
  }
}
