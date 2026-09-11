import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import exifr from 'exifr';
import sharp from 'sharp';
import type { Environment } from '../../../config/environment.js';
import { ObjectStorageService } from '../../media/infrastructure/object-storage.service.js';
import { VideoFrameExtractor } from './video-frame-extractor.js';
import {
  differenceHash,
  type ExifFacts,
  type ImageFacts,
  type PerceptualHash,
} from '../domain/proof-forensics.js';

export interface ObjectFacts {
  readonly objectKey: string;
  readonly exif: ExifFacts;
  readonly image: ImageFacts;
  /// Null when the frame is too flat to fingerprint — see `differenceHash`.
  /// Null means "cannot be compared perceptually", never "matches nothing".
  readonly perceptualHash: PerceptualHash | null;
  /// MD5 of the stored bytes, for exact-duplicate matching. Computed here
  /// rather than trusted from the storage ETag, because a multipart upload's
  /// ETag is a hash *of hashes* and is not comparable across objects.
  readonly contentHash: string;
  readonly sizeBytes: number;
  /// The decoded bytes, returned so a caller that also needs to send the
  /// image to a vision API does not read and decode the object a second time.
  readonly body: Buffer;
  /// Every frame worth judging. One element for a still image; for a video,
  /// the frames sampled across the clip. `body` is always the first of them,
  /// and it is the one the hash and EXIF facts describe.
  readonly frames: readonly Buffer[];
  readonly wasVideo: boolean;
}

/// Reads an uploaded object and measures it (#47).
///
/// This is the only place that touches image bytes. It produces facts and
/// nothing else — no verdict, no policy, no interpretation against a quest.
/// `domain/proof-forensics.ts` turns these facts into findings, which keeps
/// the judgement pure and testable and confines decode failures to here.
@Injectable()
export class MediaForensicsService {
  private readonly logger = new Logger(MediaForensicsService.name);

  constructor(
    private readonly storage: ObjectStorageService,
    private readonly video: VideoFrameExtractor,
    private readonly config: ConfigService<Environment, true>,
  ) {}

  /// Measures one object, or returns null when it cannot be read as an image.
  ///
  /// Null is an ordinary outcome, not an error: video is not decodable here,
  /// and a corrupt or oversized file must degrade to "unexamined" rather than
  /// take down the worker. The caller reports what went unexamined so a
  /// moderator is never told the whole submission was judged.
  async measure(objectKey: string, maxBytes: number): Promise<ObjectFacts | null> {
    // Video needs a bigger read budget than a still, because the whole file
    // must be decoded before any frame exists.
    const videoCap = this.config.get('AI_VERIFICATION_MAX_VIDEO_BYTES', { infer: true });

    // The read is guarded separately from the decode below, because it
    // throws rather than returning null when the object is gone — a
    // reclaimed upload, or a storage outage. That is not a fraud signal and
    // not a retryable analysis failure: it is one file this stage cannot
    // examine, and letting it escape here would abandon provenance for the
    // whole submission and leave the row to be retried forever.
    let object: Awaited<ReturnType<ObjectStorageService['read']>>;
    try {
      object = await this.storage.read(objectKey, Math.max(maxBytes, videoCap));
    } catch (error) {
      this.logger.debug(
        { objectKey, err: error instanceof Error ? error.message : String(error) },
        'Object could not be read from storage',
      );
      return null;
    }
    if (!object) return null;

    if (object.contentType.startsWith('video/')) {
      return this.measureVideo(objectKey, object.body);
    }
    // A still larger than the image budget is not analysable even though the
    // video budget let it be read.
    if (object.body.length > maxBytes) return null;

    try {
      const metadata = await sharp(object.body).metadata();
      if (!metadata.width || !metadata.height || !metadata.format) return null;

      // fit: 'fill' on purpose — the hash must describe the whole frame.
      // Preserving aspect ratio would letterbox and encode the padding.
      const bitmap = await sharp(object.body)
        .resize(9, 8, { fit: 'fill' })
        .grayscale()
        .raw()
        .toBuffer();

      return {
        objectKey,
        exif: await this.readExif(object.body),
        image: { width: metadata.width, height: metadata.height, format: metadata.format },
        perceptualHash: differenceHash(new Uint8Array(bitmap)),
        contentHash: await this.contentHash(object.body),
        sizeBytes: object.body.length,
        body: object.body,
        frames: [object.body],
        wasVideo: false,
      };
    } catch (error) {
      // A file that is not a decodable image is not a fraud signal — it is a
      // file this stage cannot read.
      this.logger.debug(
        { objectKey, err: error instanceof Error ? error.message : String(error) },
        'Object could not be measured as an image',
      );
      return null;
    }
  }

