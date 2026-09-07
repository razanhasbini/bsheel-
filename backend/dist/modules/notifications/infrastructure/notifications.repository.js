var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
var __metadata = (this && this.__metadata) || function (k, v) {
    if (typeof Reflect === "object" && typeof Reflect.metadata === "function") return Reflect.metadata(k, v);
};
import { Injectable, NotFoundException } from '@nestjs/common';
import { DatabaseService } from '../../../infrastructure/database/database.service.js';
let NotificationsRepository = class NotificationsRepository {
    database;
    constructor(database) {
        this.database = database;
    }
    async list(userId, limit, cursor) {
        const result = await this.database.query(`SELECT n.id, n.user_id, n.title, n.body, n.type, n.reference_id, n.is_read,
              n.created_at, n.actor_id,
              CASE WHEN actor.id IS NULL THEN NULL ELSE json_build_object(
                'username', actor.username::text,
                'avatar_url', actor.avatar_url
              ) END AS actor_profile
       FROM notifications n
       LEFT JOIN profiles actor ON actor.id = n.actor_id
       WHERE n.user_id = $1
         AND ($3::timestamptz IS NULL OR (n.created_at, n.id) < ($3::timestamptz, $4::uuid))
       ORDER BY n.created_at DESC, n.id DESC
       LIMIT $2`, [userId, limit + 1, cursor?.createdAt ?? null, cursor?.id ?? null]);
        return result.rows;
    }
    async unreadCount(userId) {
        const result = await this.database.query('SELECT count(*)::integer AS count FROM notifications WHERE user_id = $1 AND NOT is_read', [userId]);
        return result.rows[0].count;
    }
    async markRead(userId, notificationId) {
        await this.database.transaction(async (transaction) => {
            const result = await transaction.query('UPDATE notifications SET is_read = true WHERE id = $1 AND user_id = $2', [notificationId, userId]);
            if (!result.rowCount)
                throw new NotFoundException({ code: 'NOTIFICATION_NOT_FOUND', message: 'Notification not found' });
            await this.emitReadEvent(userId, notificationId, transaction);
        });
    }
    async markAllRead(userId) {
        return this.database.transaction(async (transaction) => {
            const result = await transaction.query('UPDATE notifications SET is_read = true WHERE user_id = $1 AND NOT is_read', [userId]);
            if (result.rowCount)
                await this.emitReadEvent(userId, null, transaction);
            return result.rowCount ?? 0;
        });
    }
    async upsertDeviceToken(userId, tokenHash, encryptedToken, platform) {
        const result = await this.database.query(`INSERT INTO device_tokens (user_id, token_hash, encrypted_token, platform)
       VALUES ($1, $2, $3, $4)
       ON CONFLICT (token_hash) DO UPDATE
       SET user_id = EXCLUDED.user_id, encrypted_token = EXCLUDED.encrypted_token,
           platform = EXCLUDED.platform, last_seen_at = now()
       RETURNING id`, [userId, tokenHash, encryptedToken, platform]);
        return result.rows[0].id;
    }
    async deleteDeviceToken(userId, tokenHash) {
        await this.database.query('DELETE FROM device_tokens WHERE user_id = $1 AND token_hash = $2', [userId, tokenHash]);
    }
    async emitReadEvent(userId, notificationId, transaction) {
        await transaction.query(`INSERT INTO outbox_events (aggregate_type, aggregate_id, event_type, payload)
       VALUES ('user', $1, 'notification.read', $2::jsonb)`, [userId, JSON.stringify({ userId, notificationId })]);
    }
};
NotificationsRepository = __decorate([
    Injectable(),
    __metadata("design:paramtypes", [DatabaseService])
], NotificationsRepository);
export { NotificationsRepository };
//# sourceMappingURL=notifications.repository.js.map