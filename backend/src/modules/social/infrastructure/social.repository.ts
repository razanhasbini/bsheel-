import { ConflictException, ForbiddenException, Injectable, NotFoundException } from '@nestjs/common';
import { DatabaseService, type DatabaseTransaction } from '../../../infrastructure/database/database.service.js';
import { socialNotificationTemplates as copy } from '../../notifications/domain/social-notification.templates.js';
import { insertNotificationBatch, type NotificationInsert } from '../../notifications/infrastructure/notification-batch.js';

@Injectable()
export class SocialRepository {
  constructor(private readonly database: DatabaseService) {}

  /**
   * Refuses an interaction when either party has blocked the other.
   *
   * Blocking used to be enforced in exactly two places — `follow` and the feed
   * query — so a blocked account could still vote on, comment on and
   * @-mention the person who blocked them, and the notification arrived in
   * that person's inbox with the blocked user's name on it. That is precisely
   * the harassment vector blocking exists to close, so the check belongs on
   * every write path, not on the ones somebody remembered.
   *
   * Runs inside the caller's transaction so the check and the write cannot be
   * separated by a concurrent block.
   */
  private async assertNotBlocked(
    viewerId: string,
    otherId: string,
    transaction: DatabaseTransaction,
  ): Promise<void> {
    if (viewerId === otherId) return;
    const blocked = await transaction.query(
      `SELECT 1 FROM blocked_users
       WHERE (blocker_id = $1 AND blocked_id = $2) OR (blocker_id = $2 AND blocked_id = $1)`,
      [viewerId, otherId],
    );
    if (blocked.rowCount) {
      throw new ForbiddenException({
        code: 'INTERACTION_BLOCKED',
        message: 'This interaction is not allowed',
      });
    }
  }

  async getVote(userId: string, submissionId: string) {
    return (await this.database.query(
      'SELECT id, submission_id, user_id, type::text, created_at FROM reactions WHERE submission_id = $1 AND user_id = $2',
      [submissionId, userId],
    )).rows[0] ?? null;
  }

  async vote(userId: string, submissionId: string, type: 'upvote' | 'downvote') {
    return this.database.transaction(async (transaction) => {
      const submissionResult = await transaction.query<{ user_id: string }>(
        `SELECT user_id FROM submissions WHERE id = $1 AND status = 'approved'
         AND visibility = 'visible' AND deleted_at IS NULL`,
        [submissionId],
      );
      const submission = submissionResult.rows[0];
      if (!submission) throw new NotFoundException({ code: 'POST_NOT_FOUND', message: 'Post not found' });
      if (submission.user_id === userId) throw new ForbiddenException({ code: 'SELF_REACTION', message: 'You cannot react to your own submission' });
      await this.assertNotBlocked(userId, submission.user_id, transaction);
      const result = await transaction.query(
        `INSERT INTO reactions (submission_id, user_id, type) VALUES ($1, $2, $3)
         ON CONFLICT (submission_id, user_id) DO UPDATE SET type = EXCLUDED.type
         RETURNING id, submission_id, user_id, type::text, created_at, (xmax = 0) AS inserted`,
        [submissionId, userId, type],
      );
      if (result.rows[0].inserted) await this.reactionNotifications(userId, submission.user_id, submissionId, transaction);
      await this.emit('social.reaction.changed', submissionId, {
        submissionId,
        userId,
        type,
      }, transaction);
      return result.rows[0];
    });
  }

  async removeVote(userId: string, submissionId: string): Promise<void> {
    await this.database.transaction(async (transaction) => {
      const result = await transaction.query(
        'DELETE FROM reactions WHERE submission_id = $1 AND user_id = $2 RETURNING id',
        [submissionId, userId],
      );
      if (result.rowCount) {
        await this.emit('social.reaction.changed', submissionId, {
          submissionId,
          userId,
          type: null,
        }, transaction);
      }
    });
  }

