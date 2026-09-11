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
  readonly journeysAbandoned: number;
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
        journeysAbandoned: 0,
      };
    });
  }

  /**
   * Closes journeys left standing on a rejection nobody answered.
   *
   * A rejected checkpoint does not end a journey — the player can retake it
   * or appeal, and both are the point. But if they do neither, the run sat
   * in their active quests for good: `unapprovedSteps` still had something
   * to do, so nothing ever completed it, and Home kept showing a journey
   * whose only news was weeks-old bad news.
   *
   * So silence gets a deadline. The clock starts at the rejection and is
   * cleared by any answer to it: a retake makes an assigned attempt exist,
   * an appeal flips `appealed`, and either one takes the run out of this
   * query entirely. Abandoned rather than expired, because expiry is what
   * the timer does and this is a decision the player made by not making one.
   */
  async abandonUnansweredJourneys(): Promise<number> {
    const graceHours = this.config.get('JOURNEY_REJECTION_GRACE_HOURS', { infer: true });
    const batchSize = this.config.get('QUEST_MAINTENANCE_BATCH_SIZE', { infer: true });
    return this.database.transaction(async (transaction) => {
      const abandoned = await transaction.query<{ id: string; owner_user_id: string; name: string }>(
        `WITH stale AS (
           SELECT r.id
           FROM quest_chain_runs r
           WHERE r.status = 'active' AND r.run_kind = 'solo'
             -- Every remaining checkpoint is blocked behind an unanswered
             -- rejection. A run with anything else still open is a run the
             -- player can get on with, and is none of this sweep's business.
             AND NOT EXISTS (
               SELECT 1 FROM quest_chain_steps cs
               WHERE cs.chain_id = r.chain_id
                 AND EXISTS (
                   SELECT 1 FROM user_quests uq
                   WHERE uq.quest_id = cs.quest_id AND uq.user_id = r.owner_user_id
                     AND uq.status IN ('assigned', 'submitted'))
             )
             AND EXISTS (
               SELECT 1 FROM quest_chain_steps cs
               JOIN user_quests uq ON uq.quest_id = cs.quest_id AND uq.user_id = r.owner_user_id
               JOIN submissions s ON s.user_quest_id = uq.id
               WHERE cs.chain_id = r.chain_id AND uq.status = 'rejected'
                 AND s.status = 'rejected' AND NOT s.appealed AND s.deleted_at IS NULL
                 AND s.reviewed_at < now() - make_interval(hours => $2))
           ORDER BY r.started_at, r.id LIMIT $1 FOR UPDATE SKIP LOCKED
         )
         UPDATE quest_chain_runs r
            SET status = 'abandoned', updated_at = now()
           FROM stale WHERE r.id = stale.id
         RETURNING r.id, r.owner_user_id, (SELECT name FROM quest_chains WHERE id = r.chain_id) AS name`,
        [batchSize, graceHours],
      );
      for (const run of abandoned.rows) {
        await this.notify(
          run.owner_user_id,
          'Journey closed. 🚪',
          `"${run.name}" stopped where the rejected checkpoint was. Start it again whenever you want — nothing you finished is lost.`,
          'journey_abandoned',
          run.id,
          transaction,
        );
      }
      return abandoned.rowCount ?? 0;
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
