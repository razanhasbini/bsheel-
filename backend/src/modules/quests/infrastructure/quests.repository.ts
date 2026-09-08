import {
  ConflictException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import {
  DatabaseService,
  type DatabaseTransaction,
} from '../../../infrastructure/database/database.service.js';
import type { QuestRecord, UserQuestRecord } from '../domain/quest.types.js';
import type {
  CreateQuestDto,
  UpdateQuestDto,
} from '../presentation/quest.dto.js';

@Injectable()
export class QuestsRepository {
  constructor(private readonly database: DatabaseService) {}

  async findQuest(id: string): Promise<QuestRecord | null> {
    const result = await this.database.query<QuestRecord>(
      'SELECT * FROM quests WHERE id = $1',
      [id],
    );
    return result.rows[0] ?? null;
  }

  async listAll(): Promise<readonly QuestRecord[]> {
    return (
      await this.database.query<QuestRecord>(
        'SELECT * FROM quests ORDER BY created_at DESC, id DESC',
      )
    ).rows;
  }

  async create(input: CreateQuestDto, actorId: string): Promise<QuestRecord> {
    const result = await this.database.query<QuestRecord>(
      `INSERT INTO quests (title, description, category, difficulty, xp_reward, duration_hours, is_active, created_by)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8) RETURNING *`,
      [
        input.title.trim(),
        input.description.trim(),
        input.category.trim(),
        input.difficulty,
        input.xpReward,
        input.durationHours,
        input.isActive,
        actorId,
      ],
    );
    return result.rows[0];
  }

  async createBulk(
    input: readonly CreateQuestDto[],
    actorId: string,
  ): Promise<readonly QuestRecord[]> {
    return this.database.transaction(async (transaction) => {
      const result = await transaction.query<QuestRecord>(
        `INSERT INTO quests
           (title, description, category, difficulty, xp_reward, duration_hours, is_active, created_by)
         SELECT trim(item.title), trim(item.description), trim(item.category), item.difficulty,
                item.xp_reward, item.duration_hours, item.is_active, $2
         FROM jsonb_to_recordset($1::jsonb) AS item(
           title text, description text, category text, difficulty text,
           xp_reward integer, duration_hours integer, is_active boolean
         )
         RETURNING *`,
        [
          JSON.stringify(
            input.map((quest) => ({
              title: quest.title,
              description: quest.description,
              category: quest.category,
              difficulty: quest.difficulty,
              xp_reward: quest.xpReward,
              duration_hours: quest.durationHours,
              is_active: quest.isActive,
            })),
          ),
          actorId,
        ],
      );
      await transaction.query(
        `INSERT INTO admin_audit_log (actor_id, action, target_type, after_state)
         VALUES ($1, 'quest.bulk_create', 'quest', $2::jsonb)`,
        [actorId, JSON.stringify({ count: result.rowCount })],
      );
      return result.rows;
    });
  }

  async update(id: string, input: UpdateQuestDto): Promise<QuestRecord | null> {
    const result = await this.database.query<QuestRecord>(
      `UPDATE quests SET
         title = COALESCE($2, title), description = COALESCE($3, description),
         category = COALESCE($4, category), difficulty = COALESCE($5, difficulty),
         xp_reward = COALESCE($6, xp_reward), duration_hours = COALESCE($7, duration_hours),
         is_active = COALESCE($8, is_active), updated_at = now()
       WHERE id = $1 RETURNING *`,
      [
        id,
        input.title?.trim(),
        input.description?.trim(),
        input.category?.trim(),
        input.difficulty,
        input.xpReward,
        input.durationHours,
        input.isActive,
      ],
    );
    return result.rows[0] ?? null;
  }

  async delete(id: string, actorId: string): Promise<void> {
    try {
      await this.database.transaction(async (transaction) => {
        const quest = await transaction.query<QuestRecord>(
          'DELETE FROM quests WHERE id = $1 RETURNING *',
          [id],
        );
        if (!quest.rows[0]) {
          throw new NotFoundException({
            code: 'QUEST_NOT_FOUND',
            message: 'Quest not found',
          });
        }
        await transaction.query(
          `INSERT INTO admin_audit_log
             (actor_id, action, target_type, target_id, before_state)
           VALUES ($1, 'quest.delete', 'quest', $2, $3::jsonb)`,
          [actorId, id, JSON.stringify(quest.rows[0])],
        );
      });
    } catch (error) {
      if (this.isForeignKeyViolation(error)) {
        throw new ConflictException({
          code: 'QUEST_IN_USE',
          message:
            'Quest is still referenced by collaboration or scheduling data',
        });
      }
      throw error;
    }
  }

  async deleteAll(actorId: string): Promise<{ deleted: number }> {
    try {
      return await this.database.transaction(async (transaction) => {
        const deleted = await transaction.query(
          'DELETE FROM quests RETURNING id',
        );
        await transaction.query(
          `INSERT INTO admin_audit_log (actor_id, action, target_type, after_state)
           VALUES ($1, 'quest.delete_all', 'quest', $2::jsonb)`,
          [actorId, JSON.stringify({ deleted: deleted.rowCount })],
        );
        return { deleted: deleted.rowCount ?? 0 };
      });
    } catch (error) {
      if (this.isForeignKeyViolation(error)) {
        throw new ConflictException({
          code: 'QUESTS_IN_USE',
          message:
            'One or more quests are still referenced by collaboration or scheduling data',
        });
      }
      throw error;
    }
  }

  async findActiveForUser(userId: string): Promise<UserQuestRecord | null> {
    const result = await this.database.query<
      UserQuestRecord & { quests: QuestRecord }
    >(
      `SELECT uq.*, row_to_json(q.*) AS quests
       FROM user_quests uq JOIN quests q ON q.id = uq.quest_id
       WHERE uq.user_id = $1 AND uq.status IN ('assigned', 'submitted')
       ORDER BY uq.assigned_at DESC LIMIT 1`,
      [userId],
    );
    return result.rows[0] ?? null;
  }

  async history(
    userId: string,
    limit: number,
    offset: number,
  ): Promise<readonly UserQuestRecord[]> {
    const result = await this.database.query<UserQuestRecord>(
      `SELECT uq.*, row_to_json(q.*) AS quests
       FROM user_quests uq JOIN quests q ON q.id = uq.quest_id
       WHERE uq.user_id = $1
       ORDER BY uq.assigned_at DESC, uq.id DESC
       LIMIT $2 OFFSET $3`,
      [userId, Math.min(Math.max(limit, 1), 100), Math.max(offset, 0)],
    );
    return result.rows;
  }

  /// Assigns a specific quest.
  ///
  /// `displaceActive` is for admin assignment only: a moderator picking a
  /// quest for a user is an override, so any in-flight quest is expired in
  /// the same transaction rather than rejecting the request. A user
  /// assigning their own quest still cannot bypass the one-active rule.
  async assignSpecific(
    userId: string,
    questId: string,
    displaceActive = false,
  ): Promise<UserQuestRecord> {
    return this.database.transaction(async (transaction) => {
      await this.lockUser(userId, transaction);
      await this.expireOverdueForUser(userId, transaction);
      if (displaceActive) {
        await transaction.query(
          `UPDATE user_quests SET status = 'expired', version = version + 1
           WHERE user_id = $1 AND status IN ('assigned', 'submitted')`,
          [userId],
        );
      }
      const active = await transaction.query(
        `SELECT 1 FROM user_quests WHERE user_id = $1 AND status IN ('assigned', 'submitted') LIMIT 1`,
        [userId],
      );
      if (active.rowCount) {
        throw new ConflictException({
          code: 'ACTIVE_QUEST_EXISTS',
          message: 'User already has an active quest',
        });
      }
      const questResult = await transaction.query<QuestRecord>(
        'SELECT * FROM quests WHERE id = $1 AND is_active = true',
        [questId],
      );
      const quest = questResult.rows[0];
      if (!quest)
        throw new NotFoundException({
          code: 'QUEST_NOT_FOUND',
          message: 'Quest not found or inactive',
        });
      const assigned = await transaction.query<UserQuestRecord>(
        `INSERT INTO user_quests (user_id, quest_id, expires_at)
         VALUES ($1, $2, now() + make_interval(hours => $3)) RETURNING *`,
        [userId, questId, quest.duration_hours],
      );
      await transaction.query(
        `UPDATE admin_quest_injections SET consumed_at = now()
         WHERE target_user_id = $1 AND quest_id = $2 AND consumed_at IS NULL`,
        [userId, questId],
      );
      await this.insertAssignmentNotification(
        userId,
        assigned.rows[0],
        quest.duration_hours,
        transaction,
      );
      await this.emitQuest(
        'quest.assigned',
        assigned.rows[0].id,
        {
          userId,
          userQuestId: assigned.rows[0].id,
          questId,
        },
        transaction,
      );
      return { ...assigned.rows[0], quests: quest };
    });
  }

  async expire(userId: string, userQuestId: string): Promise<void> {
    await this.database.transaction(async (transaction) => {
      const result = await transaction.query(
        `UPDATE user_quests SET status = 'expired', version = version + 1
         WHERE id = $1 AND user_id = $2 AND status = 'assigned' AND expires_at <= now()
         RETURNING id`,
        [userQuestId, userId],
      );
      if (!result.rowCount) {
        throw new ConflictException({
          code: 'QUEST_NOT_EXPIRABLE',
          message: 'Quest is not assigned to you or has not expired',
        });
      }
      await this.emitQuest(
        'quest.expired',
        userQuestId,
        {
          userId,
          userQuestId,
        },
        transaction,
      );
    });
  }

  async pickerOptions(
    userId: string,
    requestedCount: number,
  ): Promise<readonly QuestRecord[]> {
    const count = Math.min(Math.max(requestedCount || 3, 1), 20);
    return this.database.transaction(async (transaction) => {
      await this.lockUser(userId, transaction);
      const injection = await transaction.query<QuestRecord>(
        `WITH popped AS (
           UPDATE admin_quest_injections SET consumed_at = now()
           WHERE id = (SELECT id FROM admin_quest_injections WHERE target_user_id = $1 AND consumed_at IS NULL ORDER BY created_at LIMIT 1 FOR UPDATE SKIP LOCKED)
           RETURNING quest_id
         ) SELECT q.* FROM popped p JOIN quests q ON q.id = p.quest_id WHERE q.is_active`,
        [userId],
      );
      const injected = injection.rows[0];
      const remaining = count - (injected ? 1 : 0);
      if (remaining <= 0) return injected ? [injected] : [];
      const adminSlots = Math.max(1, Math.ceil(remaining / 2));
      const result = await transaction.query<QuestRecord>(
        `WITH eligible AS (
           SELECT q.* FROM quests q
           WHERE q.is_active
             AND ($2::uuid IS NULL OR q.id <> $2)
             AND NOT EXISTS (SELECT 1 FROM admin_quest_injections i WHERE i.quest_id = q.id)
             AND NOT EXISTS (
               SELECT 1 FROM user_quests uq WHERE uq.user_id = $1 AND uq.quest_id = q.id
               AND uq.status IN ('submitted', 'approved')
             )
         ), preferred AS (
           SELECT * FROM eligible WHERE created_by IS NOT NULL ORDER BY created_at DESC, random() LIMIT $3
         ), filler AS (
           SELECT * FROM eligible e WHERE NOT EXISTS (SELECT 1 FROM preferred p WHERE p.id = e.id)
           ORDER BY random() LIMIT GREATEST(0, $4 - (SELECT count(*)::integer FROM preferred))
         ) SELECT * FROM preferred UNION ALL SELECT * FROM filler`,
        [userId, injected?.id ?? null, adminSlots, remaining],
      );
      return injected ? [injected, ...result.rows] : result.rows;
    });
  }

  async questOfTheDay(): Promise<Record<string, unknown> | null> {
    const result = await this.database.query(
      `SELECT d.id, to_char(d.display_date, 'YYYY-MM-DD') AS display_date, d.ticket_no, d.bonus_xp, q.id AS quest_id,
              q.title AS quest_title, q.description AS quest_description,
              q.category AS quest_category, q.difficulty AS quest_difficulty,
              q.xp_reward AS quest_xp_reward, q.duration_hours AS quest_duration_hours
       FROM quest_of_the_day d JOIN quests q ON q.id = d.quest_id
       WHERE d.display_date = (now() AT TIME ZONE 'UTC')::date LIMIT 1`,
    );
    return result.rows[0] ?? null;
  }

  async followingActive(
    userId: string,
    limit: number,
  ): Promise<readonly Record<string, unknown>[]> {
    const capped = Math.min(Math.max(limit || 12, 1), 40);
    const result = await this.database.query(
      `WITH followed AS (
         SELECT uq.id AS user_quest_id, uq.user_id, p.username::text, p.display_name, p.avatar_url,
                q.id AS quest_id, q.title AS quest_title, q.category AS quest_category,
                q.xp_reward, uq.assigned_at, uq.expires_at, 0 AS pool
         FROM user_quests uq JOIN follows f ON f.following_id = uq.user_id AND f.follower_id = $1
         JOIN profiles p ON p.id = uq.user_id JOIN quests q ON q.id = uq.quest_id
         WHERE uq.status = 'assigned' AND uq.expires_at > now() AND uq.user_id <> $1
       ), global_pool AS (
         SELECT uq.id AS user_quest_id, uq.user_id, p.username::text, p.display_name, p.avatar_url,
                q.id AS quest_id, q.title AS quest_title, q.category AS quest_category,
                q.xp_reward, uq.assigned_at, uq.expires_at, 1 AS pool
         FROM user_quests uq JOIN profiles p ON p.id = uq.user_id JOIN quests q ON q.id = uq.quest_id
         WHERE uq.status = 'assigned' AND uq.expires_at > now() AND uq.user_id <> $1
           AND NOT EXISTS (SELECT 1 FROM followed)
       ) SELECT * FROM (SELECT * FROM followed UNION ALL SELECT * FROM global_pool) candidates
         ORDER BY pool, assigned_at DESC LIMIT $2`,
      [userId, capped],
    );
    return result.rows;
  }

  async rerollsRemaining(userId: string): Promise<number> {
    const result = await this.database.query<{ remaining: number }>(
      `SELECT GREATEST(0, 5 - count(*))::integer AS remaining FROM quest_reroll_log
       WHERE user_id = $1 AND rerolled_at > now() - interval '24 hours'`,
      [userId],
    );
    return result.rows[0].remaining;
  }

  async recordReroll(userId: string): Promise<number> {
    return this.database.transaction(async (transaction) => {
      await this.lockUser(userId, transaction);
      const count = await transaction.query<{ used: number }>(
        `SELECT count(*)::integer AS used FROM quest_reroll_log
         WHERE user_id = $1 AND rerolled_at > now() - interval '24 hours'`,
        [userId],
      );
      if (count.rows[0].used >= 5) {
        throw new ConflictException({
          code: 'REROLL_LIMIT_REACHED',
          message: 'Reroll limit reached (5 per 24h)',
        });
      }
      await transaction.query(
        'INSERT INTO quest_reroll_log (user_id) VALUES ($1)',
        [userId],
      );
      return 5 - count.rows[0].used - 1;
    });
  }

  private async lockUser(
    userId: string,
    transaction: DatabaseTransaction,
  ): Promise<void> {
    await transaction.query(
      'SELECT pg_advisory_xact_lock(hashtextextended($1, 0))',
      [userId],
    );
  }

  private async expireOverdueForUser(
    userId: string,
    transaction: DatabaseTransaction,
  ): Promise<void> {
    const expired = await transaction.query<{ id: string }>(
      `UPDATE user_quests SET status = 'expired', version = version + 1
       WHERE user_id = $1 AND status = 'assigned' AND expires_at < now()
       RETURNING id`,
      [userId],
    );
    for (const assignment of expired.rows) {
      await this.emitQuest(
        'quest.expired',
        assignment.id,
        {
          userId,
          userQuestId: assignment.id,
        },
        transaction,
      );
    }
  }

  private async insertAssignmentNotification(
    userId: string,
    assignment: UserQuestRecord,
    durationHours: number,
    transaction: DatabaseTransaction,
  ): Promise<void> {
    const count = await transaction.query<{ count: number }>(
      'SELECT count(*)::integer AS count FROM user_quests WHERE user_id = $1',
      [userId],
    );
    const duration = durationHours === 1 ? '1 hour' : `${durationHours} hours`;
    const first = count.rows[0].count === 1;
    const variants = [
      `Tap in. ${duration} on the clock. ⏳`,
      `A fresh quest landed in your lap. ${duration} to make it count.`,
      `Real life called. It assigned you something. ${duration} to deliver.`,
    ];
    const title = first
      ? 'Your adventure begins. ⚔️'
      : 'New quest just dropped.';
    const body = first
      ? `First quest unlocked. Finish it in ${duration} and the XP is yours.`
      : variants[Math.floor(Math.random() * variants.length)];
    const notification = await transaction.query<{ id: string }>(
      `INSERT INTO notifications (user_id, title, body, type, reference_id)
       VALUES ($1, $2, $3, 'quest_assigned', $4) RETURNING id`,
      [userId, title, body, assignment.id],
    );
    await transaction.query(
      `INSERT INTO outbox_events (aggregate_type, aggregate_id, event_type, payload)
       VALUES ('notification', $1, 'notification.created', $2::jsonb)`,
      [
        notification.rows[0].id,
        JSON.stringify({ notificationId: notification.rows[0].id, userId }),
      ],
    );
  }

  private async emitQuest(
    eventType: string,
    aggregateId: string,
    payload: Record<string, unknown>,
    transaction: DatabaseTransaction,
  ): Promise<void> {
    await transaction.query(
      `INSERT INTO outbox_events (aggregate_type, aggregate_id, event_type, payload)
       VALUES ('quest', $1, $2, $3::jsonb)`,
      [aggregateId, eventType, JSON.stringify(payload)],
    );
  }

  private isForeignKeyViolation(error: unknown): boolean {
    return (
      typeof error === 'object' &&
      error !== null &&
      'code' in error &&
      error.code === '23503'
    );
  }
}
