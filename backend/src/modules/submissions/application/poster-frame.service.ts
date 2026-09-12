import { createHash, randomUUID } from 'node:crypto';
import { Injectable, Logger } from '@nestjs/common';
import { DatabaseService } from '../../../infrastructure/database/database.service.js';
import { ObjectStorageService } from '../../media/infrastructure/object-storage.service.js';
import { VideoFrameExtractor } from '../infrastructure/video-frame-extractor.js';

/// How many videos one sweep will decode. ffmpeg is CPU-bound and shares the
/// worker with proof verification, so this is deliberately small: a backlog
/// drains over several sweeps instead of pinning a core for minutes.
const BATCH = 10;

/// The largest video worth decoding a poster from. A frame is a frame
/// whatever the file weighs, but reading a gigabyte into memory to cut a
/// 640px JPEG is not a trade worth making inside a queue worker.
const MAX_VIDEO_BYTES = 256 * 1024 * 1024;

/**
 * Cuts a still frame from each video submission so surfaces that need a
 * picture have one.
 *
 * The map's moments layer is the reason this exists. It draws a square per
 * approved submission, and for a video that square was a play glyph on the
 * quest's category tint — so a board with video proof on it looked like a
 * board of broken green tiles, and the layer's whole job is to make somebody
 * want to tap.
 *
 * **A sweep rather than an event.** Posters are wanted for submissions that
 * already exist as much as for new ones, and a video that failed to decode
 * once may decode after an ffmpeg upgrade. A sweep over the partial index
 * (`submissions_poster_pending_idx`) covers backfill, retry and steady state
 * with one code path; an outbox consumer would have covered only the third
 * and needed a separate backfill script that would then rot.
 *
 * **Failure is not recorded as failure.** A video whose frame cannot be cut
 * simply keeps `poster_object_key = NULL` and is retried on the next sweep.
 * That is cheap because the set is small and bounded, and it means a
 * deployment without ffmpeg (the capability is probed, not required) does
 * nothing at all rather than marking every video permanently posterless —
 * which is what a `poster_failed_at` column would have done on the laptop
 * where ffmpeg simply was not installed yet.
 */
@Injectable()
export class PosterFrameService {
  private readonly logger = new Logger(PosterFrameService.name);

  constructor(
    private readonly database: DatabaseService,
    private readonly storage: ObjectStorageService,
    private readonly video: VideoFrameExtractor,
  ) {}

  async sweep(): Promise<{ considered: number; written: number }> {
    if (!(await this.video.isAvailable())) return { considered: 0, written: 0 };

    const pending = await this.database.query<{ id: string; user_id: string; media_url: string }>(
      `SELECT id, user_id, media_url
         FROM submissions
        WHERE media_type = 'video'
          AND poster_object_key IS NULL
          AND deleted_at IS NULL
          -- A JSON array of keys is a multi-file submission; the poster
          -- would be ambiguous, and no map tile draws one today.
          AND media_url NOT LIKE '[%'
        ORDER BY submitted_at DESC
        LIMIT $1`,
      [BATCH],
    );

    let written = 0;
    for (const row of pending.rows) {
      if (await this.generate(row)) written += 1;
    }
    if (pending.rows.length > 0) {
      this.logger.debug({ considered: pending.rows.length, written }, 'Poster sweep finished');
    }
    return { considered: pending.rows.length, written };
  }

  private async generate(row: { id: string; user_id: string; media_url: string }): Promise<boolean> {
    const object = await this.storage.read(row.media_url, MAX_VIDEO_BYTES).catch(() => null);
    if (!object) return false;

    const frame = await this.video.poster(object.body);
    if (!frame) return false;

    // Beside the video it came from, so an operator reading the bucket can
    // see what a key belongs to without a database round trip.
    const key = `posters/${row.user_id}/${randomUUID()}.jpg`;
    await this.storage.putObject(key, frame, 'image/jpeg');

    const md5 = createHash('md5').update(frame).digest('hex');
    await this.database.transaction(async (client) => {
      // kind 'poster' keeps this out of the forensics indexes, which are all
      // partial on kind = 'submission'. A generated frame hashed into the
      // duplicate-detection space could match a real photograph and accuse
      // its author of stealing proof we made ourselves.
      await client.query(
        `INSERT INTO media_objects
           (user_id, client_request_id, object_key, kind, status, content_type,
            declared_size_bytes, stored_size_bytes, content_md5, submission_id,
            upload_expires_at, completed_at)
         VALUES ($1, gen_random_uuid(), $2, 'poster', 'ready', 'image/jpeg',
                 $3, $3, $4, $5, now(), now())`,
        [row.user_id, key, frame.length, md5, row.id],
      );
      // The link is what makes the poster signable: authorizeKeys grants a
      // linked object under the submission's own visibility predicate, so a
      // poster is exactly as public as the video, with no new rule.
      await client.query(
        `INSERT INTO media_submission_links (media_object_id, submission_id)
         SELECT id, $2 FROM media_objects WHERE object_key = $1
         ON CONFLICT DO NOTHING`,
        [key, row.id],
      );
      await client.query(
        `UPDATE submissions SET poster_object_key = $2 WHERE id = $1 AND poster_object_key IS NULL`,
        [row.id, key],
      );
    });
    return true;
  }
}
