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
let MediaRepository = class MediaRepository {
    database;
    constructor(database) {
        this.database = database;
    }
    async createOrFind(userId, clientRequestId, objectKey, kind, contentType, sizeBytes) {
        const result = await this.database.query(`INSERT INTO media_objects
         (user_id, client_request_id, object_key, kind, content_type, declared_size_bytes)
       VALUES ($1, $2, $3, $4, $5, $6)
       ON CONFLICT (user_id, client_request_id) DO UPDATE
       SET client_request_id = EXCLUDED.client_request_id
       RETURNING *`, [userId, clientRequestId, objectKey, kind, contentType, sizeBytes]);
        return result.rows[0];
    }
    async findOwnedForUpdate(userId, id) {
        const result = await this.database.query('SELECT * FROM media_objects WHERE id = $1 AND user_id = $2', [id, userId]);
        const object = result.rows[0];
        if (!object)
            throw new NotFoundException({ code: 'MEDIA_OBJECT_NOT_FOUND', message: 'Media object not found' });
        return object;
    }
    async findOwnedByKey(userId, key) {
        const result = await this.database.query('SELECT * FROM media_objects WHERE object_key = $1 AND user_id = $2', [key, userId]);
        const object = result.rows[0];
        if (!object)
            throw new NotFoundException({ code: 'MEDIA_OBJECT_NOT_FOUND', message: 'Media object not found' });
        return object;
    }
    async markReady(id, storedSize, etag) {
        return this.database.transaction(async (transaction) => {
            const result = await transaction.query(`UPDATE media_objects SET status = 'ready', stored_size_bytes = $2, etag = $3,
           completed_at = COALESCE(completed_at, now())
         WHERE id = $1 AND status IN ('pending', 'ready') RETURNING *`, [id, storedSize, etag ?? null]);
            const object = result.rows[0];
            if (!object)
                throw new NotFoundException({ code: 'MEDIA_OBJECT_NOT_FOUND', message: 'Media object is not completable' });
            await transaction.query(`INSERT INTO outbox_events (aggregate_type, aggregate_id, event_type, payload)
         VALUES ('media', $1, 'media.uploaded', $2::jsonb)`, [id, JSON.stringify({ mediaObjectId: id, key: object.object_key, kind: object.kind })]);
            return object;
        });
    }
    async markRejected(id) {
        await this.database.query("UPDATE media_objects SET status = 'rejected' WHERE id = $1 AND status = 'pending'", [id]);
    }
    async markDeleted(userId, id) {
        await this.database.transaction(async (transaction) => {
            const result = await transaction.query(`UPDATE media_objects SET status = 'deleted', deleted_at = now()
         WHERE id = $1 AND user_id = $2 AND status <> 'deleted'
         RETURNING object_key, kind`, [id, userId]);
            if (!result.rows[0])
                throw new NotFoundException({ code: 'MEDIA_OBJECT_NOT_FOUND', message: 'Media object not found' });
            if (result.rows[0].kind === 'avatar') {
                await transaction.query('UPDATE profiles SET avatar_url = NULL WHERE id = $1 AND avatar_url = $2', [userId, result.rows[0].object_key]);
            }
        });
    }
};
MediaRepository = __decorate([
    Injectable(),
    __metadata("design:paramtypes", [DatabaseService])
], MediaRepository);
export { MediaRepository };
//# sourceMappingURL=media.repository.js.map