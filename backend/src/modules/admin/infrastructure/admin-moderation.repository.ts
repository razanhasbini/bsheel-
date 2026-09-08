import { Injectable, ConflictException, NotFoundException } from '@nestjs/common';
import { DatabaseService } from '../../../infrastructure/database/database.service.js';
import { AdminRepositoryBase } from './admin-repository.base.js';

@Injectable()
export class AdminModerationRepository extends AdminRepositoryBase {
  constructor(database: DatabaseService) { super(database); }

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
}
