import { BadRequestException, ConflictException, ForbiddenException, Injectable, NotFoundException } from '@nestjs/common';
import { DatabaseService, type DatabaseTransaction } from '../../../infrastructure/database/database.service.js';
import type { CreateSubmissionDto } from '../presentation/submission.dto.js';

export interface SubmissionRecord {
  readonly id: string;
  readonly user_quest_id: string;
  readonly user_id: string;
  readonly media_url: string;
  readonly media_type: string;
  readonly caption: string | null;
  readonly status: string;
  readonly reviewed_by: string | null;
  readonly review_note: string | null;
  readonly submitted_at: Date;
  readonly reviewed_at: Date | null;
  readonly appeal_note: string | null;
  readonly appealed: boolean;
  readonly show_in_feed: boolean;
  readonly visibility: string;
  readonly deleted_at: Date | null;
  readonly xp_awarded: boolean;
  readonly xp_awarded_amount: number;
}

interface ReviewRow extends SubmissionRecord {
  quest_xp: number;
}

@Injectable()
export class SubmissionsRepository {
  constructor(private readonly database: DatabaseService) {}

  async create(userId: string, input: CreateSubmissionDto): Promise<SubmissionRecord> {
    return this.database.transaction(async (transaction) => {
      const userQuest = await transaction.query<{ status: string; expires_at: Date }>(
        'SELECT status::text, expires_at FROM user_quests WHERE id = $1 AND user_id = $2 FOR UPDATE',
        [input.userQuestId, userId],
      );
      const assignment = userQuest.rows[0];
      if (!assignment) throw new NotFoundException({ code: 'USER_QUEST_NOT_FOUND', message: 'Quest assignment not found' });
      if (assignment.status !== 'assigned') {
        throw new ConflictException({ code: 'QUEST_NOT_ASSIGNED', message: "You've already submitted this quest" });
      }
      if (assignment.expires_at <= new Date()) {
        throw new ConflictException({ code: 'QUEST_EXPIRED', message: 'The timer ran out. This quest has expired' });
      }

      const mediaKeys = this.parseMediaKeys(input.mediaUrl);
      const media = await transaction.query<{ object_key: string; content_type: string }>(
        `SELECT object_key, content_type FROM media_objects
         WHERE user_id = $1 AND kind = 'submission' AND status = 'ready'
           AND object_key = ANY($2::text[])`,
        [userId, mediaKeys],
      );
      if (media.rowCount !== mediaKeys.length) {
        throw new BadRequestException({
          code: 'UNVERIFIED_MEDIA',
          message: 'Every submission file must be an owned, verified upload',
        });
      }
      const containsImage = media.rows.some((row) => row.content_type.startsWith('image/'));
      const containsVideo = media.rows.some((row) => row.content_type.startsWith('video/'));
      const expectedType = containsImage && containsVideo ? 'mixed' : containsVideo ? 'video' : 'image';
      if (input.mediaType !== expectedType) {
        throw new BadRequestException({ code: 'MEDIA_TYPE_MISMATCH', message: `mediaType must be ${expectedType}` });
      }

      const result = await transaction.query<SubmissionRecord>(
        `INSERT INTO submissions (user_quest_id, user_id, media_url, media_type, caption, show_in_feed)
         VALUES ($1, $2, $3, $4, $5, $6) RETURNING *`,
        [input.userQuestId, userId, input.mediaUrl, input.mediaType, input.caption?.trim() || null, input.showInFeed],
      );
      await transaction.query("UPDATE user_quests SET status = 'submitted', version = version + 1 WHERE id = $1", [input.userQuestId]);
      await transaction.query(
        `UPDATE collab_group_members m SET submission_time_seconds = GREATEST(0,
           floor(EXTRACT(EPOCH FROM ($2::timestamptz - uq.assigned_at)))::integer)
         FROM user_quests uq WHERE m.user_quest_id = $1 AND uq.id = m.user_quest_id`,
        [input.userQuestId, result.rows[0].submitted_at],
      );
      await this.notifyAdmins(result.rows[0], false, transaction);
      await this.emit('submission', result.rows[0].id, 'submission.created', {
        submissionId: result.rows[0].id,
        userId,
      }, transaction);
      return result.rows[0];
    });
  }

