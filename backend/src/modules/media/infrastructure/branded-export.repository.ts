import { Injectable } from '@nestjs/common';
import { DatabaseService } from '../../../infrastructure/database/database.service.js';

export type BrandedExportStatus = 'queued' | 'rendering' | 'ready' | 'failed';

export interface BrandedExportRecord {
  readonly id: string;
  readonly submission_id: string;
  readonly requested_by: string;
  readonly status: BrandedExportStatus;
  readonly object_key: string | null;
  readonly error: string | null;
  readonly created_at: Date;
  readonly completed_at: Date | null;
}

/// What the render needs to know about the post, gathered in one read.
export interface BrandedExportSource {
  readonly submissionId: string;
  readonly mediaKey: string;
  readonly mediaType: string;
  readonly questTitle: string;
  readonly username: string;
  readonly submittedAt: Date;
  readonly placeName: string | null;
  readonly countryName: string | null;
}

@Injectable()
export class BrandedExportRepository {
  constructor(private readonly database: DatabaseService) {}

  /// The post as the viewer may see it on the feed, or null.
  ///
  /// The predicate is the feed's own — approved, in the feed, visible, not
  /// deleted, not moderator-removed — because the export hands out the media
  /// bytes with the author's name on them, and that is only defensible for
  /// media every signed-in user can already watch. The author may export
  /// their own post whatever its feed state.
  async source(viewerId: string, submissionId: string): Promise<BrandedExportSource | null> {
    const result = await this.database.query<{
      id: string; media_url: string; media_type: string; quest_title: string;
      username: string; submitted_at: Date; place_name: string | null; country_name: string | null;
    }>(
      `SELECT s.id, s.media_url, s.media_type::text, q.title AS quest_title,
              p.username::text, s.submitted_at, mp.name AS place_name, mc.name AS country_name
       FROM submissions s
       JOIN user_quests uq ON uq.id = s.user_quest_id
       JOIN quests q ON q.id = uq.quest_id
       JOIN profiles p ON p.id = s.user_id
       LEFT JOIN quest_destinations d ON d.quest_id = q.id
       LEFT JOIN map_places mp ON mp.id = d.place_id AND mp.is_published
       LEFT JOIN map_countries mc ON mc.code = mp.country_code
       WHERE s.id = $1 AND s.deleted_at IS NULL AND s.moderation_removed_at IS NULL
         AND (s.user_id = $2
              OR (s.status = 'approved' AND s.show_in_feed AND s.visibility = 'visible'))`,
      [submissionId, viewerId],
    );
    const row = result.rows[0];
    if (!row) return null;
    return {
      submissionId: row.id,
      mediaKey: row.media_url,
      mediaType: row.media_type,
      questTitle: row.quest_title,
      username: row.username,
      submittedAt: row.submitted_at,
      placeName: row.place_name,
      countryName: row.country_name,
    };
  }

  /// The one row for this post, created queued if there is none. Returns
  /// whether this call created it, so the caller enqueues exactly once.
  async ensure(submissionId: string, requestedBy: string): Promise<{ record: BrandedExportRecord; created: boolean }> {
    const inserted = await this.database.query<BrandedExportRecord>(
      `INSERT INTO branded_exports (submission_id, requested_by)
       VALUES ($1, $2)
       ON CONFLICT (submission_id) DO NOTHING
       RETURNING *`,
      [submissionId, requestedBy],
    );
    if (inserted.rows[0]) return { record: inserted.rows[0], created: true };
    const existing = await this.database.query<BrandedExportRecord>(
      'SELECT * FROM branded_exports WHERE submission_id = $1',
      [submissionId],
    );
    return { record: existing.rows[0], created: false };
  }

  async find(submissionId: string): Promise<BrandedExportRecord | null> {
    const result = await this.database.query<BrandedExportRecord>(
      'SELECT * FROM branded_exports WHERE submission_id = $1',
      [submissionId],
    );
    return result.rows[0] ?? null;
  }

  /// A failed render may be asked for again: back to queued, once.
  async requeue(submissionId: string): Promise<void> {
    await this.database.query(
      `UPDATE branded_exports SET status = 'queued', error = NULL, updated_at = now()
       WHERE submission_id = $1 AND status = 'failed'`,
      [submissionId],
    );
  }

  async markRendering(id: string): Promise<boolean> {
    const result = await this.database.query(
      `UPDATE branded_exports SET status = 'rendering', updated_at = now()
       WHERE id = $1 AND status IN ('queued', 'failed')`,
      [id],
    );
    return result.rowCount === 1;
  }

  async markReady(id: string, objectKey: string): Promise<void> {
    await this.database.query(
      `UPDATE branded_exports
          SET status = 'ready', object_key = $2, error = NULL, updated_at = now(), completed_at = now()
        WHERE id = $1`,
      [id, objectKey],
    );
  }

  async markFailed(id: string, error: string): Promise<void> {
    await this.database.query(
      `UPDATE branded_exports SET status = 'failed', error = left($2, 500), updated_at = now()
        WHERE id = $1`,
      [id, error],
    );
  }
}
