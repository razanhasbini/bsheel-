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

export interface ReclaimCandidate {
  readonly id: string;
  readonly object_key: string;
  readonly reason: 'abandoned_intent' | 'rejected_upload' | 'superseded_avatar';
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

  /// How many live objects of one kind a user owns, and whether this request
  /// is a retry of an intent that already exists.
  ///
  /// One round-trip, both answers from the partial index. The retry flag
  /// matters because `createOrFind` is idempotent on `client_request_id`: a
  /// client re-requesting the same intent must not be refused for quota when
  /// it is not actually creating anything.
  ///
  /// Deleted rows are excluded, so a user who deletes and re-uploads is not
  /// permanently capped.
  ///
  /// This is deliberately not serialised against concurrent inserts. Two
  /// simultaneous uploads can both observe `limit - 1` and both proceed, so
  /// the cap can be exceeded by at most the client's concurrency. For a cap
  /// whose job is bounding runaway or scripted abuse, that is the right
  /// trade against taking a lock on every upload.
  async quotaSnapshot(
    userId: string,
    kind: 'avatar' | 'submission',
    clientRequestId: string,
  ): Promise<{ liveCount: number; isRetry: boolean }> {
    const result = await this.database.query<{ live_count: number; is_retry: boolean }>(
      `SELECT
         (SELECT count(*)::int FROM media_objects
          WHERE user_id = $1 AND kind = $2
            AND deleted_at IS NULL AND status <> 'deleted') AS live_count,
         EXISTS (
           SELECT 1 FROM media_objects
           WHERE user_id = $1 AND client_request_id = $3
         ) AS is_retry`,
      [userId, kind, clientRequestId],
    );
    const row = result.rows[0];
    return { liveCount: row.live_count, isRetry: row.is_retry };
  }

  /// Objects whose bytes nothing references any more.
  ///
  /// Three exact classes, all read from an index. None of this inspects the
  /// bucket: the deleted Cloudflare sweeper LISTed every object and compared
  /// against the database, which is O(bucket) and cannot be batched.
  ///
  /// `FOR UPDATE SKIP LOCKED` so several worker replicas can sweep at once
  /// without handing the same object to two of them.
  ///
  /// Deliberately NOT included: a ready submission object is only reclaimable
  /// once its link to a submission is modelled. `submissions.media_url` can
  /// hold a JSON array of keys, so inferring orphanhood by matching that
  /// column would classify live multi-file media as unreferenced and delete
  /// a user's proof. See 0017 for the explicit link.
  async claimReclaimable(
    graceHours: number,
    limit: number,
  ): Promise<readonly ReclaimCandidate[]> {
    const result = await this.database.query<ReclaimCandidate>(
      `WITH candidate AS (
         -- an intent the client never completed
         SELECT id, object_key, 'abandoned_intent' AS reason
         FROM media_objects
         WHERE status = 'pending'
           AND created_at < now() - make_interval(hours => $1)

         UNION ALL

         -- rejected at completion; complete() deletes the bytes first, so a
         -- row here means that delete failed and the bytes leaked
         SELECT id, object_key, 'rejected_upload' AS reason
         FROM media_objects
         WHERE status = 'rejected' AND deleted_at IS NULL

         UNION ALL

         -- a profile holds exactly one avatar_url, so changing it orphans the
         -- previous object. Single column, never a JSON array, so equality is
         -- exact and this cannot reach a live avatar.
         SELECT m.id, m.object_key, 'superseded_avatar' AS reason
         FROM media_objects m
         JOIN profiles p ON p.id = m.user_id
         WHERE m.status = 'ready'
           AND m.kind = 'avatar'
           AND m.deleted_at IS NULL
           AND m.created_at < now() - make_interval(hours => $1)
           AND (p.avatar_url IS NULL OR p.avatar_url <> m.object_key)
       )
       SELECT c.id, c.object_key, c.reason
       FROM candidate c
       JOIN media_objects locked ON locked.id = c.id
       ORDER BY c.id
       LIMIT $2
       FOR UPDATE OF locked SKIP LOCKED`,
      [graceHours, limit],
    );
    return result.rows;
  }

  /// Marks a swept object deleted. Separate from the storage delete so a
  /// failure to remove the bytes leaves the row claimable on the next pass
  /// rather than losing track of it.
  async markReclaimed(ids: readonly string[]): Promise<number> {
    if (ids.length === 0) return 0;
    const result = await this.database.query(
      `UPDATE media_objects
       SET status = 'deleted', deleted_at = now()
       WHERE id = ANY($1::uuid[])`,
      [ids],
    );
    return result.rowCount ?? 0;
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