  private parseMediaKeys(raw: string): string[] {
    try {
      const parsed: unknown = raw.trim().startsWith('[') ? JSON.parse(raw) : [raw];
      if (!Array.isArray(parsed) || parsed.length < 1 || parsed.length > 10) throw new Error('invalid');
      const keys = [...new Set(parsed.map((value) => typeof value === 'string' ? value.trim() : ''))];
      if (keys.length !== parsed.length || keys.some((key) => !/^submissions\/[0-9a-f-]{36}\/[A-Za-z0-9._-]+$/i.test(key))) {
        throw new Error('invalid');
      }
      return keys;
    } catch {
      throw new BadRequestException({ code: 'INVALID_MEDIA_REFERENCE', message: 'mediaUrl must contain one to ten private submission object keys' });
    }
  }

  async findVisibleToUser(id: string, viewerId: string): Promise<Record<string, unknown> | null> {
    const result = await this.database.query(
      `SELECT s.*, q.id AS quest_id, q.title AS quest_title, q.description AS quest_description,
              q.category AS quest_category, q.xp_reward,
              p.username::text AS author_username, p.display_name AS author_display_name, p.avatar_url,
              COALESCE(rx.upvotes, 0)::integer AS upvote_count,
              COALESCE(rx.downvotes, 0)::integer AS downvote_count,
              (COALESCE(rx.upvotes, 0) - COALESCE(rx.downvotes, 0))::integer AS net_score,
              (gm.group_id IS NOT NULL) AS is_collab, gm.group_id AS collab_group_id,
              g.mode::text AS collab_mode,
              COALESCE((SELECT count(*) FROM collab_group_members count_member
                        WHERE count_member.group_id = gm.group_id), 0)::integer AS collab_member_count,
              CASE WHEN gm.group_id IS NULL THEN NULL ELSE (
                SELECT json_agg(json_build_object(
                  'user_id', member_profile.id,
                  'username', member_profile.username::text,
                  'display_name', member_profile.display_name,
                  'avatar_url', member_profile.avatar_url,
                  'bio', member_profile.bio,
                  'submission_id', member_submission.id,
                  'media_url', member_submission.media_url,
                  'media_type', member_submission.media_type::text,
                  'submission_status', member_submission.status::text,
                  'caption', member_submission.caption,
                  'show_in_feed', member_submission.show_in_feed,
                  'vote_count', COALESCE((SELECT count(*) FROM collab_votes vote
                                           WHERE vote.submission_id = member_submission.id), 0),
                  'viewer_voted', EXISTS(SELECT 1 FROM collab_votes vote
                                         WHERE vote.submission_id = member_submission.id
                                           AND vote.voter_id = $2)
                ) ORDER BY member.joined_at)
                FROM collab_group_members member
                JOIN profiles member_profile ON member_profile.id = member.user_id
                LEFT JOIN submissions member_submission ON member_submission.user_quest_id = member.user_quest_id
                WHERE member.group_id = gm.group_id
              ) END AS collab_members,
              uq.expires_at
       FROM submissions s JOIN user_quests uq ON uq.id = s.user_quest_id
       JOIN quests q ON q.id = uq.quest_id JOIN profiles p ON p.id = s.user_id
       LEFT JOIN collab_group_members gm ON gm.user_quest_id = uq.id
       LEFT JOIN collab_groups g ON g.id = gm.group_id
       LEFT JOIN LATERAL (
         SELECT count(*) FILTER (WHERE reaction.type = 'upvote') AS upvotes,
                count(*) FILTER (WHERE reaction.type = 'downvote') AS downvotes
         FROM reactions reaction WHERE reaction.submission_id = s.id
       ) rx ON true
       WHERE s.id = $1 AND (
         s.user_id = $2 OR EXISTS (SELECT 1 FROM admins WHERE user_id = $2) OR
         (s.status = 'approved' AND s.visibility = 'visible' AND s.deleted_at IS NULL)
       )`,
      [id, viewerId],
    );
    return result.rows[0] ?? null;
  }

