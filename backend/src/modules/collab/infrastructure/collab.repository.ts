import { ConflictException, ForbiddenException, Injectable, NotFoundException } from '@nestjs/common';
import { DatabaseService, type DatabaseTransaction } from '../../../infrastructure/database/database.service.js';

interface GroupRow {
  readonly id: string;
  readonly quest_id: string;
  readonly creator_id: string;
  readonly code: string;
  readonly mode: 'with' | 'versus';
  readonly status: string;
  readonly max_members: number;
  readonly expires_at: Date;
}

@Injectable()
export class CollabRepository {
  constructor(private readonly database: DatabaseService) {}

  async create(userId: string, userQuestId: string, mode: 'with' | 'versus') {
    return this.database.transaction(async (transaction) => {
      const assignment = await transaction.query<{ quest_id: string; expires_at: Date }>(
        `SELECT quest_id, expires_at FROM user_quests
         WHERE id = $1 AND user_id = $2 AND status IN ('assigned', 'submitted') FOR UPDATE`,
        [userQuestId, userId],
      );
      if (!assignment.rows[0]) {
        throw new NotFoundException({ code: 'ACTIVE_QUEST_NOT_FOUND', message: 'No active quest found or not your quest' });
      }
      const existing = await transaction.query<GroupRow>(
        `SELECT g.* FROM collab_groups g JOIN collab_group_members m ON m.group_id = g.id
         WHERE m.user_quest_id = $1 LIMIT 1`,
        [userQuestId],
      );
      if (existing.rows[0]) return this.groupSummary(existing.rows[0]);

      let group: GroupRow | undefined;
      for (let attempt = 0; attempt < 5 && !group; attempt += 1) {
        try {
          group = (await transaction.query<GroupRow>(
            `INSERT INTO collab_groups (quest_id, creator_id, code, mode, expires_at)
             VALUES ($1, $2, upper(substr(encode(gen_random_bytes(4), 'hex'), 1, 6)), $3, $4)
             RETURNING *`,
            [assignment.rows[0].quest_id, userId, mode, assignment.rows[0].expires_at],
          )).rows[0];
        } catch (error) {
          if (!(typeof error === 'object' && error !== null && 'code' in error && error.code === '23505')) throw error;
        }
      }
      if (!group) throw new ConflictException({ code: 'COLLAB_CODE_COLLISION', message: 'Could not allocate a group code; try again' });
      await transaction.query(
        'INSERT INTO collab_group_members (group_id, user_id, user_quest_id) VALUES ($1, $2, $3)',
        [group.id, userId, userQuestId],
      );
      return this.groupSummary(group);
    });
  }

  async preview(code: string) {
    const result = await this.database.query(
      `SELECT g.id AS group_id, g.code::text, g.mode::text, g.status::text,
              count(m.id)::integer AS member_count, g.max_members, g.expires_at,
              COALESCE(json_agg(json_build_object(
                'user_id', p.id, 'username', p.username::text,
                'display_name', p.display_name, 'avatar_url', p.avatar_url
              ) ORDER BY m.joined_at) FILTER (WHERE m.id IS NOT NULL), '[]'::json) AS members,
              q.title AS quest_title, q.description AS quest_description,
              q.category AS quest_category, q.difficulty AS quest_difficulty,
              q.xp_reward AS quest_xp_reward, q.duration_hours AS quest_duration_hours,
              cp.username::text AS creator_username, cp.display_name AS creator_display_name,
              cp.avatar_url AS creator_avatar_url
       FROM collab_groups g JOIN quests q ON q.id = g.quest_id
       JOIN profiles cp ON cp.id = g.creator_id
       LEFT JOIN collab_group_members m ON m.group_id = g.id
       LEFT JOIN profiles p ON p.id = m.user_id
       WHERE g.code = upper($1) AND g.status = 'open' AND g.expires_at > now()
       GROUP BY g.id, q.id, cp.id`,
      [code],
    );
    if (!result.rows[0]) throw new NotFoundException({ code: 'COLLAB_GROUP_NOT_FOUND', message: 'Group not found or expired' });
    return result.rows[0];
  }

