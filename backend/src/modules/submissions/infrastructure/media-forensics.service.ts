import { Injectable, Logger } from '@nestjs/common';
import exifr from 'exifr';
import sharp from 'sharp';
import { ObjectStorageService } from '../../media/infrastructure/object-storage.service.js';
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
  readonly perceptualHash: PerceptualHash;
  /// MD5 of the stored bytes, for exact-duplicate matching. Computed here
  /// rather than trusted from the storage ETag, because a multipart upload's
  /// ETag is a hash *of hashes* and is not comparable across objects.
  readonly contentHash: string;
  readonly sizeBytes: number;
  /// The decoded bytes, returned so a caller that also needs to send the
  /// image to a vision API does not read and decode the object a second time.
  readonly body: Buffer;
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

  constructor(private readonly storage: ObjectStorageService) {}

  /// Measures one object, or returns null when it cannot be read as an image.
  ///
  /// Null is an ordinary outcome, not an error: video is not decodable here,
  /// and a corrupt or oversized file must degrade to "unexamined" rather than
  /// take down the worker. The caller reports what went unexamined so a
  /// moderator is never told the whole submission was judged.
  async measure(objectKey: string, maxBytes: number): Promise<ObjectFacts | null> {
    const object = await this.storage.read(objectKey, maxBytes);
    if (!object) return null;

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