  /**
   * Takes the viewer, because a comment list is a per-viewer view.
   *
   * Two things were missing here that every sibling query already had: a
   * block predicate (so a blocked account's text stayed fully readable by the
   * person who blocked them) and a guard on the parent submission (so
   * discussion on a moderator-removed post was still served by direct id,
   * even though `POST`ing to the same path correctly 404s).
   */
  async listComments(viewerId: string, submissionId: string, limit: number, offset: number) {
    return (await this.database.query(
      `SELECT c.id, c.submission_id, c.user_id, c.body, c.created_at, c.parent_id,
              p.username::text, p.display_name, p.avatar_url
       FROM comments c JOIN profiles p ON p.id = c.user_id
       JOIN submissions s ON s.id = c.submission_id
       WHERE c.submission_id = $1
         AND s.status = 'approved' AND s.visibility = 'visible' AND s.deleted_at IS NULL
         AND NOT EXISTS (SELECT 1 FROM blocked_users b
                         WHERE (b.blocker_id = $4 AND b.blocked_id = c.user_id)
                            OR (b.blocker_id = c.user_id AND b.blocked_id = $4))
       ORDER BY c.created_at, c.id LIMIT $2 OFFSET $3`,
      [submissionId, Math.min(Math.max(limit, 1), 200), Math.max(offset, 0), viewerId],
    )).rows;
  }

  async addComment(userId: string, submissionId: string, body: string, parentId?: string) {
    return this.database.transaction(async (transaction) => {
      const submission = await transaction.query<{ user_id: string; quest_title: string }>(
        `SELECT s.user_id, q.title AS quest_title FROM submissions s
         JOIN user_quests uq ON uq.id = s.user_quest_id JOIN quests q ON q.id = uq.quest_id
         WHERE s.id = $1 AND s.status = 'approved' AND s.visibility = 'visible' AND s.deleted_at IS NULL`,
        [submissionId],
      );
      if (!submission.rows[0]) throw new NotFoundException({ code: 'POST_NOT_FOUND', message: 'Post not found' });
      await this.assertNotBlocked(userId, submission.rows[0].user_id, transaction);
      if (parentId) {
        const parent = await transaction.query('SELECT 1 FROM comments WHERE id = $1 AND submission_id = $2', [parentId, submissionId]);
        if (!parent.rowCount) throw new ConflictException({ code: 'INVALID_COMMENT_PARENT', message: 'Reply parent belongs to another post or does not exist' });
      }
      const result = await transaction.query(
        `INSERT INTO comments (submission_id, user_id, body, parent_id)
         VALUES ($1, $2, $3, $4) RETURNING id, submission_id, user_id, body, created_at, parent_id`,
        [submissionId, userId, body.trim(), parentId ?? null],
      );
      await this.commentNotifications(userId, submissionId, submission.rows[0].user_id, submission.rows[0].quest_title, body.trim(), transaction);
      await this.emit('social.comment.changed', submissionId, {
        submissionId,
        userId,
        commentId: result.rows[0].id,
        operation: 'created',
      }, transaction);
      return result.rows[0];
    });
  }

  async deleteComment(userId: string, role: string, commentId: string): Promise<void> {
    await this.database.transaction(async (transaction) => {
      const result = await transaction.query<{ submission_id: string }>(
        `DELETE FROM comments WHERE id = $1 AND (user_id = $2 OR $3 IN ('moderator', 'super_admin'))
         RETURNING submission_id`,
        [commentId, userId, role],
      );
      if (!result.rows[0]) throw new NotFoundException({ code: 'COMMENT_NOT_FOUND', message: 'Comment not found' });
      await this.emit('social.comment.changed', result.rows[0].submission_id, {
        submissionId: result.rows[0].submission_id,
        userId,
        commentId,
        operation: 'deleted',
      }, transaction);
    });
  }

  async isFollowing(userId: string, targetId: string): Promise<boolean> {
    const result = await this.database.query('SELECT 1 FROM follows WHERE follower_id = $1 AND following_id = $2', [userId, targetId]);
    return Boolean(result.rowCount);
  }