  async join(userId: string, code: string) {
    return this.database.transaction(async (transaction) => {
      const groupResult = await transaction.query<GroupRow>(
        `SELECT * FROM collab_groups
         WHERE code = upper($1) AND status = 'open' AND expires_at > now() FOR UPDATE`,
        [code],
      );
      const group = groupResult.rows[0];
      if (!group) throw new NotFoundException({ code: 'COLLAB_GROUP_NOT_FOUND', message: 'Group not found or expired' });
      const members = await transaction.query<{ user_id: string }>(
        'SELECT user_id FROM collab_group_members WHERE group_id = $1 ORDER BY joined_at FOR UPDATE',
        [group.id],
      );
      if (members.rows.some((member) => member.user_id === userId)) {
        throw new ConflictException({ code: 'ALREADY_COLLAB_MEMBER', message: 'You are already in this group' });
      }
      if (members.rows.length >= group.max_members) {
        throw new ConflictException({ code: 'COLLAB_GROUP_FULL', message: `Group is full (${members.rows.length}/${group.max_members} members)` });
      }
      const blocked = await transaction.query(
        `SELECT 1 FROM blocked_users b
         WHERE (b.blocker_id = $1 AND b.blocked_id = ANY($2::uuid[]))
            OR (b.blocked_id = $1 AND b.blocker_id = ANY($2::uuid[])) LIMIT 1`,
        [userId, members.rows.map((member) => member.user_id)],
      );
      if (blocked.rowCount) throw new ForbiddenException({ code: 'COLLAB_BLOCKED', message: 'This group is unavailable' });
      const active = await transaction.query("SELECT 1 FROM user_quests WHERE user_id = $1 AND status = 'assigned' LIMIT 1", [userId]);
      if (active.rowCount) {
        throw new ConflictException({ code: 'ACTIVE_QUEST_EXISTS', message: 'You already have an active quest. Abandon it first.' });
      }
      const assignment = await transaction.query<{ id: string }>(
        `INSERT INTO user_quests (user_id, quest_id, status, assigned_at, expires_at)
         VALUES ($1, $2, 'assigned', now(), $3) RETURNING id`,
        [userId, group.quest_id, group.expires_at],
      );
      await transaction.query(
        'INSERT INTO collab_group_members (group_id, user_id, user_quest_id) VALUES ($1, $2, $3)',
        [group.id, userId, assignment.rows[0].id],
      );
      if (members.rows.length + 1 >= group.max_members) {
        await transaction.query("UPDATE collab_groups SET status = 'closed' WHERE id = $1", [group.id]);
      }
      const actor = await this.actorName(userId, transaction);
      const notifications = await transaction.query<{ id: string; user_id: string }>(
        `INSERT INTO notifications (user_id, title, body, type, reference_id, actor_id)
         SELECT user_id, $2, $3, 'collab_joined', $1, $4
         FROM collab_group_members WHERE group_id = $1 AND user_id <> $4
         RETURNING id, user_id`,
        [group.id, `${actor} signed up for the mission. 🤝`, "You've got a teammate on this one. Go win it together.", userId],
      );
      for (const notification of notifications.rows) await this.emitNotification(notification, transaction);
      return {
        group_id: group.id,
        user_quest_id: assignment.rows[0].id,
        quest_id: group.quest_id,
        expires_at: group.expires_at,
        mode: group.mode,
      };
    });
  }

  async status(userId: string, userQuestId: string) {
    const assignment = await this.database.query('SELECT 1 FROM user_quests WHERE id = $1 AND user_id = $2', [userQuestId, userId]);
    if (!assignment.rowCount) throw new NotFoundException({ code: 'USER_QUEST_NOT_FOUND', message: 'Quest assignment not found' });
    const group = await this.database.query<GroupRow>(
      `SELECT g.* FROM collab_groups g JOIN collab_group_members mine ON mine.group_id = g.id
       WHERE mine.user_quest_id = $1 AND mine.user_id = $2`,
      [userQuestId, userId],
    );
    if (!group.rows[0]) return { is_collab: false };
    const members = await this.database.query(
      `SELECT p.id AS user_id, p.username::text, p.display_name, p.avatar_url,
              uq.status::text AS quest_status, s.status::text AS submission_status,
              m.submission_time_seconds, COALESCE(v.count, 0)::integer AS vote_count
       FROM collab_group_members m JOIN profiles p ON p.id = m.user_id
       JOIN user_quests uq ON uq.id = m.user_quest_id
       LEFT JOIN submissions s ON s.user_quest_id = m.user_quest_id
       LEFT JOIN (
         SELECT submission_id, count(*) AS count FROM collab_votes
         WHERE group_id = $1 GROUP BY submission_id
       ) v ON v.submission_id = s.id
       WHERE m.group_id = $1 ORDER BY m.joined_at`,
      [group.rows[0].id],
    );
    return {
      is_collab: true,
      group_id: group.rows[0].id,
      mode: group.rows[0].mode,
      status: group.rows[0].status,
      code: group.rows[0].code,
      max_members: group.rows[0].max_members,
      expires_at: group.rows[0].expires_at,
      members: members.rows,
    };
  }

