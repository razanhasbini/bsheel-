import { Injectable, NotFoundException } from '@nestjs/common';
import { DatabaseService } from '../../../infrastructure/database/database.service.js';

export interface MediaObjectRecord {
  readonly id: string;
  readonly user_id: string;
  readonly client_request_id: string;
  readonly object_key: string;
  readonly kind: 'avatar' | 'submission';
  readonly status: 'pending' | 'ready' | 'rejected' | 'deleted';
  readonly content_type: string;
  readonly declared_size_bytes: string;
  readonly stored_size_bytes: string | null;
  readonly etag: string | null;
  readonly created_at: Date;
  readonly completed_at: Date | null;
}

@Injectable()
export class MediaRepository {
  constructor(private readonly database: DatabaseService) {}

  async createOrFind(
    userId: string,
    clientRequestId: string,
    objectKey: string,
    kind: 'avatar' | 'submission',
    contentType: string,
    sizeBytes: number,
  ): Promise<MediaObjectRecord> {
    const result = await this.database.query<MediaObjectRecord>(
      `INSERT INTO media_objects
         (user_id, client_request_id, object_key, kind, content_type, declared_size_bytes)
       VALUES ($1, $2, $3, $4, $5, $6)
       ON CONFLICT (user_id, client_request_id) DO UPDATE
       SET client_request_id = EXCLUDED.client_request_id
       RETURNING *`,
      [userId, clientRequestId, objectKey, kind, contentType, sizeBytes],
    );
    return result.rows[0];
  }

  async findOwnedForUpdate(userId: string, id: string): Promise<MediaObjectRecord> {
    const result = await this.database.query<MediaObjectRecord>(
      'SELECT * FROM media_objects WHERE id = $1 AND user_id = $2',
      [id, userId],
    );
    const object = result.rows[0];
    if (!object) throw new NotFoundException({ code: 'MEDIA_OBJECT_NOT_FOUND', message: 'Media object not found' });
    return object;
  }

  async findOwnedByKey(userId: string, key: string): Promise<MediaObjectRecord> {
    const result = await this.database.query<MediaObjectRecord>(
      'SELECT * FROM media_objects WHERE object_key = $1 AND user_id = $2',
      [key, userId],
    );
    const object = result.rows[0];
    if (!object) throw new NotFoundException({ code: 'MEDIA_OBJECT_NOT_FOUND', message: 'Media object not found' });
    return object;
  }

  async markReady(id: string, storedSize: number, etag?: string): Promise<MediaObjectRecord> {
    return this.database.transaction(async (transaction) => {
      const result = await transaction.query<MediaObjectRecord>(
        `UPDATE media_objects SET status = 'ready', stored_size_bytes = $2, etag = $3,
           completed_at = COALESCE(completed_at, now())
         WHERE id = $1 AND status IN ('pending', 'ready') RETURNING *`,
        [id, storedSize, etag ?? null],
      );
      const object = result.rows[0];
      if (!object) throw new NotFoundException({ code: 'MEDIA_OBJECT_NOT_FOUND', message: 'Media object is not completable' });
      await transaction.query(
        `INSERT INTO outbox_events (aggregate_type, aggregate_id, event_type, payload)
         VALUES ('media', $1, 'media.uploaded', $2::jsonb)`,
        [id, JSON.stringify({ mediaObjectId: id, key: object.object_key, kind: object.kind })],
      );
      return object;
    });
  }

  async markRejected(id: string): Promise<void> {
    await this.database.query("UPDATE media_objects SET status = 'rejected' WHERE id = $1 AND status = 'pending'", [id]);
  }

  async markDeleted(userId: string, id: string): Promise<void> {
    await this.database.transaction(async (transaction) => {
      const result = await transaction.query<{ object_key: string; kind: string }>(
        `UPDATE media_objects SET status = 'deleted', deleted_at = now()
         WHERE id = $1 AND user_id = $2 AND status <> 'deleted'
         RETURNING object_key, kind`,
        [id, userId],
      );
      if (!result.rows[0]) throw new NotFoundException({ code: 'MEDIA_OBJECT_NOT_FOUND', message: 'Media object not found' });
      if (result.rows[0].kind === 'avatar') {
        await transaction.query(
          'UPDATE profiles SET avatar_url = NULL WHERE id = $1 AND avatar_url = $2',
          [userId, result.rows[0].object_key],
        );
      }
    });
  }
}
