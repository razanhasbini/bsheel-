import {
  DeleteObjectCommand,
  GetObjectCommand,
  HeadObjectCommand,
  PutObjectCommand,
  S3Client,
} from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';
import { Injectable, OnModuleDestroy, ServiceUnavailableException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import type { Environment } from '../../../config/environment.js';

@Injectable()
export class ObjectStorageService implements OnModuleDestroy {
  private readonly client?: S3Client;
  private readonly bucket?: string;
  private readonly signedUrlTtl: number;

  constructor(private readonly config: ConfigService<Environment, true>) {
    const endpoint = config.get('R2_ENDPOINT', { infer: true });
    const accessKeyId = config.get('R2_ACCESS_KEY_ID', { infer: true });
    const secretAccessKey = config.get('R2_SECRET_ACCESS_KEY', { infer: true });
    this.bucket = config.get('R2_BUCKET', { infer: true });
    this.signedUrlTtl = config.get('SIGNED_URL_TTL_SECONDS', { infer: true });
    if (endpoint && accessKeyId && secretAccessKey && this.bucket) {
      this.client = new S3Client({
        endpoint,
        region: config.get('R2_REGION', { infer: true }),
        credentials: { accessKeyId, secretAccessKey },
        forcePathStyle: config.get('S3_FORCE_PATH_STYLE', { infer: true }),
        maxAttempts: 3,
      });
    }
  }

  onModuleDestroy(): void { this.client?.destroy(); }

  async presignUpload(key: string, contentType: string, sizeBytes: number, userId: string): Promise<string> {
    return getSignedUrl(this.requiredClient(), new PutObjectCommand({
      Bucket: this.requiredBucket(), Key: key, ContentType: contentType, ContentLength: sizeBytes,
      Metadata: { 'uploaded-by': userId },
    }), { expiresIn: this.signedUrlTtl });
  }

  async presignDownload(key: string): Promise<string> {
    return getSignedUrl(this.requiredClient(), new GetObjectCommand({ Bucket: this.requiredBucket(), Key: key }), {
      expiresIn: this.signedUrlTtl,
    });
  }

  async inspect(key: string): Promise<{ size: number; contentType: string; etag?: string; header: Buffer }> {
    const client = this.requiredClient();
    const bucket = this.requiredBucket();
    const options = { abortSignal: AbortSignal.timeout(5000) };
    const head = await client.send(new HeadObjectCommand({ Bucket: bucket, Key: key }), options);
    const firstBytes = await client.send(new GetObjectCommand({ Bucket: bucket, Key: key, Range: 'bytes=0-15' }), options);
    const bytes = firstBytes.Body ? await firstBytes.Body.transformToByteArray() : new Uint8Array();
    return {
      size: Number(head.ContentLength ?? 0),
      contentType: head.ContentType ?? '',
      etag: head.ETag,
      header: Buffer.from(bytes),
    };
  }

  /// Reads a whole object into memory, refusing anything over `maxBytes`.
  ///
  /// The size is checked with a HEAD before any body is fetched, because the
  /// caller (AI proof verification, #47) runs on a queue: streaming a 50 MB
  /// video into a worker that only wanted a 3 MB image is how one oversized
  /// submission takes the whole worker down.
  async read(key: string, maxBytes: number): Promise<{ body: Buffer; contentType: string } | null> {
    const client = this.requiredClient();
    const bucket = this.requiredBucket();
    const options = { abortSignal: AbortSignal.timeout(15_000) };
    const head = await client.send(new HeadObjectCommand({ Bucket: bucket, Key: key }), options);
    if (Number(head.ContentLength ?? 0) > maxBytes) return null;
    const object = await client.send(new GetObjectCommand({ Bucket: bucket, Key: key }), options);
    if (!object.Body) return null;
    return {
      body: Buffer.from(await object.Body.transformToByteArray()),
      contentType: head.ContentType ?? '',
    };
  }

  async delete(key: string): Promise<void> {
    await this.requiredClient().send(
      new DeleteObjectCommand({ Bucket: this.requiredBucket(), Key: key }),
      { abortSignal: AbortSignal.timeout(5000) },
    );
  }

  async putPrivateJson(key: string, document: Record<string, unknown>): Promise<void> {
    await this.requiredClient().send(
      new PutObjectCommand({
        Bucket: this.requiredBucket(),
        Key: key,
        Body: JSON.stringify(document),
        ContentType: 'application/json; charset=utf-8',
        ServerSideEncryption: 'AES256',
      }),
      { abortSignal: AbortSignal.timeout(10_000) },
    );
  }

  expiresAt(): string { return new Date(Date.now() + this.signedUrlTtl * 1000).toISOString(); }

  private requiredClient(): S3Client {
    if (!this.client) {
      throw new ServiceUnavailableException({ code: 'MEDIA_STORAGE_UNAVAILABLE', message: 'Media storage is not configured' });
    }
    return this.client;
  }

  private requiredBucket(): string {
    if (!this.bucket) {
      throw new ServiceUnavailableException({ code: 'MEDIA_STORAGE_UNAVAILABLE', message: 'Media storage is not configured' });
    }
    return this.bucket;
  }
}