  async listUser(userId: string, viewerId: string, limit: number, offset: number): Promise<readonly SubmissionRecord[]> {
    const result = await this.database.query<SubmissionRecord>(
      `SELECT s.* FROM submissions s
       WHERE s.user_id = $1 AND s.visibility <> 'deleted' AND s.deleted_at IS NULL
         AND ($1 = $2 OR s.status = 'approved')
       ORDER BY s.submitted_at DESC, s.id DESC LIMIT $3 OFFSET $4`,
      [userId, viewerId, Math.min(Math.max(limit, 1), 100), Math.max(offset, 0)],
    );
    return result.rows;
  }

  async listPending(limit: number, offset: number): Promise<readonly Record<string, unknown>[]> {
    const result = await this.database.query(
      `SELECT s.*, p.username::text, p.display_name, p.avatar_url,
              q.title AS quest_title, q.description AS quest_description, q.category AS quest_category
       FROM submissions s JOIN profiles p ON p.id = s.user_id
       JOIN user_quests uq ON uq.id = s.user_quest_id JOIN quests q ON q.id = uq.quest_id
       WHERE s.status = 'pending' ORDER BY s.submitted_at ASC, s.id LIMIT $1 OFFSET $2`,
      [Math.min(Math.max(limit, 1), 100), Math.max(offset, 0)],
    );
    return result.rows;
  }

  async appeal(userId: string, id: string, appealNote: string): Promise<void> {
    await this.database.transaction(async (transaction) => {
      const result = await transaction.query<SubmissionRecord>('SELECT * FROM submissions WHERE id = $1 FOR UPDATE', [id]);
      const submission = result.rows[0];
      if (!submission) throw new NotFoundException({ code: 'SUBMISSION_NOT_FOUND', message: 'Submission not found' });
      if (submission.user_id !== userId) throw new ForbiddenException({ code: 'NOT_SUBMISSION_OWNER', message: 'Not your submission' });
      if (submission.status !== 'rejected') throw new ConflictException({ code: 'SUBMISSION_NOT_REJECTED', message: 'Only rejected submissions can be appealed' });
      if (submission.appealed) throw new ConflictException({ code: 'ALREADY_APPEALED', message: 'Already appealed' });
      if (submission.visibility === 'deleted') throw new ConflictException({ code: 'DELETED_SUBMISSION', message: 'Cannot appeal a deleted submission' });
      await transaction.query(
        `UPDATE submissions SET status = 'pending', appeal_note = $2, appealed = true,
           reviewed_by = NULL, review_note = NULL, reviewed_at = NULL, version = version + 1
         WHERE id = $1`,
        [id, appealNote.trim()],
      );
      await transaction.query("UPDATE user_quests SET status = 'submitted', version = version + 1 WHERE id = $1", [submission.user_quest_id]);
      await this.notifyAdmins(submission, true, transaction);
      await this.emit('submission', id, 'submission.appealed', {
        submissionId: id,
        userId,
      }, transaction);
    });
  }