  async abandon(userId: string, userQuestId: string): Promise<void> {
    const result = await this.database.query(
      `UPDATE user_quests SET status = 'expired', completed_at = now(), version = version + 1
       WHERE id = $1 AND user_id = $2 AND status = 'assigned'`,
      [userQuestId, userId],
    );
    if (!result.rowCount) throw new ConflictException({ code: 'QUEST_NOT_ABANDONABLE', message: 'Cannot abandon: quest not found or not in assigned status' });
  }

  async vote(userId: string, groupId: string, submissionId: string): Promise<void> {
    await this.database.transaction(async (transaction) => {
      await transaction.query('SELECT pg_advisory_xact_lock(hashtextextended($1, 2))', [userId]);
      const group = await transaction.query('SELECT 1 FROM collab_groups WHERE id = $1', [groupId]);
      if (!group.rowCount) throw new NotFoundException({ code: 'COLLAB_GROUP_NOT_FOUND', message: 'Group not found' });
      const eligible = await transaction.query(
        `SELECT 1 FROM collab_group_members m JOIN submissions s ON s.user_quest_id = m.user_quest_id
         WHERE m.group_id = $1 AND s.id = $2 AND s.status = 'approved'`,
        [groupId, submissionId],
      );
      if (!eligible.rowCount) throw new ConflictException({ code: 'COLLAB_VOTE_INELIGIBLE', message: 'Submission is not eligible for voting' });
      const recent = await transaction.query<{ count: number }>(
        `SELECT count(*)::integer AS count FROM collab_votes
         WHERE voter_id = $1 AND created_at > now() - interval '1 hour'`,
        [userId],
      );
      if (recent.rows[0].count >= 60) throw new ConflictException({ code: 'COLLAB_VOTE_RATE_LIMIT', message: 'Vote rate limit exceeded — try again later' });
      await transaction.query(
        `INSERT INTO collab_votes (group_id, voter_id, submission_id) VALUES ($1, $2, $3)
         ON CONFLICT (group_id, voter_id, submission_id) DO NOTHING`,
        [groupId, userId, submissionId],
      );
    });
  }

  async unvote(userId: string, groupId: string, submissionId: string): Promise<void> {
    await this.database.query(
      'DELETE FROM collab_votes WHERE group_id = $1 AND voter_id = $2 AND submission_id = $3',
      [groupId, userId, submissionId],
    );
  }

  private groupSummary(group: GroupRow) {
    return { group_id: group.id, code: group.code, mode: group.mode, expires_at: group.expires_at };
  }

  private async actorName(userId: string, transaction: DatabaseTransaction): Promise<string> {
    const result = await transaction.query<{ name: string }>(
      `SELECT COALESCE(NULLIF(display_name, ''), username::text, 'Someone') AS name FROM profiles WHERE id = $1`,
      [userId],
    );
    return result.rows[0]?.name ?? 'Someone';
  }

  private async emitNotification(notification: { id: string; user_id: string }, transaction: DatabaseTransaction): Promise<void> {
    await transaction.query(
      `INSERT INTO outbox_events (aggregate_type, aggregate_id, event_type, payload)
       VALUES ('notification', $1, 'notification.created', $2::jsonb)`,
      [notification.id, JSON.stringify({ notificationId: notification.id, userId: notification.user_id })],
    );
  }
}