  async follow(userId: string, targetId: string): Promise<string> {
    if (userId === targetId) throw new ConflictException({ code: 'SELF_FOLLOW', message: 'You cannot follow yourself' });
    return this.database.transaction(async (transaction) => {
      const target = await transaction.query('SELECT 1 FROM profiles WHERE id = $1', [targetId]);
      if (!target.rowCount) throw new NotFoundException({ code: 'PROFILE_NOT_FOUND', message: 'Profile not found' });
      const blocked = await transaction.query(
        `SELECT 1 FROM blocked_users WHERE (blocker_id = $1 AND blocked_id = $2) OR (blocker_id = $2 AND blocked_id = $1)`,
        [userId, targetId],
      );
      if (blocked.rowCount) throw new ForbiddenException({ code: 'FOLLOW_BLOCKED', message: 'This follow relationship is not allowed' });
      const result = await transaction.query<{ id: string; inserted: boolean }>(
        `INSERT INTO follows (follower_id, following_id) VALUES ($1, $2)
         ON CONFLICT (follower_id, following_id) DO UPDATE SET follower_id = EXCLUDED.follower_id
         RETURNING id, (xmax = 0) AS inserted`,
        [userId, targetId],
      );
      if (result.rows[0].inserted) {
        const actor = await this.actorName(userId, transaction);
        await this.notification(targetId, ...copy.followed(actor), 'new_follower', userId, userId, transaction);
      }
      await this.emit('social.follow.changed', result.rows[0].id, {
        userId,
        targetUserId: targetId,
        following: true,
      }, transaction);
      return result.rows[0].id;
    });
  }

  async unfollow(userId: string, targetId: string): Promise<void> {
    await this.database.transaction(async (transaction) => {
      const result = await transaction.query<{ id: string }>(
        'DELETE FROM follows WHERE follower_id = $1 AND following_id = $2 RETURNING id',
        [userId, targetId],
      );
      if (result.rows[0]) {
        await this.emit('social.follow.changed', result.rows[0].id, {
          userId,
          targetUserId: targetId,
          following: false,
        }, transaction);
      }
    });
  }

  async connections(userId: string, followers: boolean, limit: number, offset: number) {
    const result = await this.database.query(
      `SELECT p.id, p.username::text, p.display_name, p.avatar_url
       FROM follows f JOIN profiles p ON p.id = CASE WHEN $2 THEN f.follower_id ELSE f.following_id END
       WHERE CASE WHEN $2 THEN f.following_id ELSE f.follower_id END = $1
       ORDER BY f.created_at DESC LIMIT $3 OFFSET $4`,
      [userId, followers, Math.min(Math.max(limit, 1), 100), Math.max(offset, 0)],
    );
    return result.rows;
  }

  async followCounts(userId: string) {
    const result = await this.database.query<{ followers: number; following: number }>(
      `SELECT count(*) FILTER (WHERE following_id = $1)::integer AS followers,
              count(*) FILTER (WHERE follower_id = $1)::integer AS following FROM follows
       WHERE follower_id = $1 OR following_id = $1`,
      [userId],
    );
    return result.rows[0];
  }

  async block(userId: string, targetId: string, reason: string): Promise<void> {
    if (userId === targetId) throw new ConflictException({ code: 'SELF_BLOCK', message: 'Cannot block yourself' });
    await this.database.transaction(async (transaction) => {
      const exists = await transaction.query('SELECT 1 FROM profiles WHERE id = $1', [targetId]);
      if (!exists.rowCount) throw new NotFoundException({ code: 'PROFILE_NOT_FOUND', message: 'Profile not found' });
      await transaction.query('INSERT INTO blocked_users (blocker_id, blocked_id) VALUES ($1, $2) ON CONFLICT DO NOTHING', [userId, targetId]);
      const report = await transaction.query<{ id: string }>(
        `INSERT INTO reports (reporter_id, reported_type, reported_id, reason)
         VALUES ($1, 'user', $2, $3) ON CONFLICT DO NOTHING RETURNING id`,
        [userId, targetId, reason.trim() || 'Blocked by user'],
      );
      await transaction.query(
        'DELETE FROM follows WHERE (follower_id = $1 AND following_id = $2) OR (follower_id = $2 AND following_id = $1)',
        [userId, targetId],
      );
      if (report.rows[0]) {
        await this.notifyAdminsOfReport(report.rows[0].id, ...copy.blocked(reason), transaction);
        await this.emit('report.created', report.rows[0].id, { reportId: report.rows[0].id }, transaction);
      }
      await this.emit('social.follow.changed', targetId, {
        userId,
        targetUserId: targetId,
        following: false,
      }, transaction);
    });
  }

