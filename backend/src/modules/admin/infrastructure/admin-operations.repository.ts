import { Injectable, ConflictException, NotFoundException } from '@nestjs/common';
import { DatabaseService } from '../../../infrastructure/database/database.service.js';
import { AdminRepositoryBase } from './admin-repository.base.js';
import type { InjectQuestDto, SetQotdDto } from '../presentation/admin.dto.js';

@Injectable()
export class AdminOperationsRepository extends AdminRepositoryBase {
  constructor(database: DatabaseService) { super(database); }

  async stats() {
    return (
      await this.database.query(
        `SELECT
         (SELECT count(*)::integer FROM profiles) AS users,
         (SELECT count(*)::integer FROM submissions WHERE status = 'pending') AS pending,
         (SELECT count(*)::integer FROM quests) AS quests,
         (SELECT count(*)::integer FROM submissions WHERE status = 'approved' AND submitted_at >= now() - interval '24 hours') AS "approvedToday",
         (SELECT count(*)::integer FROM user_quests WHERE status = 'assigned') AS "activeQuests",
         (SELECT count(*)::integer FROM submissions WHERE status = 'pending' AND appealed) AS appeals,
         (SELECT count(*)::integer FROM reports WHERE status = 'pending') AS "pendingReports"`,
      )
    ).rows[0];
  }

  async injections(limit: number, offset: number) {
    return (
      await this.database.query(
        `SELECT i.*, q.title AS quest_title, p.username::text AS target_username
       FROM admin_quest_injections i JOIN quests q ON q.id = i.quest_id JOIN profiles p ON p.id = i.target_user_id
       WHERE i.consumed_at IS NULL ORDER BY i.created_at DESC LIMIT $1 OFFSET $2`,
        [limit, offset],
      )
    ).rows;
  }

  async inject(actorId: string, input: InjectQuestDto) {
    try {
      return await this.database.transaction(async (transaction) => {
        const target = await transaction.query(
          'SELECT 1 FROM profiles WHERE id = $1',
          [input.targetUserId],
        );
        if (!target.rowCount)
          throw new NotFoundException({
            code: 'PROFILE_NOT_FOUND',
            message: 'Target user not found',
          });
        const quest = await transaction.query(
          `INSERT INTO quests (title, description, category, difficulty, xp_reward, duration_hours, is_active, created_by)
           VALUES ($1, $2, $3, $4, $5, $6, true, $7) RETURNING *`,
          [
            input.title.trim(),
            input.description.trim(),
            input.category.trim(),
            input.difficulty,
            input.xpReward,
            input.durationHours,
            actorId,
          ],
        );
        await transaction.query(
          'INSERT INTO admin_quest_injections (target_user_id, quest_id, created_by) VALUES ($1, $2, $3)',
          [input.targetUserId, quest.rows[0].id, actorId],
        );
        await this.audit(
          actorId,
          'quest.inject',
          'user',
          input.targetUserId,
          null,
          { quest_id: quest.rows[0].id, xp_reward: input.xpReward },
          transaction,
        );
        return quest.rows[0];
      });
    } catch (error) {
      if (
        typeof error === 'object' &&
        error !== null &&
        'code' in error &&
        error.code === '23505'
      ) {
        throw new ConflictException({
          code: 'PENDING_INJECTION_EXISTS',
          message: 'This user already has a pending injected quest',
        });
      }
      throw error;
    }
  }

  async cancelInjection(actorId: string, id: string): Promise<void> {
    const result = await this.database.query(
      `UPDATE admin_quest_injections SET consumed_at = now() WHERE id = $1 AND consumed_at IS NULL RETURNING target_user_id`,
      [id],
    );
    if (!result.rows[0])
      throw new NotFoundException({
        code: 'INJECTION_NOT_FOUND',
        message: 'Pending injection not found',
      });
    await this.database.query(
      `INSERT INTO admin_audit_log (actor_id, action, target_type, target_id, after_state)
       VALUES ($1, 'quest.injection.cancel', 'injection', $2, $3::jsonb)`,
      [
        actorId,
        id,
        JSON.stringify({ target_user_id: result.rows[0].target_user_id }),
      ],
    );
  }

  async notify(
    actorId: string,
    targetUserId: string | undefined,
    title: string,
    body: string,
    type: string,
  ) {
    return this.database.transaction(async (transaction) => {
      const result = await transaction.query<{ id: string; user_id: string }>(
        `INSERT INTO notifications (user_id, title, body, type, actor_id)
         SELECT id, $2, $3, $4, $5 FROM users WHERE status = 'active' AND ($1::uuid IS NULL OR id = $1)
         RETURNING id, user_id`,
        [targetUserId ?? null, title, body, type, actorId],
      );
      if (targetUserId && !result.rowCount)
        throw new NotFoundException({
          code: 'USER_NOT_FOUND',
          message: 'Target user not found or inactive',
        });
      if (result.rowCount) {
        await transaction.query(
          `INSERT INTO outbox_events (aggregate_type, aggregate_id, event_type, payload)
           SELECT 'notification', id, 'notification.created', jsonb_build_object('notificationId', id, 'userId', user_id)
           FROM notifications WHERE id = ANY($1::uuid[])`,
          [result.rows.map((row) => row.id)],
        );
      }
      await this.audit(
        actorId,
        targetUserId ? 'notification.send' : 'notification.broadcast',
        'notification',
        null,
        null,
        {
          target_user_id: targetUserId,
          title,
          recipient_count: result.rowCount,
        },
        transaction,
      );
      return { recipients: result.rowCount ?? 0 };
    });
  }

