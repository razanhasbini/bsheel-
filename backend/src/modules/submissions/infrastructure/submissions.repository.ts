import { BadRequestException, ConflictException, ForbiddenException, Injectable, NotFoundException } from '@nestjs/common';
import { decodeCursor, encodeCursor } from '../../../common/pagination/keyset-cursor.js';
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
  readonly moderation_removed_at: Date | null;
  readonly xp_awarded: boolean;
  readonly xp_awarded_amount: number;
}

/// Cursor contexts. Distinct per list so a cursor cannot be replayed on a
/// list with a different ordering — `decodeCursor` rejects a mismatch.
const listForAdminCursorContext = 'submissions.admin.list';
const reviewQueueCursorContext = 'submissions.admin.review-queue';

/// Attaches `next_cursor` to the last row of a full page, and strips the
/// internal `pagination_at` column the cursor is built from.
///
/// `pagination_at` exists because the `pg` driver decodes `timestamptz` into
/// a JS `Date`, which holds milliseconds — Postgres stores microseconds. A
/// cursor derived from that Date lands *before* the row it came from, so
/// `(submitted_at, id) > (cursor)` re-returns that row and every other row
/// inside the same millisecond. That is a silent duplicate-rows bug, and it
/// is what the first version of this did; the e2e walk caught it. The query
/// therefore emits the timestamp as microsecond-precision text and the
/// cursor carries that verbatim. The feed does the same thing for the same
/// reason.
///
/// A short page is the end-of-list signal, so no cursor is offered there. A
/// full page might still be the last one, in which case the next request
/// simply returns nothing — cheaper than a count, and it never claims there
/// are more rows than there are.
function withNextCursor(
  rows: readonly Record<string, unknown>[],
  limit: number,
  context: string,
): readonly Record<string, unknown>[] {
  const exhausted = rows.length < limit;
  return rows.map(({ pagination_at, ...row }, index) => ({
    ...row,
    next_cursor: exhausted || index !== rows.length - 1
      ? null
      : encodeCursor({ context, at: pagination_at as string, id: row.id as string }),
  }));
}

