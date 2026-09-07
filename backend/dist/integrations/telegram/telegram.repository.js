var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
var __metadata = (this && this.__metadata) || function (k, v) {
    if (typeof Reflect === "object" && typeof Reflect.metadata === "function") return Reflect.metadata(k, v);
};
import { Injectable } from '@nestjs/common';
import { DatabaseService } from '../../infrastructure/database/database.service.js';
let TelegramRepository = class TelegramRepository {
    database;
    constructor(database) {
        this.database = database;
    }
    async submission(id) {
        const result = await this.database.query(`SELECT submission.id, submission.media_url, submission.media_type::text,
              submission.caption, submission.status::text, submission.review_note,
              submission.appeal_note, submission.appealed, submission.telegram_message_id,
              quest.title AS quest_title, profile.username::text, profile.display_name
       FROM submissions submission
       JOIN user_quests assignment ON assignment.id = submission.user_quest_id
       JOIN quests quest ON quest.id = assignment.quest_id
       JOIN profiles profile ON profile.id = submission.user_id
       WHERE submission.id = $1`, [id]);
        return result.rows[0] ?? null;
    }
    async setSubmissionMessageId(id, messageId) {
        await this.database.query('UPDATE submissions SET telegram_message_id = $2 WHERE id = $1', [id, messageId]);
    }
    async user(id) {
        const result = await this.database.query(`SELECT users.id, users.email::text, profile.username::text, profile.display_name,
              COALESCE(array_agg(identity.provider ORDER BY identity.provider)
                       FILTER (WHERE identity.provider IS NOT NULL), ARRAY[]::text[]) AS providers
       FROM users
       JOIN profiles profile ON profile.id = users.id
       LEFT JOIN auth_identities identity ON identity.user_id = users.id
       WHERE users.id = $1
       GROUP BY users.id, users.email, profile.username, profile.display_name`, [id]);
        return result.rows[0] ?? null;
    }
    async report(id) {
        const result = await this.database.query(`SELECT report.id, report.reported_type, report.reason,
              COALESCE(NULLIF(reporter.display_name, ''), reporter.username::text, '(unknown)') AS reporter_name,
              COALESCE(
                NULLIF(reported_user.display_name, ''), reported_user.username::text,
                NULLIF(submission_user.display_name, ''), submission_user.username::text,
                NULLIF(comment_user.display_name, ''), comment_user.username::text,
                '(' || report.reported_type || ')'
              ) AS reported_name
       FROM reports report
       JOIN profiles reporter ON reporter.id = report.reporter_id
       LEFT JOIN profiles reported_user
         ON report.reported_type = 'user' AND reported_user.id = report.reported_id
       LEFT JOIN submissions reported_submission
         ON report.reported_type = 'submission' AND reported_submission.id = report.reported_id
       LEFT JOIN profiles submission_user ON submission_user.id = reported_submission.user_id
       LEFT JOIN comments reported_comment
         ON report.reported_type = 'comment' AND reported_comment.id = report.reported_id
       LEFT JOIN profiles comment_user ON comment_user.id = reported_comment.user_id
       WHERE report.id = $1 AND report.status = 'pending'`, [id]);
        return result.rows[0] ?? null;
    }
    async claimUpdate(updateId) {
        const result = await this.database.query(`INSERT INTO telegram_webhook_updates (update_id)
       VALUES ($1::bigint)
       ON CONFLICT (update_id) DO UPDATE SET
         status = 'processing', locked_until = now() + interval '2 minutes',
         attempts = telegram_webhook_updates.attempts + 1,
         last_error = NULL, updated_at = now()
       WHERE telegram_webhook_updates.status = 'failed'
          OR (telegram_webhook_updates.status = 'processing'
              AND telegram_webhook_updates.locked_until < now())
       RETURNING update_id`, [updateId]);
        return Boolean(result.rowCount);
    }
    async finishUpdate(updateId, error) {
        const failed = error !== undefined;
        await this.database.query(`UPDATE telegram_webhook_updates
       SET status = $2, processed_at = CASE WHEN $2 = 'processed' THEN now() ELSE NULL END,
           locked_until = now(), last_error = $3, updated_at = now()
       WHERE update_id = $1::bigint`, [updateId, failed ? 'failed' : 'processed', failed ? errorText(error) : null]);
    }
    async pendingCounts() {
        return (await this.database.query(`SELECT
         (SELECT count(*)::integer FROM submissions WHERE status = 'pending' AND NOT appealed) AS submissions,
         (SELECT count(*)::integer FROM submissions WHERE status = 'pending' AND appealed) AS appeals,
         (SELECT count(*)::integer FROM reports WHERE status = 'pending') AS reports`)).rows[0];
    }
    async stats(days) {
        return (await this.database.query(`SELECT
         (SELECT count(*)::integer FROM submissions WHERE submitted_at >= now() - ($1 * interval '1 day')) AS submissions,
         (SELECT count(*)::integer FROM submissions WHERE status = 'approved' AND reviewed_at >= now() - ($1 * interval '1 day')) AS approved,
         (SELECT count(*)::integer FROM submissions WHERE status = 'rejected' AND reviewed_at >= now() - ($1 * interval '1 day')) AS rejected,
         (SELECT count(*)::integer FROM profiles WHERE created_at >= now() - ($1 * interval '1 day')) AS signups,
         (SELECT count(DISTINCT user_id)::integer FROM submissions WHERE submitted_at >= now() - ($1 * interval '1 day')) AS submitters`, [days])).rows[0];
    }
    async profileByHandle(handle) {
        const result = await this.database.query(`SELECT profile.id, profile.username::text, profile.display_name, profile.xp, profile.level,
              profile.quests_completed, users.status::text AS account_status, profile.created_at,
              (SELECT count(*)::integer FROM submissions
               WHERE user_id = profile.id AND status = 'pending') AS pending_submissions,
              (SELECT max(submitted_at) FROM submissions WHERE user_id = profile.id) AS last_submission_at
       FROM profiles profile JOIN users ON users.id = profile.id
       WHERE lower(profile.username::text) = lower($1)`, [stripHandle(handle)]);
        return result.rows[0] ?? null;
    }
    async setAccountStatus(userId, status, chatId) {
        await this.database.transaction(async (transaction) => {
            const before = await transaction.query('SELECT status::text FROM users WHERE id = $1 FOR UPDATE', [userId]);
            if (!before.rows[0])
                throw new Error('User not found');
            await transaction.query(`UPDATE users SET status = $2::account_status, token_version = token_version + 1,
           updated_at = now() WHERE id = $1`, [userId, status]);
            await transaction.query('UPDATE refresh_sessions SET revoked_at = now() WHERE user_id = $1 AND revoked_at IS NULL', [userId]);
            if (status === 'banned')
                await transaction.query('DELETE FROM device_tokens WHERE user_id = $1', [userId]);
            await transaction.query(`INSERT INTO admin_audit_log (actor_id, action, target_type, target_id, before_state, after_state)
         VALUES (NULL, 'user.set_status', 'user', $1,
                 jsonb_build_object('status', $2::text),
                 jsonb_build_object('status', $3::text, 'source', 'telegram', 'telegram_chat_id', $4::text))`, [userId, before.rows[0].status, status, chatId]);
            await transaction.query(`INSERT INTO outbox_events (aggregate_type, aggregate_id, event_type, payload)
         VALUES ('user', $1, 'admin.user_status_changed',
                 jsonb_build_object('userId', $1::uuid, 'status', $2::text, 'source', 'telegram'))`, [userId, status]);
        });
    }
    async broadcast(title, body, chatId) {
        return this.database.transaction(async (transaction) => {
            const result = await transaction.query(`WITH inserted AS (
           INSERT INTO notifications (user_id, title, body, type)
           SELECT id, $1, $2, 'broadcast' FROM users WHERE status = 'active'
           RETURNING id, user_id
         ), emitted AS (
           INSERT INTO outbox_events (aggregate_type, aggregate_id, event_type, payload)
           SELECT 'notification', id, 'notification.created',
                  jsonb_build_object('notificationId', id, 'userId', user_id)
           FROM inserted
           RETURNING 1
         )
         SELECT count(*)::integer AS recipient_count FROM emitted`, [title.slice(0, 180), body.slice(0, 500)]);
            const recipients = result.rows[0].recipient_count;
            await transaction.query(`INSERT INTO admin_audit_log (actor_id, action, target_type, after_state)
         VALUES (NULL, 'notification.broadcast', 'notification',
                 jsonb_build_object('source', 'telegram', 'telegram_chat_id', $1::text,
                                    'title', $2::text, 'recipient_count', $3::integer))`, [chatId, title, recipients]);
            return recipients;
        });
    }
    async activeQuests() {
        return (await this.database.query(`SELECT id, title, description FROM quests WHERE is_active
       ORDER BY created_at DESC, id DESC LIMIT 50`)).rows;
    }
    async audit(handle) {
        return (await this.database.query(`SELECT audit.created_at,
              COALESCE(NULLIF(profile.display_name, ''), '@' || profile.username::text, '(system)') AS actor_name,
              audit.action
       FROM admin_audit_log audit
       LEFT JOIN profiles profile ON profile.id = audit.actor_id
       WHERE ($1::text IS NULL OR lower(profile.username::text) = lower($1))
       ORDER BY audit.created_at DESC LIMIT 10`, [handle ? stripHandle(handle) : null])).rows;
    }
    async weeklyLeaderboard() {
        return (await this.database.query(`SELECT profile.display_name, profile.username::text,
              count(*)::integer AS approvals
       FROM submissions submission JOIN profiles profile ON profile.id = submission.user_id
       WHERE submission.status = 'approved' AND submission.reviewed_at >= now() - interval '7 days'
       GROUP BY profile.id, profile.display_name, profile.username
       ORDER BY approvals DESC, profile.id LIMIT 5`)).rows;
    }
    async dailySummary() {
        return (await this.database.query(`WITH top_quests AS (
         SELECT quest.title, count(*)::integer AS approvals
         FROM submissions submission
         JOIN user_quests assignment ON assignment.id = submission.user_quest_id
         JOIN quests quest ON quest.id = assignment.quest_id
         WHERE submission.status = 'approved'
           AND submission.reviewed_at >= now() - interval '24 hours'
         GROUP BY quest.id, quest.title
         ORDER BY approvals DESC, quest.id
         LIMIT 3
       )
       SELECT
         (SELECT count(*)::integer FROM submissions WHERE submitted_at >= now() - interval '24 hours') AS submissions,
         (SELECT count(*)::integer FROM submissions WHERE status = 'approved' AND reviewed_at >= now() - interval '24 hours') AS approved,
         (SELECT count(*)::integer FROM submissions WHERE status = 'rejected' AND reviewed_at >= now() - interval '24 hours') AS rejected,
         (SELECT count(*)::integer FROM profiles WHERE created_at >= now() - interval '24 hours') AS signups,
         (SELECT count(DISTINCT user_id)::integer FROM submissions WHERE submitted_at >= now() - interval '24 hours') AS submitters,
         (SELECT count(*)::integer FROM submissions WHERE status = 'pending' AND NOT appealed) AS pending_submissions,
         (SELECT count(*)::integer FROM submissions WHERE status = 'pending' AND appealed) AS pending_appeals,
         (SELECT count(*)::integer FROM reports WHERE status = 'pending') AS pending_reports,
         COALESCE((SELECT jsonb_agg(jsonb_build_object('title', title, 'approvals', approvals)
                                   ORDER BY approvals DESC, title)
                   FROM top_quests), '[]'::jsonb) AS top_quests`)).rows[0];
    }
    async commandState(chatId) {
        const result = await this.database.query(`SELECT chat_id::text, command, step, data FROM telegram_command_state WHERE chat_id = $1::bigint`, [chatId]);
        return result.rows[0] ?? null;
    }
    async setCommandState(chatId, command, step, data) {
        await this.database.query(`INSERT INTO telegram_command_state (chat_id, command, step, data)
       VALUES ($1::bigint, $2, $3, $4::jsonb)
       ON CONFLICT (chat_id) DO UPDATE SET command = EXCLUDED.command, step = EXCLUDED.step,
         data = EXCLUDED.data, updated_at = now()`, [chatId, command, step, JSON.stringify(data)]);
    }
    async clearCommandState(chatId) {
        await this.database.query('DELETE FROM telegram_command_state WHERE chat_id = $1::bigint', [chatId]);
    }
    async createQuest(data, chatId) {
        return this.database.transaction(async (transaction) => {
            const quest = await transaction.query(`INSERT INTO quests (title, description, category, difficulty, xp_reward, duration_hours, is_active)
         VALUES ($1, $2, $3, $4, $5, 4, true) RETURNING id`, [data.title, data.description, data.category, data.difficulty, data.xp_reward]);
            await transaction.query(`INSERT INTO admin_audit_log (actor_id, action, target_type, target_id, after_state)
         VALUES (NULL, 'quest.create', 'quest', $1,
                 jsonb_build_object('source', 'telegram', 'telegram_chat_id', $2::text))`, [quest.rows[0].id, chatId]);
            return quest.rows[0].id;
        });
    }
    async reviewReport(reportId, action, chatId) {
        return this.database.transaction(async (transaction) => {
            const result = await transaction.query(`SELECT report.status, report.reported_type, report.reported_id,
                CASE report.reported_type
                  WHEN 'user' THEN reported_user.id
                  WHEN 'submission' THEN submission.user_id
                  WHEN 'comment' THEN comment.user_id
                END AS offender_id
         FROM reports report
         LEFT JOIN users reported_user
           ON report.reported_type = 'user' AND reported_user.id::text = report.reported_id
         LEFT JOIN submissions submission
           ON report.reported_type = 'submission' AND submission.id::text = report.reported_id
         LEFT JOIN comments comment
           ON report.reported_type = 'comment' AND comment.id::text = report.reported_id
         WHERE report.id = $1 FOR UPDATE OF report`, [reportId]);
            const report = result.rows[0];
            if (!report)
                return { ok: false, message: 'Report not found' };
            if (report.status !== 'pending')
                return { ok: false, message: `Already ${report.status}` };
            if (action === 'action' && !report.offender_id)
                return { ok: false, message: 'Reported user not found' };
            if (action === 'action') {
                await transaction.query(`UPDATE users SET status = 'banned', token_version = token_version + 1,
             updated_at = now() WHERE id = $1`, [report.offender_id]);
                await transaction.query('UPDATE refresh_sessions SET revoked_at = now() WHERE user_id = $1 AND revoked_at IS NULL', [report.offender_id]);
                await transaction.query('DELETE FROM device_tokens WHERE user_id = $1', [report.offender_id]);
            }
            const status = action === 'action' ? 'actioned' : 'dismissed';
            await transaction.query(`UPDATE reports SET status = $2, reviewed_by = NULL, reviewed_at = now() WHERE id = $1`, [reportId, status]);
            await transaction.query(`INSERT INTO admin_audit_log (actor_id, action, target_type, target_id, after_state)
         VALUES (NULL, $2, 'report', $1,
                 jsonb_build_object('source', 'telegram', 'telegram_chat_id', $3::text,
                                    'status', $4::text, 'offender_id', $5::uuid))`, [reportId, action === 'action' ? 'report.action' : 'report.dismiss', chatId, status, report.offender_id]);
            return { ok: true, message: action === 'action' ? 'User banned' : 'Dismissed' };
        });
    }
};
TelegramRepository = __decorate([
    Injectable(),
    __metadata("design:paramtypes", [DatabaseService])
], TelegramRepository);
export { TelegramRepository };
function stripHandle(value) {
    return value.replace(/^@/, '').trim();
}
function errorText(error) {
    return (error instanceof Error ? error.message : String(error)).slice(0, 2000);
}
//# sourceMappingURL=telegram.repository.js.map