  async unblock(userId: string, targetId: string): Promise<void> {
    await this.database.query('DELETE FROM blocked_users WHERE blocker_id = $1 AND blocked_id = $2', [userId, targetId]);
  }

  async blockedUsers(userId: string, limit: number, offset: number) {
    return (await this.database.query(
      `SELECT p.id, p.username::text, p.display_name, p.avatar_url, b.created_at AS blocked_at
       FROM blocked_users b JOIN profiles p ON p.id = b.blocked_id
       WHERE b.blocker_id = $1
       ORDER BY b.created_at DESC, b.id DESC LIMIT $2 OFFSET $3`,
      [userId, Math.min(Math.max(limit, 1), 100), Math.max(offset, 0)],
    )).rows;
  }

  async report(userId: string, reportedType: string, reportedId: string, reason: string): Promise<string> {
    try {
      return await this.database.transaction(async (transaction) => {
        const result = await transaction.query<{ id: string }>(
          `INSERT INTO reports (reporter_id, reported_type, reported_id, reason)
           VALUES ($1, $2, $3, $4) RETURNING id`,
          [userId, reportedType, reportedId, reason.trim()],
        );
        await this.notifyAdminsOfReport(result.rows[0].id, ...copy.reported(reportedType, reason), transaction);
        await this.emit('report.created', result.rows[0].id, { reportId: result.rows[0].id }, transaction);
        return result.rows[0].id;
      });
    } catch (error) {
      if (typeof error === 'object' && error !== null && 'code' in error && error.code === '23505') {
        throw new ConflictException({ code: 'DUPLICATE_REPORT', message: 'You have already reported this content' });
      }
      throw error;
    }
  }

  async setSavedPost(userId: string, submissionId: string, saved: boolean): Promise<void> {
    if (saved) {
      const result = await this.database.query(
        `INSERT INTO saved_posts (user_id, submission_id)
         SELECT $1, id FROM submissions
         WHERE id = $2 AND status = 'approved' AND visibility = 'visible' AND deleted_at IS NULL
         ON CONFLICT DO NOTHING`,
        [userId, submissionId],
      );
      if (!result.rowCount) {
        const existing = await this.database.query('SELECT 1 FROM saved_posts WHERE user_id = $1 AND submission_id = $2', [userId, submissionId]);
        if (!existing.rowCount) throw new NotFoundException({ code: 'POST_NOT_FOUND', message: 'Post not found' });
      }
    }
    else await this.database.query('DELETE FROM saved_posts WHERE user_id = $1 AND submission_id = $2', [userId, submissionId]);
  }

  async isPostSaved(userId: string, submissionId: string): Promise<boolean> {
    const result = await this.database.query('SELECT 1 FROM saved_posts WHERE user_id = $1 AND submission_id = $2', [userId, submissionId]);
    return Boolean(result.rowCount);
  }

  async setSavedQuest(userId: string, questId: string, saved: boolean): Promise<void> {
    if (saved) {
      const result = await this.database.query(
        `INSERT INTO saved_quests (user_id, quest_id)
         SELECT $1, id FROM quests WHERE id = $2
         ON CONFLICT DO NOTHING`,
        [userId, questId],
      );
      if (!result.rowCount) {
        const existing = await this.database.query('SELECT 1 FROM saved_quests WHERE user_id = $1 AND quest_id = $2', [userId, questId]);
        if (!existing.rowCount) throw new NotFoundException({ code: 'QUEST_NOT_FOUND', message: 'Quest not found' });
      }
    }
    else await this.database.query('DELETE FROM saved_quests WHERE user_id = $1 AND quest_id = $2', [userId, questId]);
  }