interface ReviewRow extends SubmissionRecord {
  quest_xp: number;
  /// Quest-of-the-Day bonus for this attempt, or 0. Earned only when the
  /// quest was the QOTD on the UTC day the user took it on, so yesterday's
  /// ticket rolled randomly today does not pay the bonus.
  qotd_bonus_xp: number;
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
           AND deleted_at IS NULL AND reclaim_started_at IS NULL
           AND object_key = ANY($2::text[]) ORDER BY id FOR UPDATE`,
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
      await transaction.query(
        `INSERT INTO media_submission_links (media_object_id, submission_id)
         SELECT id, $1 FROM media_objects
         WHERE user_id = $2 AND kind = 'submission' AND status = 'ready'
           AND object_key = ANY($3::text[])`,
        [result.rows[0].id, userId, mediaKeys],
      );
      await transaction.query("UPDATE user_quests SET status = 'submitted', version = version + 1 WHERE id = $1", [input.userQuestId]);
      await transaction.query(
        `UPDATE collab_group_members m SET submission_time_seconds = GREATEST(0,
           floor(EXTRACT(EPOCH FROM ($2::timestamptz - uq.assigned_at)))::integer)
         FROM user_quests uq WHERE m.user_quest_id = $1 AND uq.id = m.user_quest_id`,
        [input.userQuestId, result.rows[0].submitted_at],
      );
      // AI proof verification (#47): the queue row is created here, in the
      // same transaction as the submission, rather than by the worker that
      // consumes submission.created. That makes the catch-up sweep a real
      // safety net — it can find work even if the event was never delivered —
      // instead of one that only sees submissions the outbox already reached.
      await transaction.query(
        'INSERT INTO submission_verifications (submission_id) VALUES ($1) ON CONFLICT DO NOTHING',
        [result.rows[0].id],
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
                  -- Withheld unless the viewer owns it or it is publicly
                  -- visible. Same leak as the feed's roster: this join had no
                  -- status/visibility/deleted_at predicate, so pending and
                  -- rejected proof was served to anyone who could read the
                  -- parent submission.
                  'media_url', CASE WHEN member_submission.user_id = $2
                                      OR (member_submission.status = 'approved'
                                          AND member_submission.visibility = 'visible'
                                          AND member_submission.deleted_at IS NULL)
                                 THEN member_submission.media_url END,
                  'media_type', member_submission.media_type::text,
                  'submission_status', member_submission.status::text,
                  'caption', CASE WHEN member_submission.user_id = $2
                                    OR (member_submission.status = 'approved'
                                        AND member_submission.visibility = 'visible'
                                        AND member_submission.deleted_at IS NULL)
                               THEN member_submission.caption END,
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

  /// The moderation review queue with the reviewer context the admin UI
  /// shows as trust hints and a DUPLICATE badge.
  ///
  /// The counts and the duplicate check are computed here rather than in the
  /// client, which previously fetched every submission for every user in the
  /// queue to derive them. `is_duplicate` matches the legacy rule exactly:
  /// the same user has a rejected submission with an identical media_url, or
  /// an identical caption of at least 8 characters.
  /// Everything the review screen needs for one submission: the author's
  /// profile, the quest, and whether this is a retake of a quest the user
  /// already had approved (legacy `is_quest_retake`, migration 0087).
  async adminDetail(id: string): Promise<Record<string, unknown> | null> {
    const result = await this.database.query(
      `SELECT s.*,
              p.username::text, p.display_name, p.avatar_url, p.xp, p.level,
              q.id AS quest_id, q.title AS quest_title, q.description AS quest_description,
              q.category AS quest_category, q.difficulty AS quest_difficulty,
              q.xp_reward AS quest_xp_reward, q.duration_hours AS quest_duration_hours,
              uq.status AS user_quest_status, uq.assigned_at, uq.expires_at,
              cg.id AS collab_group_id, cg.mode::text AS collab_mode,
              cg.status::text AS collab_status,
              EXISTS (
                SELECT 1 FROM user_quests prior
                WHERE prior.user_id = s.user_id
                  AND prior.quest_id = uq.quest_id
                  AND prior.status = 'approved'
                  AND prior.id <> uq.id
              ) AS is_retake
       FROM submissions s
       JOIN profiles p ON p.id = s.user_id
       JOIN user_quests uq ON uq.id = s.user_quest_id
       JOIN quests q ON q.id = uq.quest_id
       -- The review screen shows a COLLAB / VERSUS badge. Joining it here
       -- avoids a second request that would be scoped to the caller rather
       -- than to the submission's author.
       LEFT JOIN collab_group_members cgm ON cgm.user_quest_id = uq.id
       LEFT JOIN collab_groups cg ON cg.id = cgm.group_id
       WHERE s.id = $1`,
      [id],
    );
    return result.rows[0] ?? null;
  }

  async reviewQueue(limit: number, offset: number, cursor?: string): Promise<readonly Record<string, unknown>[]> {
    // The cursor filters inside the CTE, alongside the LIMIT it belongs to.
    // Applied outside it, the enrichment below would be computed for a page
    // that was then discarded.
    const decoded = decodeCursor(cursor, reviewQueueCursorContext);
    const capped = Math.min(Math.max(limit, 1), 100);
    const result = await this.database.query(
      `WITH queue AS (
         SELECT s.*, p.username::text, p.display_name, q.title AS quest_title,
                to_char(s.submitted_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.USZ') AS pagination_at
         FROM submissions s
         JOIN profiles p ON p.id = s.user_id
         JOIN user_quests uq ON uq.id = s.user_quest_id
         JOIN quests q ON q.id = uq.quest_id
         -- Deleted proof is not reviewable (lockForReview refuses it), so it
         -- must not sit in the queue either — a moderator working the rail
         -- would otherwise open it, read it, and get a 409 on decide.
         WHERE s.status = 'pending'
           AND s.visibility <> 'deleted' AND s.deleted_at IS NULL
           AND ($3::timestamptz IS NULL
                OR (s.submitted_at, s.id) > ($3::timestamptz, $4::uuid))
         ORDER BY s.submitted_at ASC, s.id
         LIMIT $1 OFFSET $2
       ),
       stats AS (
         SELECT user_id,
                count(*) FILTER (WHERE status = 'approved') AS approved_count,
                count(*) FILTER (WHERE status = 'rejected') AS rejected_count
         FROM submissions
         WHERE user_id IN (SELECT user_id FROM queue)
         GROUP BY user_id
       ),
       rejected AS (
         SELECT user_id, media_url, lower(btrim(caption)) AS caption
         FROM submissions
         WHERE status = 'rejected' AND user_id IN (SELECT user_id FROM queue)
       )
       SELECT queue.*,
              coalesce(stats.approved_count, 0)::int AS user_approved_count,
              coalesce(stats.rejected_count, 0)::int AS user_rejected_count,
              -- AI proof verification (#47). Null for anything the agent has
              -- not finished; advisory, so a moderator can ignore it.
              verification.verdict::text AS ai_verdict,
              verification.confidence AS ai_confidence,
              verification.rationale AS ai_rationale,
              verification.escalation_reason AS ai_escalation_reason,
              EXISTS (
                SELECT 1 FROM rejected r
                WHERE r.user_id = queue.user_id
                  AND (
                    (queue.media_url <> '' AND r.media_url = queue.media_url)
                    OR (char_length(coalesce(r.caption, '')) >= 8
                        AND r.caption = lower(btrim(queue.caption)))
                  )
              ) AS is_duplicate
       FROM queue
       LEFT JOIN stats ON stats.user_id = queue.user_id
       LEFT JOIN submission_verifications verification
              ON verification.submission_id = queue.id
             AND verification.state = 'complete'
       ORDER BY queue.submitted_at ASC, queue.id`,
      [
        capped,
        // Ignored once a cursor is in play: combining the two would skip rows.
        decoded ? 0 : Math.max(offset, 0),
        decoded?.at ?? null,
        decoded?.id ?? null,
      ],
    );
    return withNextCursor(result.rows, capped, reviewQueueCursorContext);
  }

  /// The admin submission lists, paginated by keyset.
  ///
  /// `PERFORMANCE.md` §5.2 measured the offset path degrading 0.93 ms at
  /// offset 0 to 153.9 ms at offset 39,000, where the plan becomes an
  /// external merge sort spilling 5.9 MB to disk — it sorts 40,000 rows of
  /// `s.*` (304 bytes wide) past `work_mem`. A keyset seek is constant cost
  /// at any depth: no sort, no spill.
  ///
  /// `offset` is still accepted, because two clients pass it today and the
  /// point of this change is to make paging possible rather than to break
  /// what already works. A supplied `cursor` wins; without one the behaviour
  /// is exactly as before.
  ///
  /// Every row carries `next_cursor`, matching how the feed already returns
  /// one. That keeps the response an array, so a client that does not paginate
  /// needs no change at all.
  async listForAdmin(filter: {
    status?: 'pending' | 'approved' | 'rejected' | 'all';
    appealed?: boolean;
    visibility?: 'visible' | 'hidden_from_feed' | 'deleted' | 'not_visible';
    order?: 'asc' | 'desc';
    limit?: number;
    offset?: number;
    cursor?: string;
  }): Promise<readonly Record<string, unknown>[]> {
    const conditions: string[] = [];
    const parameters: unknown[] = [];

    const status = filter.status ?? 'pending';
    if (status !== 'all') {
      parameters.push(status);
      conditions.push(`s.status = $${parameters.length}`);
    }
    if (filter.appealed !== undefined) {
      parameters.push(filter.appealed);
      conditions.push(`s.appealed = $${parameters.length}`);
    }
    // `not_visible` is the moderation "removed content" view: anything the
    // feed no longer shows, whether hidden or soft-deleted.
    if (filter.visibility === 'not_visible') {
      conditions.push(`s.visibility <> 'visible'`);
    } else if (filter.visibility !== undefined) {
      parameters.push(filter.visibility);
      conditions.push(`s.visibility = $${parameters.length}`);
    }

    // Interpolated only from a closed set the DTO already validated; never
    // from raw input.
    const descending = filter.order === 'desc';
    const direction = descending ? 'DESC' : 'ASC';

    // The cursor is context-bound to this list, so one taken from the feed —
    // or from the review queue — is rejected rather than silently paging
    // through the wrong ordering.
    const cursor = decodeCursor(filter.cursor, listForAdminCursorContext);
    if (cursor) {
      parameters.push(cursor.at, cursor.id);
      // The comparison follows the sort: reversing one without the other
      // returns the page already seen.
      const comparison = descending ? '<' : '>';
      conditions.push(
        `(s.submitted_at, s.id) ${comparison} ($${parameters.length - 1}::timestamptz, $${parameters.length}::uuid)`,
      );
    }

    const where = conditions.length ? `WHERE ${conditions.join(' AND ')}` : '';
    const limit = Math.min(Math.max(filter.limit ?? 50, 1), 100);
    parameters.push(limit);
    const limitPlaceholder = `$${parameters.length}`;
    // Ignored once a cursor is in play: mixing the two would skip rows.
    parameters.push(cursor ? 0 : Math.max(filter.offset ?? 0, 0));
    const offsetPlaceholder = `$${parameters.length}`;

    const result = await this.database.query(
      `SELECT s.*, p.username::text, p.display_name, p.avatar_url,
              q.title AS quest_title, q.description AS quest_description, q.category AS quest_category,
              to_char(s.submitted_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.USZ') AS pagination_at
       FROM submissions s JOIN profiles p ON p.id = s.user_id
       JOIN user_quests uq ON uq.id = s.user_quest_id JOIN quests q ON q.id = uq.quest_id
       ${where}
       ORDER BY s.submitted_at ${direction}, s.id
       LIMIT ${limitPlaceholder} OFFSET ${offsetPlaceholder}`,
      parameters,
    );
    return withNextCursor(result.rows, limit, listForAdminCursorContext);
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
      // One figure covers base + Quest-of-the-Day bonus. Rollback on takedown
      // and restore both read xp_awarded_amount, so folding the bonus in here
      // keeps those paths correct with no extra branch.
      const bonusXp = submission.qotd_bonus_xp ?? 0;
      const awardedXp = submission.quest_xp + bonusXp;
      const updated = await transaction.query<SubmissionRecord>(
        `UPDATE submissions SET status = 'approved', reviewed_by = $2, reviewed_at = now(),
           review_note = COALESCE(NULLIF(trim($3), ''), review_note), xp_awarded = true,
           xp_awarded_amount = $4, version = version + 1
         WHERE id = $1 RETURNING *`,
        [id, actorId, reviewNote ?? null, awardedXp],
      );
      await transaction.query("UPDATE user_quests SET status = 'approved', completed_at = now(), version = version + 1 WHERE id = $1", [submission.user_quest_id]);
      const newProfile = await transaction.query<{ level: number }>(
        `UPDATE profiles SET xp = xp + $2, quests_completed = quests_completed + 1,
           level = GREATEST(1, (xp + $2) / 100 + 1)
         WHERE id = $1 RETURNING level`,
        [submission.user_id, awardedXp],
      );
      // Name the bonus when there is one — the ticket promised it on the home
      // screen, so the approval has to account for it.
      const xpLine = bonusXp > 0
        ? `+${awardedXp} XP added to your name (${submission.quest_xp} + ${bonusXp} Quest of the Day bonus). Keep cooking.`
        : `+${awardedXp} XP added to your name. Keep cooking.`;
      await this.createNotification(submission.user_id, 'Approved. Respect. ✅', xpLine, 'submission_approved', id, transaction);
      await this.notifyCollabPartners(submission.user_id, submission.user_quest_id, id, transaction);
      if (newProfile.rows[0].level > oldLevel) {
        await this.createNotification(
          submission.user_id,
          `Level ${newProfile.rows[0].level}. Look at you. 🎮`,
          "You levelled up in real life. That's not a thing most apps can say.",
          'level_up', null, transaction,
        );
      }
      // AI proof verification (#47): a human has now decided, so the
      // escalation leaves the "unclear" queue in the same transaction that
      // recorded the decision. A reviewed submission must never still be
      // listed as waiting on a human.
      await transaction.query(
        `UPDATE submission_verifications SET resolved_by = $2, resolved_at = now()
         WHERE submission_id = $1 AND resolved_at IS NULL`,
        [id, actorId],
      );
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
      // AI proof verification (#47): a human has now decided, so the
      // escalation leaves the "unclear" queue in the same transaction that
      // recorded the decision. A reviewed submission must never still be
      // listed as waiting on a human.
      await transaction.query(
        `UPDATE submission_verifications SET resolved_by = $2, resolved_at = now()
         WHERE submission_id = $1 AND resolved_at IS NULL`,
        [id, actorId],
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
    if (ownerId && submission.moderation_removed_at && visibility !== 'deleted') {
      throw new ForbiddenException({ code: 'MODERATION_TAKEDOWN', message: 'A moderator removed this post. It cannot be restored by its author.' });
    }
    if (!ownerId && visibility === 'deleted') {
      // Record provenance even when a moderator removes an already owner-deleted
      // post. The aggregate lock serializes this with any simultaneous restore.
      await transaction.query('UPDATE submissions SET moderation_removed_at = COALESCE(moderation_removed_at, now()) WHERE id = $1', [id]);
    }
    if (submission.visibility === visibility) return { submission, xpRolledBack: 0 };

    const xpRolledBack = visibility === 'deleted' && submission.xp_awarded
      ? submission.xp_awarded_amount
      : 0;
    const restoreAward = submission.visibility === 'deleted' && visibility !== 'deleted'
      && submission.status === 'approved' && !submission.xp_awarded;
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
    if (restoreAward) {
      await transaction.query(
        `UPDATE profiles SET xp = xp + $2, quests_completed = quests_completed + 1,
           level = GREATEST(1, (xp + $2) / 100 + 1) WHERE id = $1`,
        [submission.user_id, submission.xp_awarded_amount],
      );
    }

    await transaction.query(
      `UPDATE submissions SET
         visibility = $2::submission_visibility,
         show_in_feed = ($2::submission_visibility = 'visible'),
         deleted_at = CASE WHEN $2::submission_visibility = 'deleted' THEN now() ELSE NULL END,
         xp_awarded = CASE WHEN $2::submission_visibility = 'deleted' THEN false WHEN $3 THEN true ELSE xp_awarded END,
         version = version + 1
       WHERE id = $1`,
      [id, visibility, restoreAward],
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
      if (restoreAward) {
        await this.emit('profile', submission.user_id, 'profile.updated', {
          profileId: submission.user_id,
          reason: 'xp_restored',
        }, transaction);
      }
    }
    return { submission, xpRolledBack };
  }

  private async lockForReview(id: string, transaction: DatabaseTransaction): Promise<ReviewRow> {
    const result = await transaction.query<ReviewRow>(
      `SELECT s.*, q.xp_reward AS quest_xp,
              COALESCE(d.bonus_xp, 0) AS qotd_bonus_xp
       FROM submissions s
       JOIN user_quests uq ON uq.id = s.user_quest_id JOIN quests q ON q.id = uq.quest_id
       -- The bonus is tied to the day the quest was taken on, not the day it
       -- is reviewed: a moderator's backlog must not change what a user earns.
       LEFT JOIN quest_of_the_day d
              ON d.quest_id = uq.quest_id
             AND d.display_date = (uq.assigned_at AT TIME ZONE 'UTC')::date
       WHERE s.id = $1 FOR UPDATE OF s`,
      [id],
    );
    const submission = result.rows[0];
    if (!submission) throw new NotFoundException({ code: 'SUBMISSION_NOT_FOUND', message: 'Submission not found' });
    if (submission.status !== 'pending') {
      throw new ConflictException({ code: 'SUBMISSION_ALREADY_REVIEWED', message: `Submission is no longer pending (current: ${submission.status})` });
    }
    // Withdrawn or taken-down proof cannot be reviewed.
    //
    // Only `status` was checked here, so a pending submission that the author
    // had deleted — or that a moderator had already removed — could still be
    // approved. The XP was then unrecoverable, because `transitionVisibility`
    // short-circuits when `visibility` is already 'deleted', so the rollback
    // that should claw it back is a no-op. The result was permanent XP and a
    // completed-quest credit for a post that no longer exists.
    //
    // The appeal path has always guarded this; approve and reject never did.
    if (submission.visibility === 'deleted' || submission.deleted_at) {
      throw new ConflictException({ code: 'DELETED_SUBMISSION', message: 'This submission was deleted and can no longer be reviewed' });
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
    await transaction.query(
      `WITH inserted AS (INSERT INTO notifications (user_id, title, body, type, reference_id)
       SELECT user_id, $1, $2, $3, $4 FROM admins RETURNING id, user_id)
       INSERT INTO outbox_events (aggregate_type, aggregate_id, event_type, payload)
       SELECT 'notification', id, 'notification.created',
         jsonb_build_object('notificationId', id, 'userId', user_id) FROM inserted`,
      [title, body, type, submission.id],
    );
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
    await transaction.query(
      `WITH inserted AS (INSERT INTO notifications (user_id, title, body, type, reference_id, actor_id)
       SELECT user_id, $2, $3, 'collab_partner_approved', $4, $5
       FROM collab_group_members WHERE group_id = $1 AND user_id <> $5
       RETURNING id, user_id)
       INSERT INTO outbox_events (aggregate_type, aggregate_id, event_type, payload)
       SELECT 'notification', id, 'notification.created',
         jsonb_build_object('notificationId', id, 'userId', user_id) FROM inserted`,
      [
        group.rows[0].group_id,
        `${author.rows[0]?.name ?? 'Someone'} delivered. ✅`,
        "Your teammate's proof got approved. The squad eats good tonight.",
        submissionId,
        userId,
      ],
    );
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