  /// Measures a video by its frames.
  ///
  /// The first frame carries the hash and the image facts, so a re-uploaded
  /// clip still matches as a near-duplicate. EXIF is read from the container
  /// rather than the frame: ffmpeg's JPEG output has none, while the source
  /// file often carries a real capture time, which is the strongest signal
  /// available and must not be thrown away by transcoding.
  private async measureVideo(objectKey: string, body: Buffer): Promise<ObjectFacts | null> {
    const frames = await this.video.extract(body);
    if (frames.length === 0) return null;

    try {
      const metadata = await sharp(frames[0]).metadata();
      if (!metadata.width || !metadata.height) return null;
      const bitmap = await sharp(frames[0])
        .resize(9, 8, { fit: 'fill' })
        .grayscale()
        .raw()
        .toBuffer();

      return {
        objectKey,
        exif: await this.readExif(body),
        image: { width: metadata.width, height: metadata.height, format: 'jpeg' },
        perceptualHash: differenceHash(new Uint8Array(bitmap)),
        // Hashed over the source bytes, not a frame, so exact-duplicate
        // detection catches the same clip re-uploaded.
        contentHash: await this.contentHash(body),
        sizeBytes: body.length,
        body: frames[0],
        frames,
        wasVideo: true,
      };
    } catch (error) {
      this.logger.debug(
        { objectKey, err: error instanceof Error ? error.message : String(error) },
        'Video frames could not be measured',
      );
      return null;
    }
  }

  /// EXIF facts, with absence treated as absence.
  ///
  /// `exifr` applies `OffsetTimeOriginal` when the file carries one, giving a
  /// true instant; without it the returned Date is a wall-clock reading with
  /// no zone. That distinction is recorded in `capturedAtHasOffset`, because
  /// the capture-window check has to be tolerant in exactly the second case
  /// or it accuses honest players in other timezones.
  private async readExif(body: Buffer): Promise<ExifFacts> {
    const parsed = await exifr
      .parse(body, {
        pick: [
          'Make', 'Model', 'Software',
          'DateTimeOriginal', 'OffsetTimeOriginal',
          'GPSLatitude', 'GPSLongitude',
        ],
      })
      .catch(() => undefined);

    if (!parsed) return { capturedAtHasOffset: false, hasGps: false };

    const capturedAt = parsed.DateTimeOriginal instanceof Date && !Number.isNaN(parsed.DateTimeOriginal.getTime())
      ? parsed.DateTimeOriginal
      : undefined;

    return {
      capturedAt,
      capturedAtHasOffset: capturedAt !== undefined && typeof parsed.OffsetTimeOriginal === 'string',
      cameraMake: typeof parsed.Make === 'string' ? parsed.Make.trim() || undefined : undefined,
      cameraModel: typeof parsed.Model === 'string' ? parsed.Model.trim() || undefined : undefined,
      software: typeof parsed.Software === 'string' ? parsed.Software.trim() || undefined : undefined,
      hasGps: parsed.GPSLatitude !== undefined && parsed.GPSLongitude !== undefined,
    };
  }

  private async contentHash(body: Buffer): Promise<string> {
    const { createHash } = await import('node:crypto');
    return createHash('md5').update(body).digest('hex');
  }
}
