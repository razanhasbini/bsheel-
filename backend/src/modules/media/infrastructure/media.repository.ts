import { BadRequestException, Injectable, NotFoundException } from '@nestjs/common';
import { randomUUID } from 'node:crypto';
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
  readonly reclaim_started_at: Date | null;
}

export interface ReclaimCandidate {
  readonly id: string;
  readonly object_key: string;
  readonly reason: 'abandoned_intent' | 'rejected_upload' | 'superseded_avatar' | 'orphan_submission' | 'user_deleted';
  readonly reclaim_token: string;
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
    maxObjects: number,
    uploadTtlSeconds: number,
  ): Promise<MediaObjectRecord> {
    return this.database.transaction(async (transaction) => {
      // Serialize reservations, not a snapshot followed by an unlocked insert.
      await transaction.query('SELECT pg_advisory_xact_lock(hashtextextended($1, 0))', [`media-quota:${userId}`]);
      const existing = await transaction.query<MediaObjectRecord>(
        'SELECT * FROM media_objects WHERE user_id = $1 AND client_request_id = $2 FOR UPDATE',
        [userId, clientRequestId],
      );
      const prior = existing.rows[0];
      if (prior) {
        if (prior.reclaim_started_at || prior.status === 'deleted' || prior.status === 'rejected') {
          throw new BadRequestException({ code: 'MEDIA_INTENT_CLOSED', message: 'This upload intent is closed' });
        }
        if (prior.kind !== kind || prior.content_type !== contentType || Number(prior.declared_size_bytes) !== sizeBytes) {
          throw new BadRequestException({ code: 'MEDIA_INTENT_CONFLICT', message: 'An upload retry must use the original file parameters' });
        }
        await transaction.query(
          'UPDATE media_objects SET upload_expires_at = now() + make_interval(secs => $2) WHERE id = $1',
          [prior.id, uploadTtlSeconds],
        );
        return prior;
      }
      const count = await transaction.query<{ count: number }>(
        `SELECT count(*)::int AS count FROM media_objects
         WHERE user_id = $1 AND kind = $2 AND deleted_at IS NULL AND status <> 'deleted'`,
        [userId, kind],
      );
      if (count.rows[0].count >= maxObjects) {
        throw new BadRequestException({ code: 'MEDIA_QUOTA_EXCEEDED', message: `You have reached the limit of ${maxObjects} stored ${kind === 'avatar' ? 'avatars' : 'files'}` });
      }
      const result = await transaction.query<MediaObjectRecord>(
        `INSERT INTO media_objects
           (user_id, client_request_id, object_key, kind, content_type, declared_size_bytes, upload_expires_at)
         VALUES ($1, $2, $3, $4, $5, $6, now() + make_interval(secs => $7)) RETURNING *`,
        [userId, clientRequestId, objectKey, kind, contentType, sizeBytes, uploadTtlSeconds],
      );
      return result.rows[0];
    });
  }

  // Both selection and the post-lock recheck use this closed, static predicate.
  // Ready objects use completion/upload-grant age, not just intent age.
  private readonly reclaimPredicate = `m.storage_deleted_at IS NULL
    AND (m.reclaim_lease_until IS NULL OR m.reclaim_lease_until < now())
    AND m.upload_expires_at < now() - make_interval(hours => $1)
    AND (
      m.reclaim_started_at IS NOT NULL
      OR m.status IN ('pending', 'rejected')
      OR (m.status = 'ready' AND COALESCE(m.completed_at, m.created_at) < now() - make_interval(hours => $1)
        AND (
          (m.kind = 'avatar' AND NOT EXISTS (SELECT 1 FROM profiles p WHERE p.avatar_url = m.object_key))
          OR (m.kind = 'submission' AND NOT EXISTS (
            SELECT 1 FROM media_submission_links link WHERE link.media_object_id = m.id
          ))
        ))
    )`;

  /// Commit a permanent tombstone before external I/O. Bind/complete operations
  /// lock the same row and reject tombstones. A fresh statement after acquiring
  /// locks sees references committed by a binder after our selection snapshot.
  /// The lease only avoids duplicate work; even a crashed/late worker is safe
  /// because a tombstoned object can never become referenced again.
  async claimReclaimable(
    graceHours: number,
    limit: number,
  ): Promise<readonly ReclaimCandidate[]> {
    return this.database.transaction(async (transaction) => {
      const candidates = await transaction.query<{ id: string }>(
        `SELECT m.id FROM media_objects m WHERE ${this.reclaimPredicate}
         ORDER BY m.created_at, m.id LIMIT $2 FOR UPDATE OF m SKIP LOCKED`,
        [graceHours, limit],
      );
      if (!candidates.rowCount) return [];
      const result = await transaction.query<ReclaimCandidate>(
        `UPDATE media_objects m SET reclaim_started_at = COALESCE(m.reclaim_started_at, now()),
           reclaim_token = $3, reclaim_lease_until = now() + interval '30 minutes',
           reclaim_reason = COALESCE(m.reclaim_reason, CASE
             WHEN m.status = 'pending' THEN 'abandoned_intent'
             WHEN m.status = 'rejected' THEN 'rejected_upload'
             WHEN m.kind = 'avatar' THEN 'superseded_avatar'
             ELSE 'orphan_submission' END)
         WHERE m.id = ANY($2::uuid[]) AND ${this.reclaimPredicate}
         RETURNING m.id, m.object_key, m.reclaim_reason AS reason, m.reclaim_token`,
        [graceHours, candidates.rows.map((row) => row.id), randomUUID()],
      );
      return result.rows;
    });
  }

  /// Marks a swept object deleted. Separate from the storage delete so a
  /// failure to remove the bytes leaves the row claimable on the next pass
  /// rather than losing track of it.
  async markReclaimed(candidates: readonly ReclaimCandidate[]): Promise<number> {
    if (candidates.length === 0) return 0;
    const result = await this.database.query(
      `UPDATE media_objects
       SET status = 'deleted', deleted_at = COALESCE(deleted_at, now()), storage_deleted_at = now(),
           reclaim_lease_until = NULL
       WHERE (id, reclaim_token) IN (SELECT * FROM unnest($1::uuid[], $2::uuid[]))
         AND reclaim_started_at IS NOT NULL AND storage_deleted_at IS NULL`,
      [candidates.map((candidate) => candidate.id), candidates.map((candidate) => candidate.reclaim_token)],
    );
    return result.rowCount ?? 0;
  }

  async releaseReclaim(candidate: ReclaimCandidate): Promise<void> {
    await this.database.query(
      'UPDATE media_objects SET reclaim_lease_until = NULL WHERE id = $1 AND reclaim_token = $2 AND storage_deleted_at IS NULL',
      [candidate.id, candidate.reclaim_token],
    );
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
         WHERE id = $1 AND status = 'pending' AND reclaim_started_at IS NULL RETURNING *`,
        [id, storedSize, etag ?? null],
      );
      const object = result.rows[0];
      if (!object) {
        const prior = await transaction.query<MediaObjectRecord>(
          "SELECT * FROM media_objects WHERE id = $1 AND status = 'ready' AND reclaim_started_at IS NULL", [id],
        );
        if (prior.rows[0]) return prior.rows[0];
        throw new BadRequestException({ code: 'MEDIA_INTENT_CLOSED', message: 'Media object is not completable' });
      }
      await transaction.query(
        `INSERT INTO outbox_events (aggregate_type, aggregate_id, event_type, payload)
         VALUES ('media', $1, 'media.uploaded', $2::jsonb)`,
        [id, JSON.stringify({ mediaObjectId: id, key: object.object_key, kind: object.kind })],
      );
      return object;
    });
  }

  async markRejected(id: string): Promise<boolean> {
    const result = await this.database.query("UPDATE media_objects SET status = 'rejected' WHERE id = $1 AND status = 'pending' AND reclaim_started_at IS NULL", [id]);
    return (result.rowCount ?? 0) > 0;
  }

  async markDeleted(userId: string, id: string): Promise<void> {
    await this.database.transaction(async (transaction) => {
      const result = await transaction.query<{ object_key: string; kind: string }>(
        `UPDATE media_objects SET status = 'deleted', deleted_at = COALESCE(deleted_at, now()),
           reclaim_started_at = COALESCE(reclaim_started_at, now()),
           reclaim_reason = COALESCE(reclaim_reason, 'user_deleted')
         WHERE id = $1 AND user_id = $2
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
