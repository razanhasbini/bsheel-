var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
var __metadata = (this && this.__metadata) || function (k, v) {
    if (typeof Reflect === "object" && typeof Reflect.metadata === "function") return Reflect.metadata(k, v);
};
import { ConflictException, ForbiddenException, Injectable, NotFoundException } from '@nestjs/common';
import { DatabaseService } from '../../../infrastructure/database/database.service.js';
let SocialRepository = class SocialRepository {
    database;
    constructor(database) {
        this.database = database;
    }
    async getVote(userId, submissionId) {
        return (await this.database.query('SELECT id, submission_id, user_id, type::text, created_at FROM reactions WHERE submission_id = $1 AND user_id = $2', [submissionId, userId])).rows[0] ?? null;
    }
    async vote(userId, submissionId, type) {
        return this.database.transaction(async (transaction) => {
            const submissionResult = await transaction.query(`SELECT user_id FROM submissions WHERE id = $1 AND status = 'approved'
         AND visibility = 'visible' AND deleted_at IS NULL`, [submissionId]);
            const submission = submissionResult.rows[0];
            if (!submission)
                throw new NotFoundException({ code: 'POST_NOT_FOUND', message: 'Post not found' });
            if (submission.user_id === userId)
                throw new ForbiddenException({ code: 'SELF_REACTION', message: 'You cannot react to your own submission' });
            const result = await transaction.query(`INSERT INTO reactions (submission_id, user_id, type) VALUES ($1, $2, $3)
         ON CONFLICT (submission_id, user_id) DO UPDATE SET type = EXCLUDED.type
         RETURNING id, submission_id, user_id, type::text, created_at, (xmax = 0) AS inserted`, [submissionId, userId, type]);
            if (result.rows[0].inserted)
                await this.reactionNotifications(userId, submission.user_id, submissionId, transaction);
            await this.emit('social.reaction.changed', submissionId, {
                submissionId,
                userId,
                type,
            }, transaction);
            return result.rows[0];
        });
    }
    async removeVote(userId, submissionId) {
        await this.database.transaction(async (transaction) => {
            const result = await transaction.query('DELETE FROM reactions WHERE submission_id = $1 AND user_id = $2 RETURNING id', [submissionId, userId]);
            if (result.rowCount) {
                await this.emit('social.reaction.changed', submissionId, {
                    submissionId,
                    userId,
                    type: null,
                }, transaction);
            }
        });
    }
    async listComments(submissionId, limit, offset) {
        return (await this.database.query(`SELECT c.id, c.submission_id, c.user_id, c.body, c.created_at, c.parent_id,
              p.username::text, p.display_name, p.avatar_url
       FROM comments c JOIN profiles p ON p.id = c.user_id
       WHERE c.submission_id = $1 ORDER BY c.created_at, c.id LIMIT $2 OFFSET $3`, [submissionId, Math.min(Math.max(limit, 1), 200), Math.max(offset, 0)])).rows;
    }
    async addComment(userId, submissionId, body, parentId) {
        return this.database.transaction(async (transaction) => {
            const submission = await transaction.query(`SELECT s.user_id, q.title AS quest_title FROM submissions s
         JOIN user_quests uq ON uq.id = s.user_quest_id JOIN quests q ON q.id = uq.quest_id
         WHERE s.id = $1 AND s.status = 'approved' AND s.visibility = 'visible' AND s.deleted_at IS NULL`, [submissionId]);
            if (!submission.rows[0])
                throw new NotFoundException({ code: 'POST_NOT_FOUND', message: 'Post not found' });
            if (parentId) {
                const parent = await transaction.query('SELECT 1 FROM comments WHERE id = $1 AND submission_id = $2', [parentId, submissionId]);
                if (!parent.rowCount)
                    throw new ConflictException({ code: 'INVALID_COMMENT_PARENT', message: 'Reply parent belongs to another post or does not exist' });
            }
            const result = await transaction.query(`INSERT INTO comments (submission_id, user_id, body, parent_id)
         VALUES ($1, $2, $3, $4) RETURNING id, submission_id, user_id, body, created_at, parent_id`, [submissionId, userId, body.trim(), parentId ?? null]);
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
    async deleteComment(userId, role, commentId) {
        await this.database.transaction(async (transaction) => {
            const result = await transaction.query(`DELETE FROM comments WHERE id = $1 AND (user_id = $2 OR $3 IN ('moderator', 'super_admin'))
         RETURNING submission_id`, [commentId, userId, role]);
            if (!result.rows[0])
                throw new NotFoundException({ code: 'COMMENT_NOT_FOUND', message: 'Comment not found' });
            await this.emit('social.comment.changed', result.rows[0].submission_id, {
                submissionId: result.rows[0].submission_id,
                userId,
                commentId,
                operation: 'deleted',
            }, transaction);
        });
    }
    async isFollowing(userId, targetId) {
        const result = await this.database.query('SELECT 1 FROM follows WHERE follower_id = $1 AND following_id = $2', [userId, targetId]);
        return Boolean(result.rowCount);
    }
    async follow(userId, targetId) {
        if (userId === targetId)
            throw new ConflictException({ code: 'SELF_FOLLOW', message: 'You cannot follow yourself' });
        return this.database.transaction(async (transaction) => {
            const target = await transaction.query('SELECT 1 FROM profiles WHERE id = $1', [targetId]);
            if (!target.rowCount)
                throw new NotFoundException({ code: 'PROFILE_NOT_FOUND', message: 'Profile not found' });
            const blocked = await transaction.query(`SELECT 1 FROM blocked_users WHERE (blocker_id = $1 AND blocked_id = $2) OR (blocker_id = $2 AND blocked_id = $1)`, [userId, targetId]);
            if (blocked.rowCount)
                throw new ForbiddenException({ code: 'FOLLOW_BLOCKED', message: 'This follow relationship is not allowed' });
            const result = await transaction.query(`INSERT INTO follows (follower_id, following_id) VALUES ($1, $2)
         ON CONFLICT (follower_id, following_id) DO UPDATE SET follower_id = EXCLUDED.follower_id
         RETURNING id, (xmax = 0) AS inserted`, [userId, targetId]);
            if (result.rows[0].inserted) {
                const actor = await this.actorName(userId, transaction);
                await this.notification(targetId, `${actor} followed you. 👋`, 'Your party just got one person bigger.', 'new_follower', userId, userId, transaction);
            }
            await this.emit('social.follow.changed', result.rows[0].id, {
                userId,
                targetUserId: targetId,
                following: true,
            }, transaction);
            return result.rows[0].id;
        });
    }
    async unfollow(userId, targetId) {
        await this.database.transaction(async (transaction) => {
            const result = await transaction.query('DELETE FROM follows WHERE follower_id = $1 AND following_id = $2 RETURNING id', [userId, targetId]);
            if (result.rows[0]) {
                await this.emit('social.follow.changed', result.rows[0].id, {
                    userId,
                    targetUserId: targetId,
                    following: false,
                }, transaction);
            }
        });
    }
    async connections(userId, followers, limit, offset) {
        const result = await this.database.query(`SELECT p.id, p.username::text, p.display_name, p.avatar_url
       FROM follows f JOIN profiles p ON p.id = CASE WHEN $2 THEN f.follower_id ELSE f.following_id END
       WHERE CASE WHEN $2 THEN f.following_id ELSE f.follower_id END = $1
       ORDER BY f.created_at DESC LIMIT $3 OFFSET $4`, [userId, followers, Math.min(Math.max(limit, 1), 100), Math.max(offset, 0)]);
        return result.rows;
    }
    async followCounts(userId) {
        const result = await this.database.query(`SELECT count(*) FILTER (WHERE following_id = $1)::integer AS followers,
              count(*) FILTER (WHERE follower_id = $1)::integer AS following FROM follows
       WHERE follower_id = $1 OR following_id = $1`, [userId]);
        return result.rows[0];
    }
    async block(userId, targetId, reason) {
        if (userId === targetId)
            throw new ConflictException({ code: 'SELF_BLOCK', message: 'Cannot block yourself' });
        await this.database.transaction(async (transaction) => {
            const exists = await transaction.query('SELECT 1 FROM profiles WHERE id = $1', [targetId]);
            if (!exists.rowCount)
                throw new NotFoundException({ code: 'PROFILE_NOT_FOUND', message: 'Profile not found' });
            await transaction.query('INSERT INTO blocked_users (blocker_id, blocked_id) VALUES ($1, $2) ON CONFLICT DO NOTHING', [userId, targetId]);
            const report = await transaction.query(`INSERT INTO reports (reporter_id, reported_type, reported_id, reason)
         VALUES ($1, 'user', $2, $3) ON CONFLICT DO NOTHING RETURNING id`, [userId, targetId, reason.trim() || 'Blocked by user']);
            await transaction.query('DELETE FROM follows WHERE (follower_id = $1 AND following_id = $2) OR (follower_id = $2 AND following_id = $1)', [userId, targetId]);
            if (report.rows[0]) {
                await this.notifyAdminsOfReport(report.rows[0].id, 'User Blocked', `A user was blocked. Reason: ${reason.slice(0, 100)}`, transaction);
                await this.emit('report.created', report.rows[0].id, { reportId: report.rows[0].id }, transaction);
            }
            await this.emit('social.follow.changed', targetId, {
                userId,
                targetUserId: targetId,
                following: false,
            }, transaction);
        });
    }
    async unblock(userId, targetId) {
        await this.database.query('DELETE FROM blocked_users WHERE blocker_id = $1 AND blocked_id = $2', [userId, targetId]);
    }
    async blockedUsers(userId, limit, offset) {
        return (await this.database.query(`SELECT p.id, p.username::text, p.display_name, p.avatar_url, b.created_at AS blocked_at
       FROM blocked_users b JOIN profiles p ON p.id = b.blocked_id
       WHERE b.blocker_id = $1
       ORDER BY b.created_at DESC, b.id DESC LIMIT $2 OFFSET $3`, [userId, Math.min(Math.max(limit, 1), 100), Math.max(offset, 0)])).rows;
    }
    async report(userId, reportedType, reportedId, reason) {
        try {
            return await this.database.transaction(async (transaction) => {
                const result = await transaction.query(`INSERT INTO reports (reporter_id, reported_type, reported_id, reason)
           VALUES ($1, $2, $3, $4) RETURNING id`, [userId, reportedType, reportedId, reason.trim()]);
                await this.notifyAdminsOfReport(result.rows[0].id, 'New Content Report', `A user reported ${reportedType}: ${reason.slice(0, 100)}`, transaction);
                await this.emit('report.created', result.rows[0].id, { reportId: result.rows[0].id }, transaction);
                return result.rows[0].id;
            });
        }
        catch (error) {
            if (typeof error === 'object' && error !== null && 'code' in error && error.code === '23505') {
                throw new ConflictException({ code: 'DUPLICATE_REPORT', message: 'You have already reported this content' });
            }
            throw error;
        }
    }
    async setSavedPost(userId, submissionId, saved) {
        if (saved) {
            const result = await this.database.query(`INSERT INTO saved_posts (user_id, submission_id)
         SELECT $1, id FROM submissions
         WHERE id = $2 AND status = 'approved' AND visibility = 'visible' AND deleted_at IS NULL
         ON CONFLICT DO NOTHING`, [userId, submissionId]);
            if (!result.rowCount) {
                const existing = await this.database.query('SELECT 1 FROM saved_posts WHERE user_id = $1 AND submission_id = $2', [userId, submissionId]);
                if (!existing.rowCount)
                    throw new NotFoundException({ code: 'POST_NOT_FOUND', message: 'Post not found' });
            }
        }
        else
            await this.database.query('DELETE FROM saved_posts WHERE user_id = $1 AND submission_id = $2', [userId, submissionId]);
    }
    async isPostSaved(userId, submissionId) {
        const result = await this.database.query('SELECT 1 FROM saved_posts WHERE user_id = $1 AND submission_id = $2', [userId, submissionId]);
        return Boolean(result.rowCount);
    }
    async setSavedQuest(userId, questId, saved) {
        if (saved) {
            const result = await this.database.query(`INSERT INTO saved_quests (user_id, quest_id)
         SELECT $1, id FROM quests WHERE id = $2
         ON CONFLICT DO NOTHING`, [userId, questId]);
            if (!result.rowCount) {
                const existing = await this.database.query('SELECT 1 FROM saved_quests WHERE user_id = $1 AND quest_id = $2', [userId, questId]);
                if (!existing.rowCount)
                    throw new NotFoundException({ code: 'QUEST_NOT_FOUND', message: 'Quest not found' });
            }
        }
        else
            await this.database.query('DELETE FROM saved_quests WHERE user_id = $1 AND quest_id = $2', [userId, questId]);
    }
    async isQuestSaved(userId, questId) {
        const result = await this.database.query('SELECT 1 FROM saved_quests WHERE user_id = $1 AND quest_id = $2', [userId, questId]);
        return Boolean(result.rowCount);
    }
    async savedQuests(userId, limit, offset) {
        return (await this.database.query(`SELECT sq.id AS saved_id, sq.created_at AS saved_at, q.*
       FROM saved_quests sq JOIN quests q ON q.id = sq.quest_id
       WHERE sq.user_id = $1
       ORDER BY sq.created_at DESC, sq.id DESC LIMIT $2 OFFSET $3`, [userId, Math.min(Math.max(limit, 1), 100), Math.max(offset, 0)])).rows;
    }
    async savedPosts(userId, limit, offset) {
        return (await this.database.query(`SELECT sp.id AS saved_id, sp.created_at AS saved_at, s.id AS submission_id, s.media_url,
              s.media_type::text, s.visibility::text, s.status::text, q.id AS quest_id,
              q.title AS quest_title, q.description AS quest_description, q.category AS quest_category,
              q.xp_reward, p.id AS author_id, p.username::text AS author_username,
              p.display_name AS author_display_name, p.avatar_url AS author_avatar_url
       FROM saved_posts sp JOIN submissions s ON s.id = sp.submission_id
       JOIN user_quests uq ON uq.id = s.user_quest_id JOIN quests q ON q.id = uq.quest_id
       JOIN profiles p ON p.id = s.user_id
       WHERE sp.user_id = $1 AND s.status = 'approved'
         AND s.visibility = 'visible' AND s.deleted_at IS NULL
       ORDER BY sp.created_at DESC, sp.id DESC LIMIT $2 OFFSET $3`, [userId, Math.min(Math.max(limit, 1), 100), Math.max(offset, 0)])).rows;
    }
    async reactionNotifications(actorId, ownerId, submissionId, transaction) {
        const actor = await this.actorName(actorId, transaction);
        await this.notification(ownerId, `${actor} just reacted. 🗳️`, 'Someone has thoughts about your quest. Go see.', 'reaction_received', submissionId, actorId, transaction);
        const total = await transaction.query('SELECT count(*)::integer AS count FROM reactions WHERE submission_id = $1', [submissionId]);
        const copies = {
            10: ['10 reactions and counting. 🔥', 'Your post is doing numbers. Keep posting like this.'],
            25: ['25 reactions. The squad sees you. 👀', "This one's hitting. Go take a bow."],
            50: ['50 reactions. You broke containment. 🚀', 'Half a hundred people hit react. Your post is officially a moment.'],
        };
        const copy = copies[total.rows[0].count];
        if (copy)
            await this.notification(ownerId, copy[0], copy[1], 'reaction_milestone', submissionId, null, transaction);
    }
    async commentNotifications(actorId, submissionId, ownerId, questTitle, body, transaction) {
        const actor = await this.actorName(actorId, transaction);
        const short = body.length > 50 ? `${body.slice(0, 50)}…` : body;
        const mentionNames = [...body.matchAll(/@([\p{L}\p{N}_]{3,30})/gu)].map((match) => match[1].toLowerCase());
        const mentions = mentionNames.length
            ? (await transaction.query('SELECT id FROM profiles WHERE lower(username::text) = ANY($1::text[])', [mentionNames])).rows.map((row) => row.id)
            : [];
        const excluded = new Set([actorId, ...mentions]);
        if (ownerId !== actorId && !excluded.has(ownerId)) {
            await this.notification(ownerId, `${actor} dropped a comment. 💬`, `"${short}"`, 'new_comment', submissionId, actorId, transaction);
        }
        const participants = await transaction.query('SELECT DISTINCT user_id FROM comments WHERE submission_id = $1', [submissionId]);
        for (const participant of participants.rows) {
            if (participant.user_id === ownerId || excluded.has(participant.user_id))
                continue;
            excluded.add(participant.user_id);
            await this.notification(participant.user_id, `${actor} jumped into the thread. 🧵`, `"${short}"`, 'comment_reply', submissionId, actorId, transaction);
        }
        for (const mentionedId of mentions) {
            if (mentionedId === actorId)
                continue;
            await this.notification(mentionedId, `${actor} pulled you in. 📣`, `On someone's post "${questTitle}": "${short}"`, 'mention', submissionId, actorId, transaction);
        }
    }
    async actorName(id, transaction) {
        const result = await transaction.query(`SELECT COALESCE(NULLIF(display_name, ''), username::text, 'Someone') AS name FROM profiles WHERE id = $1`, [id]);
        return result.rows[0]?.name ?? 'Someone';
    }
    async notifyAdminsOfReport(id, title, body, transaction) {
        const rows = await transaction.query(`INSERT INTO notifications (user_id, title, body, type, reference_id)
       SELECT user_id, $1, $2, 'content_report', $3 FROM admins RETURNING id, user_id`, [title, body, id]);
        for (const row of rows.rows)
            await this.emitNotification(row.id, row.user_id, transaction);
    }
    async notification(userId, title, body, type, referenceId, actorId, transaction) {
        const result = await transaction.query(`INSERT INTO notifications (user_id, title, body, type, reference_id, actor_id)
       VALUES ($1, $2, $3, $4, $5, $6) RETURNING id`, [userId, title, body, type, referenceId, actorId]);
        await this.emitNotification(result.rows[0].id, userId, transaction);
    }
    async emitNotification(id, userId, transaction) {
        await transaction.query(`INSERT INTO outbox_events (aggregate_type, aggregate_id, event_type, payload)
       VALUES ('notification', $1, 'notification.created', $2::jsonb)`, [id, JSON.stringify({ notificationId: id, userId })]);
    }
    async emit(eventType, aggregateId, payload, transaction) {
        await transaction.query(`INSERT INTO outbox_events (aggregate_type, aggregate_id, event_type, payload)
       VALUES ('social', $1, $2, $3::jsonb)`, [aggregateId, eventType, JSON.stringify(payload)]);
    }
};
SocialRepository = __decorate([
    Injectable(),
    __metadata("design:paramtypes", [DatabaseService])
], SocialRepository);
export { SocialRepository };
//# sourceMappingURL=social.repository.js.map