  async isQuestSaved(userId: string, questId: string): Promise<boolean> {
    const result = await this.database.query('SELECT 1 FROM saved_quests WHERE user_id = $1 AND quest_id = $2', [userId, questId]);
    return Boolean(result.rowCount);
  }

  async savedQuests(userId: string, limit: number, offset: number) {
    return (await this.database.query(
      `SELECT sq.id AS saved_id, sq.created_at AS saved_at, q.*
       FROM saved_quests sq JOIN quests q ON q.id = sq.quest_id
       WHERE sq.user_id = $1
       ORDER BY sq.created_at DESC, sq.id DESC LIMIT $2 OFFSET $3`,
      [userId, Math.min(Math.max(limit, 1), 100), Math.max(offset, 0)],
    )).rows;
  }

  async savedPosts(userId: string, limit: number, offset: number) {
    return (await this.database.query(
      `SELECT sp.id AS saved_id, sp.created_at AS saved_at, s.id AS submission_id, s.media_url,
              s.media_type::text, s.visibility::text, s.status::text, q.id AS quest_id,
              q.title AS quest_title, q.description AS quest_description, q.category AS quest_category,
              q.xp_reward, p.id AS author_id, p.username::text AS author_username,
              p.display_name AS author_display_name, p.avatar_url AS author_avatar_url
       FROM saved_posts sp JOIN submissions s ON s.id = sp.submission_id
       JOIN user_quests uq ON uq.id = s.user_quest_id JOIN quests q ON q.id = uq.quest_id
       JOIN profiles p ON p.id = s.user_id
       WHERE sp.user_id = $1 AND s.status = 'approved'
         AND s.visibility = 'visible' AND s.deleted_at IS NULL
         -- Saved posts survived a block: a post you saved before blocking its
         -- author stayed in your list. Status/visibility were filtered here
         -- already; the block was the one predicate missing.
         AND NOT EXISTS (SELECT 1 FROM blocked_users b
                         WHERE (b.blocker_id = $1 AND b.blocked_id = s.user_id)
                            OR (b.blocker_id = s.user_id AND b.blocked_id = $1))
       ORDER BY sp.created_at DESC, sp.id DESC LIMIT $2 OFFSET $3`,
      [userId, Math.min(Math.max(limit, 1), 100), Math.max(offset, 0)],
    )).rows;
  }

  private async reactionNotifications(actorId: string, ownerId: string, submissionId: string, transaction: DatabaseTransaction): Promise<void> {
    const actor = await this.actorName(actorId, transaction);
    await this.notification(ownerId, ...copy.reacted(actor), 'reaction_received', submissionId, actorId, transaction);
    const total = await transaction.query<{ count: number }>('SELECT count(*)::integer AS count FROM reactions WHERE submission_id = $1', [submissionId]);
    const milestone = copy.milestone(total.rows[0].count);
    if (milestone) await this.notification(ownerId, ...milestone, 'reaction_milestone', submissionId, null, transaction);
  }

  /**
   * Drops recipients on either side of a block.
   *
   * Applied at the fan-out rather than at each `add(...)` so a future
   * notification type cannot forget it. `vote` and `addComment` already refuse
   * a blocked actor outright; this is the second line for the recipients who
   * are neither party to that check — a thread participant or an @-mentioned
   * user who blocked the commenter. Without it, a mention delivered the
   * blocked user's display name and comment excerpt straight to the blocker.
   */
  private async withoutBlockedRecipients(
    actorId: string,
    notifications: readonly NotificationInsert[],
    transaction: DatabaseTransaction,
  ): Promise<NotificationInsert[]> {
    if (notifications.length === 0) return [];
    const recipients = [...new Set(notifications.map((notification) => notification.userId))];
    const blocked = await transaction.query<{ other_id: string }>(
      `SELECT CASE WHEN blocker_id = $1 THEN blocked_id ELSE blocker_id END AS other_id
       FROM blocked_users
       WHERE (blocker_id = $1 AND blocked_id = ANY($2::uuid[]))
          OR (blocked_id = $1 AND blocker_id = ANY($2::uuid[]))`,
      [actorId, recipients],
    );
    if (!blocked.rowCount) return [...notifications];
    const excluded = new Set(blocked.rows.map((row) => row.other_id));
    return notifications.filter((notification) => !excluded.has(notification.userId));
  }