  async config() {
    return (
      await this.database.query(
        'SELECT key, value, description, is_public, updated_at FROM app_config ORDER BY key',
      )
    ).rows;
  }
  /// XP reconciliation: stored profile totals next to what the approved
  /// quest history implies. One aggregate here replaces the admin page's
  /// fetch of every profile plus every approved user_quest.

  async notifications(limit: number, offset: number) {
    return (
      await this.database.query(
        `SELECT n.id, n.user_id, n.title, n.body, n.type, n.created_at,
                p.username::text AS username
         FROM notifications n
         LEFT JOIN profiles p ON p.id = n.user_id
         WHERE n.type <> 'announcement'
         ORDER BY n.created_at DESC
         LIMIT $1 OFFSET $2`,
        [Math.min(Math.max(limit, 1), 200), Math.max(offset, 0)],
      )
    ).rows;
  }

  async publicConfig() {
    return (
      await this.database.query(
        'SELECT key, value FROM app_config WHERE is_public ORDER BY key',
      )
    ).rows;
  }

  /**
   * The public deletion-request queue.
   *
   * These arrive from the signed-out compliance page, which cannot erase
   * anything itself. Without a read endpoint the rows would be invisible and
   * the requests would sit unactioned — the same failure as an audit log
   * nothing can read.
   */
  async deletionRequests(limit: number, offset: number) {
    return (
      await this.database.query(
        `SELECT r.id, r.email::text, r.note, r.created_at, r.handled_at,
                r.matched_user_id,
                p.username::text AS matched_username,
                handler.email::text AS handled_by_email
         FROM public_deletion_requests r
         LEFT JOIN profiles p ON p.id = r.matched_user_id
         LEFT JOIN users handler ON handler.id = r.handled_by
         ORDER BY (r.handled_at IS NULL) DESC, r.created_at ASC
         LIMIT $1 OFFSET $2`,
        [Math.min(Math.max(limit, 1), 200), Math.max(offset, 0)],
      )
    ).rows;
  }

  /**
   * Marks a deletion request handled, with an audit row naming the operator.
   *
   * Marking it handled is a record that a human verified the requester; the
   * erasure itself still runs through the authenticated account flow.
   */
  async markDeletionRequestHandled(actorId: string, requestId: string) {
    return this.database.transaction(async (transaction) => {
      const before = await transaction.query<{ email: string; handled_at: Date | null }>(
        'SELECT email::text, handled_at FROM public_deletion_requests WHERE id = $1 FOR UPDATE',
        [requestId],
      );
      const row = before.rows[0];
      if (!row) {
        throw new NotFoundException({
          code: 'DELETION_REQUEST_NOT_FOUND',
          message: 'Deletion request not found',
        });
      }
      await transaction.query(
        'UPDATE public_deletion_requests SET handled_at = now(), handled_by = $2 WHERE id = $1',
        [requestId, actorId],
      );
      await this.audit(
        actorId,
        'deletion_request.handled',
        'public_deletion_requests',
        requestId,
        { handled_at: row.handled_at },
        { email: row.email },
        transaction,
      );
    });
  }

  async setConfig(
    actorId: string,
    key: string,
    value: unknown,
    description: string | undefined,
    isPublic: boolean,
  ) {
    return (
      await this.database.query(
        `INSERT INTO app_config (key, value, description, is_public, updated_by)
       VALUES ($1, $2::jsonb, $3, $4, $5) ON CONFLICT (key) DO UPDATE
       SET value = EXCLUDED.value, description = COALESCE(EXCLUDED.description, app_config.description),
           is_public = EXCLUDED.is_public, updated_by = EXCLUDED.updated_by, updated_at = now()
       RETURNING *`,
        [key, JSON.stringify(value), description ?? null, isPublic, actorId],
      )
    ).rows[0];
  }

  async qotd(limit: number, offset: number) {
    return (
      await this.database.query(
        `SELECT d.id, d.quest_id, to_char(d.display_date, 'YYYY-MM-DD') AS display_date,
              d.ticket_no, d.bonus_xp, d.note, d.created_by, d.created_at, d.updated_at,
              json_build_object('title', q.title, 'category', q.category, 'xp_reward', q.xp_reward, 'difficulty', q.difficulty) AS quests
       FROM quest_of_the_day d JOIN quests q ON q.id = d.quest_id
       ORDER BY d.display_date DESC LIMIT $1 OFFSET $2`,
        [limit, offset],
      )
    ).rows;
  }

  async setQotd(actorId: string, input: SetQotdDto) {
    return (
      await this.database.query(
        `INSERT INTO quest_of_the_day (quest_id, display_date, ticket_no, bonus_xp, note, created_by)
       VALUES ($1, $2, $3, $4, $5, $6) ON CONFLICT (display_date) DO UPDATE
       SET quest_id = EXCLUDED.quest_id, ticket_no = EXCLUDED.ticket_no, bonus_xp = EXCLUDED.bonus_xp,
           note = EXCLUDED.note, updated_at = now() RETURNING *`,
        [
          input.questId,
          input.displayDate,
          input.ticketNo?.trim() || null,
          input.bonusXp,
          input.note?.trim() || null,
          actorId,
        ],
      )
    ).rows[0];
  }

  async deleteQotd(id: string): Promise<void> {
    const result = await this.database.query(
      'DELETE FROM quest_of_the_day WHERE id = $1',
      [id],
    );
    if (!result.rowCount)
      throw new NotFoundException({
        code: 'QOTD_NOT_FOUND',
        message: 'QOTD entry not found',
      });
  }

  async waitlist(limit: number, offset: number) {
    return (
      await this.database.query(
        'SELECT * FROM waitlist ORDER BY created_at DESC LIMIT $1 OFFSET $2',
        [limit, offset],
      )
    ).rows;
  }
}
