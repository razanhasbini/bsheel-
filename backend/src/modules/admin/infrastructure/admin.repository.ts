import {
  BadRequestException,
  ConflictException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { DatabaseService } from '../../../infrastructure/database/database.service.js';
import type { InjectQuestDto, SetQotdDto } from '../presentation/admin.dto.js';

@Injectable()
export class AdminRepository {
  constructor(private readonly database: DatabaseService) {}

  async me(userId: string) {
    return (
      (
        await this.database.query(
          `SELECT a.id, a.user_id, a.role::text, p.username::text, p.display_name, p.avatar_url
       FROM admins a JOIN profiles p ON p.id = a.user_id WHERE a.user_id = $1`,
          [userId],
        )
      ).rows[0] ?? null
    );
  }

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

  async users(query: string | undefined, limit: number, offset: number) {
    const pattern = query
      ? `%${query.replaceAll('\\', '\\\\').replaceAll('%', '\\%').replaceAll('_', '\\_')}%`
      : null;
    return (
      await this.database.query(
        `SELECT p.id, p.username::text, p.display_name, p.avatar_url, p.bio, p.xp, p.level,
              p.quests_completed, p.created_at, p.updated_at, u.email::text, u.status::text AS account_status,
              a.role::text AS admin_role
       FROM profiles p JOIN users u ON u.id = p.id LEFT JOIN admins a ON a.user_id = p.id
       WHERE ($1::text IS NULL OR lower(p.username::text) LIKE lower($1) ESCAPE '\\'
              OR lower(p.display_name) LIKE lower($1) ESCAPE '\\'
              OR lower(u.email::text) LIKE lower($1) ESCAPE '\\')
       ORDER BY p.created_at DESC, p.id DESC LIMIT $2 OFFSET $3`,
        [pattern, limit, offset],
      )
    ).rows;
  }

  async createUser(
    actorId: string,
    input: {
      email: string;
      passwordHash: string;
      username: string;
      displayName: string;
    },
  ) {
    try {
      return await this.database.transaction(async (transaction) => {
        const user = await transaction.query<{ id: string }>(
          `INSERT INTO users (email, password_hash, email_verified_at)
           VALUES ($1, $2, now()) RETURNING id`,
          [input.email.trim().toLowerCase(), input.passwordHash],
        );
        const userId = user.rows[0].id;
        await transaction.query(
          `INSERT INTO profiles (id, username, display_name, age_verified, profile_completed)
           VALUES ($1, $2, $3, false, false)`,
          [
            userId,
            input.username.trim().toLowerCase(),
            input.displayName.trim(),
          ],
        );
        await transaction.query(
          `INSERT INTO auth_identities (user_id, provider, provider_subject, provider_email)
           VALUES ($1, 'password', $2::text, $2::citext)`,
          [userId, input.email.trim().toLowerCase()],
        );
        await this.audit(
          actorId,
          'user.create',
          'profile',
          userId,
          null,
          {
            email_confirmed_at_create: true,
          },
          transaction,
        );
        await transaction.query(
          `INSERT INTO outbox_events (aggregate_type, aggregate_id, event_type, payload)
           VALUES ('user', $1, 'user.created', jsonb_build_object('userId', $1::uuid))`,
          [userId],
        );
        return { userId };
      });
    } catch (error) {
      if (
        typeof error === 'object' &&
        error !== null &&
        'code' in error &&
        error.code === '23505'
      ) {
        throw new ConflictException({
          code: 'ACCOUNT_CONFLICT',
          message: 'Email or username is already in use',
        });
      }
      throw error;
    }
  }

  async queueUserDeletion(actorId: string, userId: string): Promise<void> {
    if (actorId === userId) {
      throw new BadRequestException({
        code: 'CANNOT_DELETE_SELF',
        message: 'Cannot delete yourself',
      });
    }
    await this.database.transaction(async (transaction) => {
      const user = await transaction.query<{ status: string }>(
        'SELECT status::text FROM users WHERE id = $1 FOR UPDATE',
        [userId],
      );
      if (!user.rows[0])
        throw new NotFoundException({
          code: 'USER_NOT_FOUND',
          message: 'User not found',
        });
      const request = await transaction.query<{ id: string }>(
        `INSERT INTO account_delete_requests (user_id, execute_after)
         VALUES ($1, now()) ON CONFLICT (user_id) DO UPDATE
         SET cancelled_at = NULL, execute_after = now() RETURNING id`,
        [userId],
      );
      await transaction.query(
        `UPDATE profiles SET username = 'deleted_' || substr(replace(id::text, '-', ''), 1, 8),
           display_name = 'Deleted account', avatar_url = NULL, bio = NULL,
           analytics_consent_at = NULL, updated_at = now() WHERE id = $1`,
        [userId],
      );
      await transaction.query(
        `UPDATE users SET status = 'deletion_pending', token_version = token_version + 1,
           updated_at = now() WHERE id = $1`,
        [userId],
      );
      await transaction.query(
        'UPDATE refresh_sessions SET revoked_at = now() WHERE user_id = $1 AND revoked_at IS NULL',
        [userId],
      );
      await transaction.query('DELETE FROM device_tokens WHERE user_id = $1', [
        userId,
      ]);
      await transaction.query(
        `INSERT INTO outbox_events (aggregate_type, aggregate_id, event_type, payload)
         VALUES ('account', $1, 'account.deletion.requested', $2::jsonb)`,
        [userId, JSON.stringify({ requestId: request.rows[0].id, userId })],
      );
      await this.audit(
        actorId,
        'user.delete',
        'profile',
        userId,
        {
          status: user.rows[0].status,
        },
        { queued: true },
        transaction,
      );
    });
  }

  async setAdminRole(
    actorId: string,
    userId: string,
    role?: 'moderator' | 'super_admin',
  ): Promise<void> {
    if (actorId === userId) {
      throw new BadRequestException({
        code: 'CANNOT_CHANGE_OWN_ROLE',
        message: 'Cannot change your own role',
      });
    }
    await this.database.transaction(async (transaction) => {
      const target = await transaction.query(
        'SELECT 1 FROM users WHERE id = $1 FOR UPDATE',
        [userId],
      );
      if (!target.rowCount)
        throw new NotFoundException({
          code: 'USER_NOT_FOUND',
          message: 'User not found',
        });
      const before = await transaction.query<{ role: string }>(
        'SELECT role::text FROM admins WHERE user_id = $1',
        [userId],
      );
      if (role) {
        await transaction.query(
          `INSERT INTO admins (user_id, role) VALUES ($1, $2::admin_role)
           ON CONFLICT (user_id) DO UPDATE SET role = EXCLUDED.role`,
          [userId, role],
        );
      } else {
        await transaction.query('DELETE FROM admins WHERE user_id = $1', [
          userId,
        ]);
      }
      await this.audit(
        actorId,
        role ? 'admin.grant' : 'admin.revoke',
        'profile',
        userId,
        { role: before.rows[0]?.role ?? null },
        { role: role ?? null },
        transaction,
      );
    });
  }

  async passwordIdentity(
    userId: string,
  ): Promise<{ email: string; username: string } | null> {
    const result = await this.database.query<{
      email: string;
      username: string;
    }>(
      `SELECT users.email::text, profiles.username::text
       FROM users JOIN profiles ON profiles.id = users.id WHERE users.id = $1`,
      [userId],
    );
    return result.rows[0] ?? null;
  }

  async forceResetPassword(
    actorId: string,
    userId: string,
    passwordHash: string,
  ): Promise<void> {
    if (actorId === userId) {
      throw new BadRequestException({
        code: 'USE_SELF_PASSWORD_FLOW',
        message: 'Use the normal account flow to change your own password',
      });
    }
    await this.database.transaction(async (transaction) => {
      const target = await transaction.query<{ email: string }>(
        `UPDATE users SET password_hash = $2, token_version = token_version + 1, updated_at = now()
         WHERE id = $1 RETURNING email::text`,
        [userId, passwordHash],
      );
      if (!target.rows[0])
        throw new NotFoundException({
          code: 'USER_NOT_FOUND',
          message: 'User not found',
        });
      await transaction.query(
        `INSERT INTO auth_identities (user_id, provider, provider_subject, provider_email)
         VALUES ($1, 'password', $2::text, $2::citext) ON CONFLICT DO NOTHING`,
        [userId, target.rows[0].email],
      );
      await transaction.query(
        'UPDATE refresh_sessions SET revoked_at = now() WHERE user_id = $1 AND revoked_at IS NULL',
        [userId],
      );
      const notification = await transaction.query<{ id: string }>(
        `INSERT INTO notifications (user_id, title, body, type, reference_id)
         VALUES ($1, 'Your password was reset by an admin',
                 'If you did not request this, contact support immediately.',
                 'security_alert', $2) RETURNING id`,
        [userId, actorId],
      );
      await transaction.query(
        `INSERT INTO outbox_events (aggregate_type, aggregate_id, event_type, payload)
         VALUES ('notification', $1, 'notification.created', $2::jsonb)`,
        [
          notification.rows[0].id,
          JSON.stringify({
            notificationId: notification.rows[0].id,
            userId,
          }),
        ],
      );
      await this.audit(
        actorId,
        'user.reset_password',
        'profile',
        userId,
        null,
        {
          forced: true,
        },
        transaction,
      );
    });
  }

  async queuePasswordRecovery(
    actorId: string,
    userId: string,
    token: { tokenHash: Buffer; encryptedToken: Buffer; expiresAt: Date },
  ): Promise<void> {
    await this.database.transaction(async (transaction) => {
      const target = await transaction.query<{ email: string }>(
        `SELECT email::text FROM users
         WHERE id = $1 AND deleted_at IS NULL FOR UPDATE`,
        [userId],
      );
      if (!target.rows[0]) {
        throw new NotFoundException({
          code: 'USER_NOT_FOUND',
          message: 'User not found',
        });
      }
      await transaction.query(
        `UPDATE auth_action_tokens SET consumed_at = now()
         WHERE user_id = $1 AND purpose = 'password_recovery' AND consumed_at IS NULL`,
        [userId],
      );
      const action = await transaction.query<{ id: string }>(
        `INSERT INTO auth_action_tokens
           (user_id, purpose, token_hash, encrypted_token, expires_at)
         VALUES ($1, 'password_recovery', $2, $3, $4)
         RETURNING id`,
        [userId, token.tokenHash, token.encryptedToken, token.expiresAt],
      );
      await transaction.query(
        `INSERT INTO outbox_events (aggregate_type, aggregate_id, event_type, payload)
         VALUES ('auth_action_token', $1, 'auth.password_recovery.requested',
                 jsonb_build_object('tokenId', $1::uuid))`,
        [action.rows[0].id],
      );
      await this.audit(
        actorId,
        'user.request_password_reset',
        'profile',
        userId,
        null,
        { queued: true },
        transaction,
      );
    });
  }

  async setStatus(
    actorId: string,
    userId: string,
    status: string,
    reason: string,
  ): Promise<void> {
    await this.database.transaction(async (transaction) => {
      const before = await transaction.query<{ status: string }>(
        'SELECT status::text FROM users WHERE id = $1 FOR UPDATE',
        [userId],
      );
      if (!before.rows[0])
        throw new NotFoundException({
          code: 'USER_NOT_FOUND',
          message: 'User not found',
        });
      await transaction.query(
        `UPDATE users SET status = $2::account_status,
           token_version = token_version + CASE WHEN $2::text = 'active' THEN 0 ELSE 1 END,
           updated_at = now() WHERE id = $1`,
        [userId, status],
      );
      if (status !== 'active')
        await transaction.query(
          'UPDATE refresh_sessions SET revoked_at = now() WHERE user_id = $1 AND revoked_at IS NULL',
          [userId],
        );
      await this.audit(
        actorId,
        'user.set_status',
        'user',
        userId,
        { status: before.rows[0].status },
        { status, reason },
        transaction,
      );
    });
  }

  async setXp(
    actorId: string,
    userId: string,
    xp: number,
    level: number,
    completed: number,
    reason: string,
  ): Promise<void> {
    await this.database.transaction(async (transaction) => {
      const before = await transaction.query(
        'SELECT xp, level, quests_completed FROM profiles WHERE id = $1 FOR UPDATE',
        [userId],
      );
      if (!before.rows[0])
        throw new NotFoundException({
          code: 'PROFILE_NOT_FOUND',
          message: 'Profile not found',
        });
      await transaction.query(
        'UPDATE profiles SET xp = $2, level = $3, quests_completed = $4, updated_at = now() WHERE id = $1',
        [userId, xp, level, completed],
      );
      await this.audit(
        actorId,
        'user.set_xp',
        'profile',
        userId,
        before.rows[0],
        { xp, level, quests_completed: completed, reason },
        transaction,
      );
    });
  }

  async reports(status: string, limit: number, offset: number) {
    return (
      await this.database.query(
        `SELECT r.*, json_build_object('username', p.username::text, 'display_name', p.display_name) AS profiles,
              COALESCE(reported_user.id, submission_owner.id) AS reported_user_id,
              COALESCE(reported_user.username::text, submission_owner.username::text) AS reported_username
       FROM reports r JOIN profiles p ON p.id = r.reporter_id
       LEFT JOIN profiles reported_user
         ON r.reported_type = 'user' AND reported_user.id::text = r.reported_id
       LEFT JOIN submissions reported_submission
         ON r.reported_type = 'submission' AND reported_submission.id::text = r.reported_id
       LEFT JOIN profiles submission_owner ON submission_owner.id = reported_submission.user_id
       WHERE ($1 = 'all' OR r.status = $1) ORDER BY r.created_at DESC, r.id DESC LIMIT $2 OFFSET $3`,
        [status, limit, offset],
      )
    ).rows;
  }

  async reviewReport(
    actorId: string,
    id: string,
    status: string,
    note?: string,
  ): Promise<void> {
    await this.database.transaction(async (transaction) => {
      const before = await transaction.query(
        'SELECT status::text, admin_note FROM reports WHERE id = $1 FOR UPDATE',
        [id],
      );
      if (!before.rows[0]) {
        throw new NotFoundException({
          code: 'REPORT_NOT_FOUND',
          message: 'Report not found',
        });
      }
      await transaction.query(
        `UPDATE reports SET status = $2, admin_note = COALESCE($3, admin_note), reviewed_by = $4, reviewed_at = now()
         WHERE id = $1`,
        [id, status, note?.trim() || null, actorId],
      );
      await this.audit(
        actorId,
        'report.review',
        'report',
        id,
        before.rows[0],
        { status, admin_note: note?.trim() || before.rows[0].admin_note },
        transaction,
      );
      await transaction.query(
        `INSERT INTO outbox_events (aggregate_type, aggregate_id, event_type, payload)
         VALUES ('report', $1, 'report.reviewed', $2::jsonb)`,
        [id, JSON.stringify({ reportId: id, status })],
      );
    });
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
  async publicConfig() {
    return (
      await this.database.query(
        'SELECT key, value FROM app_config WHERE is_public ORDER BY key',
      )
    ).rows;
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
  async suggestions(status: string, limit: number, offset: number) {
    return (
      await this.database.query(
        `SELECT * FROM quest_suggestions WHERE ($1 = 'all' OR status = $1)
       ORDER BY created_at DESC LIMIT $2 OFFSET $3`,
        [status, limit, offset],
      )
    ).rows;
  }
  async reviewSuggestion(
    actorId: string,
    id: string,
    status: 'approved' | 'rejected',
    xpReward: number,
    durationHours: number,
  ) {
    return this.database.transaction(async (transaction) => {
      const suggestion = await transaction.query(
        `UPDATE quest_suggestions SET status = $2, reviewed_by = $3, reviewed_at = now()
         WHERE id = $1 AND status = 'pending' RETURNING *`,
        [id, status, actorId],
      );
      if (!suggestion.rows[0])
        throw new ConflictException({
          code: 'SUGGESTION_ALREADY_REVIEWED',
          message: 'Suggestion is missing or already reviewed',
        });
      let questId: string | null = null;
      if (status === 'approved') {
        const quest = await transaction.query<{ id: string }>(
          `INSERT INTO quests (title, description, category, difficulty, xp_reward, duration_hours, is_active, created_by)
           VALUES ($1, $2, $3, $4, $5, $6, true, $7) RETURNING id`,
          [
            suggestion.rows[0].title,
            suggestion.rows[0].description,
            suggestion.rows[0].category,
            suggestion.rows[0].difficulty,
            xpReward,
            durationHours,
            actorId,
          ],
        );
        questId = quest.rows[0].id;
      }
      await this.audit(
        actorId,
        `suggestion.${status}`,
        'quest_suggestion',
        id,
        null,
        { quest_id: questId },
        transaction,
      );
      return { ...suggestion.rows[0], quest_id: questId };
    });
  }

  private async audit(
    actorId: string,
    action: string,
    targetType: string,
    targetId: string | null,
    before: unknown,
    after: unknown,
    transaction: import('../../../infrastructure/database/database.service.js').DatabaseTransaction,
  ) {
    await transaction.query(
      `INSERT INTO admin_audit_log (actor_id, action, target_type, target_id, before_state, after_state)
       VALUES ($1, $2, $3, $4, $5::jsonb, $6::jsonb)`,
      [
        actorId,
        action,
        targetType,
        targetId,
        before === null ? null : JSON.stringify(before),
        after === null ? null : JSON.stringify(after),
      ],
    );
  }
}
