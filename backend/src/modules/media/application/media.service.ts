import { randomUUID } from 'node:crypto';
import { BadRequestException, Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import type { Environment } from '../../../config/environment.js';
import { MediaRepository } from '../infrastructure/media.repository.js';
import { ObjectStorageService } from '../infrastructure/object-storage.service.js';

const extensions: Readonly<Record<string, string>> = {
  'image/jpeg': 'jpg', 'image/png': 'png', 'image/gif': 'gif', 'image/webp': 'webp',
  'video/mp4': 'mp4', 'video/quicktime': 'mov', 'video/webm': 'webm',
};

@Injectable()
export class MediaService {
  constructor(
    private readonly repository: MediaRepository,
    private readonly storage: ObjectStorageService,
    private readonly config: ConfigService<Environment, true>,
  ) {}

  async createIntent(userId: string, requestId: string, kind: 'avatar' | 'submission', contentType: string, sizeBytes: number) {
    if (kind === 'avatar' && contentType.startsWith('video/')) {
      throw new BadRequestException({ code: 'AVATAR_VIDEO_NOT_ALLOWED', message: 'Videos are not allowed for avatars' });
    }
    const maxSize = kind === 'avatar'
      ? this.config.get('MEDIA_MAX_AVATAR_BYTES', { infer: true })
      : this.config.get('MEDIA_MAX_SUBMISSION_BYTES', { infer: true });
    if (sizeBytes > maxSize) {
      const megabytes = Math.round(maxSize / (1024 * 1024));
      throw new BadRequestException({
        code: 'MEDIA_TOO_LARGE',
        message: `File exceeds the ${megabytes}MB limit`,
      });
    }

    // The repository atomically reserves quota and preserves idempotent retries.
    const maxObjects = kind === 'avatar'
      ? this.config.get('MEDIA_MAX_AVATAR_OBJECTS_PER_USER', { infer: true })
      : this.config.get('MEDIA_MAX_SUBMISSION_OBJECTS_PER_USER', { infer: true });
    const prefix = kind === 'avatar' ? 'avatars' : 'submissions';
    const generatedKey = `${prefix}/${userId}/${randomUUID()}.${extensions[contentType]}`;
    const object = await this.repository.createOrFind(
      userId, requestId, generatedKey, kind, contentType, sizeBytes, maxObjects,
      this.config.get('SIGNED_URL_TTL_SECONDS', { infer: true }),
    );
    if (object.reclaim_started_at || object.status === 'deleted' || object.status === 'rejected') {
      throw new BadRequestException({ code: 'MEDIA_INTENT_CLOSED', message: 'This upload intent is closed' });
    }
    const uploadUrl = await this.storage.presignUpload(
      object.object_key, object.content_type, Number(object.declared_size_bytes), userId,
    );
    return {
      objectId: object.id,
      key: object.object_key,
      uploadUrl,
      headers: { 'content-type': object.content_type, 'content-length': object.declared_size_bytes },
      expiresAt: this.storage.expiresAt(),
      status: object.status,
    };
  }

  async complete(userId: string, objectId: string) {
    const object = await this.repository.findOwnedForUpdate(userId, objectId);
    if (object.status === 'ready' && !object.reclaim_started_at) return { id: object.id, key: object.object_key, status: object.status };
    if (object.status !== 'pending' || object.reclaim_started_at) {
      throw new BadRequestException({ code: 'MEDIA_INTENT_CLOSED', message: 'This upload intent cannot be completed' });
    }
    try {
      const stored = await this.storage.inspect(object.object_key);
      const valid = stored.size === Number(object.declared_size_bytes)
        && stored.contentType === object.content_type
        && matchesMagic(stored.header, object.content_type);
      if (!valid) {
        if (await this.repository.markRejected(object.id)) {
          await this.storage.delete(object.object_key).catch(() => undefined);
        }
        throw new BadRequestException({ code: 'INVALID_MEDIA_UPLOAD', message: 'Uploaded content does not match its declared type or size' });
      }
      const ready = await this.repository.markReady(object.id, stored.size, stored.etag);
      return { id: ready.id, key: ready.object_key, status: ready.status };
    } catch (error) {
      if (error instanceof BadRequestException) throw error;
      throw new BadRequestException({ code: 'MEDIA_UPLOAD_NOT_FOUND', message: 'The uploaded object could not be verified' });
    }
  }

  /**
   * Presigns only the keys this caller is allowed to read.
   *
   * Unauthorised keys are omitted from the response rather than raising, which
   * keeps a batch of 100 useful when one row has since been taken down, and
   * avoids turning the endpoint into an existence oracle. Callers already
   * handle a missing entry — that is what happens today for an unparseable
   * key.
   */
  async sign(viewerId: string, isModerator: boolean, rawUrls: readonly string[]) {
    const requested = rawUrls
      .map((raw) => ({ raw, key: this.extractKey(raw) }))
      .filter((entry): entry is { raw: string; key: string } => entry.key !== null);

    const allowed = await this.repository.authorizeKeys(
      viewerId,
      [...new Set(requested.map((entry) => entry.key))],
      isModerator,
    );

    const entries = await Promise.all(
      requested
        .filter((entry) => allowed.has(entry.key))
        .map(async (entry) => [entry.raw, await this.storage.presignDownload(entry.key)] as const),
    );
    return { urls: Object.fromEntries(entries) };
  }

  async delete(userId: string, objectId: string): Promise<void> {
    const object = await this.repository.findOwnedForUpdate(userId, objectId);
    await this.repository.markDeleted(userId, objectId);
    await this.storage.delete(object.object_key);
  }

  async deleteByKey(userId: string, key: string): Promise<void> {
    const object = await this.repository.findOwnedByKey(userId, key);
    await this.repository.markDeleted(userId, object.id);
    await this.storage.delete(object.object_key);
  }

  /**
   * The shapes of key this endpoint will consider at all.
   *
   * An allowlist, and the first gate of two: passing it only means the string
   * looks like one of our object keys, never that the caller may have it —
   * `authorizeKeys` decides that. Its job is to stop a crafted path reaching
   * the signer, so a new prefix belongs here only when something actually
   * stores objects under it.
   *
   * `posters` is one of those: a still cut from a video submission. It is
   * authorised through `media_submission_links` under the submission's own
   * visibility rule, so adding the prefix widens what can be *named*, not
   * what can be seen — a poster is exactly as public as the video, and
   * exactly as private.
   */
  private static readonly KEY_SHAPE =
    /^(avatars|submissions|posters)\/[0-9a-f-]{36}\/[A-Za-z0-9._-]+$/i;

  private extractKey(raw: string): string | null {
    const value = raw.trim();
    if (MediaService.KEY_SHAPE.test(value)) return value;
    try {
      const url = new URL(value);
      const mediaPath = url.pathname.startsWith('/media/') ? decodeURIComponent(url.pathname.slice(7)) : url.pathname.replace(/^\/+/, '');
      return MediaService.KEY_SHAPE.test(mediaPath) ? mediaPath : null;
    } catch {
      return null;
    }
  }
}

export function matchesMagic(bytes: Buffer, contentType: string): boolean {
  const at = (...expected: number[]) => expected.every((value, index) => bytes[index] === value);
  if (contentType === 'image/jpeg') return at(0xff, 0xd8, 0xff);
  if (contentType === 'image/png') return at(0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a);
  if (contentType === 'image/gif') return bytes.subarray(0, 6).toString('ascii') === 'GIF87a' || bytes.subarray(0, 6).toString('ascii') === 'GIF89a';
  if (contentType === 'image/webp') return bytes.subarray(0, 4).toString('ascii') === 'RIFF' && bytes.subarray(8, 12).toString('ascii') === 'WEBP';
  if (contentType === 'video/mp4' || contentType === 'video/quicktime') return bytes.subarray(4, 8).toString('ascii') === 'ftyp';
  if (contentType === 'video/webm') return at(0x1a, 0x45, 0xdf, 0xa3);
  return false;
}