  private async commentNotifications(actorId: string, submissionId: string, ownerId: string, questTitle: string, body: string, transaction: DatabaseTransaction): Promise<void> {
    const actor = await this.actorName(actorId, transaction);
    const notifications: NotificationInsert[] = [];
    const add = (userId: string, type: string, [title, text]: readonly [string, string]) => {
      notifications.push({ userId, type, title, body: text, referenceId: submissionId, actorId });
    };
    const mentionNames = [...body.matchAll(/@([\p{L}\p{N}_]{3,30})/gu)].map((match) => match[1].toLowerCase());
    const mentions = mentionNames.length
      ? (await transaction.query<{ id: string }>('SELECT id FROM profiles WHERE lower(username::text) = ANY($1::text[])', [mentionNames])).rows.map((row) => row.id)
      : [];
    const excluded = new Set([actorId, ...mentions]);
    if (ownerId !== actorId && !excluded.has(ownerId)) {
      add(ownerId, 'new_comment', copy.comment(actor, body));
    }
    const participants = await transaction.query<{ user_id: string }>('SELECT DISTINCT user_id FROM comments WHERE submission_id = $1', [submissionId]);
    for (const participant of participants.rows) {
      if (participant.user_id === ownerId || excluded.has(participant.user_id)) continue;
      excluded.add(participant.user_id);
      add(participant.user_id, 'comment_reply', copy.reply(actor, body));
    }
    for (const mentionedId of mentions) {
      if (mentionedId === actorId) continue;
      add(mentionedId, 'mention', copy.mention(actor, questTitle, body));
    }
    await insertNotificationBatch(
      transaction,
      await this.withoutBlockedRecipients(actorId, notifications, transaction),
    );
  }

  private async actorName(id: string, transaction: DatabaseTransaction): Promise<string> {
    const result = await transaction.query<{ name: string }>(
      `SELECT COALESCE(NULLIF(display_name, ''), username::text, 'Someone') AS name FROM profiles WHERE id = $1`, [id],
    );
    return result.rows[0]?.name ?? 'Someone';
  }

  private async notifyAdminsOfReport(id: string, title: string, body: string, transaction: DatabaseTransaction): Promise<void> {
    await transaction.query(
      `WITH inserted AS (
         INSERT INTO notifications (user_id, title, body, type, reference_id)
         SELECT user_id, $1, $2, 'content_report', $3 FROM admins RETURNING id, user_id
       ) INSERT INTO outbox_events (aggregate_type, aggregate_id, event_type, payload)
       SELECT 'notification', id, 'notification.created',
              jsonb_build_object('notificationId', id, 'userId', user_id) FROM inserted`, [title, body, id],
    );
  }

  private async notification(userId: string, title: string, body: string, type: string, referenceId: string | null, actorId: string | null, transaction: DatabaseTransaction): Promise<void> {
    await insertNotificationBatch(transaction, [{ userId, title, body, type, referenceId, actorId }]);
  }

  private async emit(
    eventType: string,
    aggregateId: string,
    payload: Record<string, unknown>,
    transaction: DatabaseTransaction,
  ): Promise<void> {
    await transaction.query(
      `INSERT INTO outbox_events (aggregate_type, aggregate_id, event_type, payload)
       VALUES ('social', $1, $2, $3::jsonb)`,
      [aggregateId, eventType, JSON.stringify(payload)],
    );
  }
}