  async approve(
    actorId: string | null,
    id: string,
    reviewNote?: string,
    source: Record<string, unknown> = {},
  ): Promise<void> {
    await this.database.transaction(async (transaction) => {
      const submission = await this.lockForReview(id, transaction);
      const profile = await transaction.query<{ level: number }>('SELECT level FROM profiles WHERE id = $1 FOR UPDATE', [submission.user_id]);
      const oldLevel = profile.rows[0].level;
      const updated = await transaction.query<SubmissionRecord>(
        `UPDATE submissions SET status = 'approved', reviewed_by = $2, reviewed_at = now(),
           review_note = COALESCE(NULLIF(trim($3), ''), review_note), xp_awarded = true,
           xp_awarded_amount = $4, version = version + 1
         WHERE id = $1 RETURNING *`,
        [id, actorId, reviewNote ?? null, submission.quest_xp],
      );
      await transaction.query("UPDATE user_quests SET status = 'approved', completed_at = now(), version = version + 1 WHERE id = $1", [submission.user_quest_id]);
      const newProfile = await transaction.query<{ level: number }>(
        `UPDATE profiles SET xp = xp + $2, quests_completed = quests_completed + 1,
           level = GREATEST(1, (xp + $2) / 100 + 1)
         WHERE id = $1 RETURNING level`,
        [submission.user_id, submission.quest_xp],
      );
      await this.createNotification(submission.user_id, 'Approved. Respect. ✅', `+${submission.quest_xp} XP added to your name. Keep cooking.`, 'submission_approved', id, transaction);
      await this.notifyCollabPartners(submission.user_id, submission.user_quest_id, id, transaction);
      if (newProfile.rows[0].level > oldLevel) {
        await this.createNotification(
          submission.user_id,
          `Level ${newProfile.rows[0].level}. Look at you. 🎮`,
          "You levelled up in real life. That's not a thing most apps can say.",
          'level_up', null, transaction,
        );
      }
      await this.audit(actorId, 'submission.approve', id, {
        previous_status: 'pending', note_chars: reviewNote?.trim().length ?? 0, ...source,
      }, transaction);
      await this.emit('submission', id, 'submission.approved', { submissionId: id, userId: submission.user_id, xpAwarded: updated.rows[0].xp_awarded_amount }, transaction);
      await this.emit('profile', submission.user_id, 'profile.updated', {
        profileId: submission.user_id,
        reason: 'xp_awarded',
      }, transaction);
    });
  }

  async reject(
    actorId: string | null,
    id: string,
    reviewNote: string,
    source: Record<string, unknown> = {},
  ): Promise<void> {
    await this.database.transaction(async (transaction) => {
      const submission = await this.lockForReview(id, transaction);
      const updated = await transaction.query<SubmissionRecord>(
        `UPDATE submissions SET status = 'rejected', reviewed_by = $2, review_note = $3,
           reviewed_at = now(), version = version + 1 WHERE id = $1 RETURNING *`,
        [id, actorId, reviewNote.trim()],
      );
      await transaction.query("UPDATE user_quests SET status = 'rejected', version = version + 1 WHERE id = $1", [submission.user_quest_id]);
      const deleted = updated.rows[0].visibility === 'deleted';
      await this.createNotification(
        submission.user_id,
        deleted ? 'Quest rejected. We took the post down.' : 'Quest rejected. Try again. 🔁',
        deleted
          ? 'Mods pulled the post and rolled back the XP. No drama. The quest is yours again whenever you want it.'
          : reviewNote.trim() || "The judges weren't convinced this round. Take another swing. Same quest, fresh shot.",
        'submission_rejected', id, transaction,
      );
      await this.audit(actorId, 'submission.reject', id, {
        previous_status: 'pending', note_chars: reviewNote.trim().length, ...source,
      }, transaction);
      await this.emit('submission', id, 'submission.rejected', { submissionId: id, userId: submission.user_id }, transaction);
    });
  }

  async setVisibility(
    userId: string,
    id: string,
    visibility: 'visible' | 'hidden_from_feed' | 'deleted',
  ): Promise<void> {
    await this.database.transaction(async (transaction) => {
      await this.transitionVisibility(id, visibility, transaction, userId);
    });
  }

