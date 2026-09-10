import { Injectable, ConflictException, NotFoundException } from '@nestjs/common';
import { DatabaseService } from '../../../infrastructure/database/database.service.js';
import { AdminRepositoryBase } from './admin-repository.base.js';

@Injectable()
export class AdminUsersRepository extends AdminRepositoryBase {
  constructor(database: DatabaseService) { super(database); }

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

  /// Edits the admin-editable profile fields in one audited transaction.
  /// The admin form saves identity and progression together, so splitting
  /// this into two calls could leave a rename applied with the XP change
  /// lost (or the reverse).

  async updateUserProfile(
    actorId: string,
    userId: string,
    input: {
      username?: string;
      displayName?: string;
      bio?: string;
      xp?: number;
      level?: number;
      questsCompleted?: number;
      reason: string;
    },
  ): Promise<void> {
    const assignments: string[] = [];
    const parameters: unknown[] = [userId];

    const push = (column: string, value: unknown) => {
      parameters.push(value);
      assignments.push(`${column} = $${parameters.length}`);
    };

    if (input.username !== undefined) push('username', input.username.trim().toLowerCase());
    if (input.displayName !== undefined) push('display_name', input.displayName.trim());
    if (input.bio !== undefined) push('bio', input.bio.trim() === '' ? null : input.bio.trim());
    if (input.xp !== undefined) push('xp', input.xp);
    if (input.level !== undefined) push('level', input.level);
    if (input.questsCompleted !== undefined) push('quests_completed', input.questsCompleted);

    if (assignments.length === 0) {
      throw new ConflictException({ code: 'NO_PROFILE_CHANGES', message: 'No fields to update' });
    }

    await this.database.transaction(async (transaction) => {
      const before = await transaction.query(
        `SELECT username::text, display_name, bio, xp, level, quests_completed
         FROM profiles WHERE id = $1 FOR UPDATE`,
        [userId],
      );
      if (!before.rows[0]) {
        throw new NotFoundException({ code: 'PROFILE_NOT_FOUND', message: 'Profile not found' });
      }
      try {
        await transaction.query(
          `UPDATE profiles SET ${assignments.join(', ')}, updated_at = now() WHERE id = $1`,
          parameters,
        );
      } catch (error) {
        if (
          typeof error === 'object' && error !== null && 'code' in error &&
          (error as { code?: unknown }).code === '23505'
        ) {
          throw new ConflictException({ code: 'USERNAME_TAKEN', message: 'That username is already taken' });
        }
        throw error;
      }
      await this.audit(
        actorId,
        'user.update_profile',
        'profile',
        userId,
        before.rows[0],
        { ...input },
        transaction,
      );
    });
  }

  async setXp(
    actorId: string,
    userId: string,
    xp: number,
    level: number | undefined,
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
      // Level is derived, not taken from the caller. It used to be an
      // independent field with nothing checking the two agreed, so a
      // mismatched pair made xp_to_next_level negative and the profile panel
      // render totals like "300 / 200". Same formula the approve path and the
      // admin UI use.
      const derivedLevel = Math.max(1, Math.floor(xp / 100) + 1);
      await transaction.query(
        'UPDATE profiles SET xp = $2, level = $3, quests_completed = $4, updated_at = now() WHERE id = $1',
        [userId, xp, derivedLevel, completed],
      );
      await this.audit(
        actorId,
        'user.set_xp',
        'profile',
        userId,
        before.rows[0],
        {
          xp,
          level: derivedLevel,
          quests_completed: completed,
          reason,
          // Recorded when the caller asked for something else, so the audit
          // shows what was requested as well as what was stored.
          ...(level !== undefined && level !== derivedLevel
            ? { requested_level: level }
            : {}),
        },
        transaction,
      );
    });
  }

  async xpAudit(limit: number, offset: number) {
    return (
      await this.database.query(
        `SELECT p.id AS user_id, p.username::text, p.display_name,
                p.xp AS current_xp, p.level AS current_level,
                p.quests_completed AS current_quests,
                coalesce(e.expected_xp, 0)::int AS expected_xp,
                coalesce(e.expected_quests, 0)::int AS expected_quests,
                ((coalesce(e.expected_xp, 0) / 100) + 1)::int AS expected_level
         FROM profiles p
         -- Expected XP comes from the LEDGER — the amount actually awarded and
         -- recorded on each submission — not from the quest catalogue.
         --
         -- This used to be sum(quests.xp_reward) over user_quests where status
         -- = 'approved', which is wrong in three ways at once: a quest's
         -- xp_reward can be edited after approval, user_quests.status stays
         -- 'approved' after a takedown (so a correctly revoked award still
         -- counted), and a Quest-of-the-Day bonus is never in the catalogue
         -- figure. On live data that flagged three of five users whose stored
         -- counter and ledger agreed exactly -- and the dashboard's Reconcile
         -- button writes this figure into profiles.xp, so it re-awarded XP for
         -- deleted posts and confiscated legitimately earned QOTD bonuses.
         LEFT JOIN (
           SELECT s.user_id,
                  sum(s.xp_awarded_amount)::int AS expected_xp,
                  count(*)::int AS expected_quests
           FROM submissions s
           WHERE s.xp_awarded
           GROUP BY s.user_id
         ) e ON e.user_id = p.id
         ORDER BY p.xp DESC, p.id
         LIMIT $1 OFFSET $2`,
        [Math.min(Math.max(limit, 1), 500), Math.max(offset, 0)],
      )
    ).rows;
  }
}