  async removeByAdmin(actorId: string, id: string, reason: string): Promise<void> {
    await this.database.transaction(async (transaction) => {
      const transition = await this.transitionVisibility(id, 'deleted', transaction);
      await this.audit(actorId, 'post.remove', id, {
        user_id: transition.submission.user_id,
        previous_status: transition.submission.status,
        prev_visibility: transition.submission.visibility,
        reason: reason.trim().slice(0, 500),
        xp_rolled_back: transition.xpRolledBack,
      }, transaction);
    });
  }

  private async transitionVisibility(
    id: string,
    visibility: 'visible' | 'hidden_from_feed' | 'deleted',
    transaction: DatabaseTransaction,
    ownerId?: string,
  ): Promise<{ submission: SubmissionRecord; xpRolledBack: number }> {
    const locked = await transaction.query<SubmissionRecord>(
      `SELECT * FROM submissions WHERE id = $1
       AND ($2::uuid IS NULL OR user_id = $2) FOR UPDATE`,
      [id, ownerId ?? null],
    );
    const submission = locked.rows[0];
    if (!submission) throw new NotFoundException({ code: 'SUBMISSION_NOT_FOUND', message: 'Submission not found' });
    if (submission.visibility === visibility) return { submission, xpRolledBack: 0 };

    const xpRolledBack = visibility === 'deleted' && submission.xp_awarded
      ? submission.xp_awarded_amount
      : 0;
    if (xpRolledBack > 0 || (visibility === 'deleted' && submission.xp_awarded)) {
      await transaction.query(
        `UPDATE profiles SET
           xp = GREATEST(0, xp - $2),
           quests_completed = GREATEST(0, quests_completed - 1),
           level = GREATEST(1, GREATEST(0, xp - $2) / 100 + 1)
         WHERE id = $1`,
        [submission.user_id, xpRolledBack],
      );
    }

    await transaction.query(
      `UPDATE submissions SET
         visibility = $2::submission_visibility,
         show_in_feed = ($2::submission_visibility = 'visible'),
         deleted_at = CASE WHEN $2::submission_visibility = 'visible' THEN NULL ELSE now() END,
         xp_awarded = CASE WHEN $2::submission_visibility = 'deleted' THEN false ELSE xp_awarded END,
         version = version + 1
       WHERE id = $1`,
      [id, visibility],
    );
    if (visibility === 'deleted') {
      await this.emit('submission', id, 'submission.deleted', {
        submissionId: id,
        userId: submission.user_id,
        xpRolledBack,
      }, transaction);
      if (xpRolledBack > 0) {
        await this.emit('profile', submission.user_id, 'profile.updated', {
          profileId: submission.user_id,
          reason: 'xp_rolled_back',
        }, transaction);
      }
    } else {
      await this.emit('submission', id, 'submission.visibility_changed', {
        submissionId: id,
        userId: submission.user_id,
        visibility,
      }, transaction);
    }
    return { submission, xpRolledBack };
  }

  private async lockForReview(id: string, transaction: DatabaseTransaction): Promise<ReviewRow> {
    const result = await transaction.query<ReviewRow>(
      `SELECT s.*, q.xp_reward AS quest_xp FROM submissions s
       JOIN user_quests uq ON uq.id = s.user_quest_id JOIN quests q ON q.id = uq.quest_id
       WHERE s.id = $1 FOR UPDATE OF s`,
      [id],
    );
    const submission = result.rows[0];
    if (!submission) throw new NotFoundException({ code: 'SUBMISSION_NOT_FOUND', message: 'Submission not found' });
    if (submission.status !== 'pending') {
      throw new ConflictException({ code: 'SUBMISSION_ALREADY_REVIEWED', message: `Submission is no longer pending (current: ${submission.status})` });
    }
    return submission;
  }

  private async notifyAdmins(submission: SubmissionRecord, appeal: boolean, transaction: DatabaseTransaction): Promise<void> {
    const author = await transaction.query<{ name: string }>(
      `SELECT COALESCE(NULLIF(display_name, ''), username::text, 'Someone') AS name FROM profiles WHERE id = $1`,
      [submission.user_id],
    );
    const title = appeal ? `${author.rows[0].name} is back for round two. 🔁` : `Inbox: ${author.rows[0].name} sent proof. 📥`;
    const body = appeal ? 'Resubmitted after rejection. Fresh eyes needed.' : 'New submission waiting on a verdict.';
    const type = appeal ? 'appeal_submitted' : 'new_submission';
    const notifications = await transaction.query<{ id: string; user_id: string }>(
      `INSERT INTO notifications (user_id, title, body, type, reference_id)
       SELECT user_id, $1, $2, $3, $4 FROM admins RETURNING id, user_id`,
      [title, body, type, submission.id],
    );
    for (const notification of notifications.rows) {
      await this.emit('notification', notification.id, 'notification.created', { notificationId: notification.id, userId: notification.user_id }, transaction);
    }
  }

  private async createNotification(
    userId: string, title: string, body: string, type: string, referenceId: string | null,
    transaction: DatabaseTransaction,
  ): Promise<void> {
    const result = await transaction.query<{ id: string }>(
      `INSERT INTO notifications (user_id, title, body, type, reference_id)
       VALUES ($1, $2, $3, $4, $5) RETURNING id`,
      [userId, title, body, type, referenceId],
    );
    await this.emit('notification', result.rows[0].id, 'notification.created', { notificationId: result.rows[0].id, userId }, transaction);
  }

  private async notifyCollabPartners(
    userId: string,
    userQuestId: string,
    submissionId: string,
    transaction: DatabaseTransaction,
  ): Promise<void> {
    const group = await transaction.query<{ group_id: string }>(
      'SELECT group_id FROM collab_group_members WHERE user_quest_id = $1',
      [userQuestId],
    );
    if (!group.rows[0]) return;
    const author = await transaction.query<{ name: string }>(
      `SELECT COALESCE(NULLIF(display_name, ''), username::text, 'Someone') AS name
       FROM profiles WHERE id = $1`,
      [userId],
    );
    const notifications = await transaction.query<{ id: string; user_id: string }>(
      `INSERT INTO notifications (user_id, title, body, type, reference_id, actor_id)
       SELECT user_id, $2, $3, 'collab_partner_approved', $4, $5
       FROM collab_group_members WHERE group_id = $1 AND user_id <> $5
       RETURNING id, user_id`,
      [
        group.rows[0].group_id,
        `${author.rows[0]?.name ?? 'Someone'} delivered. ✅`,
        "Your teammate's proof got approved. The squad eats good tonight.",
        submissionId,
        userId,
      ],
    );
    for (const notification of notifications.rows) {
      await this.emit('notification', notification.id, 'notification.created', {
        notificationId: notification.id,
        userId: notification.user_id,
      }, transaction);
    }
  }

  private async emit(
    aggregateType: string, aggregateId: string, eventType: string, payload: Record<string, unknown>,
    transaction: DatabaseTransaction,
  ): Promise<void> {
    await transaction.query(
      `INSERT INTO outbox_events (aggregate_type, aggregate_id, event_type, payload)
       VALUES ($1, $2, $3, $4::jsonb)`,
      [aggregateType, aggregateId, eventType, JSON.stringify(payload)],
    );
  }

  private async audit(
    actorId: string | null, action: string, targetId: string, afterState: Record<string, unknown>,
    transaction: DatabaseTransaction,
  ): Promise<void> {
    await transaction.query(
      `INSERT INTO admin_audit_log (actor_id, action, target_type, target_id, after_state)
       VALUES ($1, $2, 'submission', $3, $4::jsonb)`,
      [actorId, action, targetId, JSON.stringify(afterState)],
    );
  }
}
