var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
var __metadata = (this && this.__metadata) || function (k, v) {
    if (typeof Reflect === "object" && typeof Reflect.metadata === "function") return Reflect.metadata(k, v);
};
import { DeleteObjectCommand, GetObjectCommand, HeadObjectCommand, PutObjectCommand, S3Client, } from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';
import { Injectable, ServiceUnavailableException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
let ObjectStorageService = class ObjectStorageService {
    config;
    client;
    bucket;
    signedUrlTtl;
    constructor(config) {
        this.config = config;
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
    onModuleDestroy() { this.client?.destroy(); }
    async presignUpload(key, contentType, sizeBytes, userId) {
        return getSignedUrl(this.requiredClient(), new PutObjectCommand({
            Bucket: this.requiredBucket(), Key: key, ContentType: contentType, ContentLength: sizeBytes,
            Metadata: { 'uploaded-by': userId },
        }), { expiresIn: this.signedUrlTtl });
    }
    async presignDownload(key) {
        return getSignedUrl(this.requiredClient(), new GetObjectCommand({ Bucket: this.requiredBucket(), Key: key }), {
            expiresIn: this.signedUrlTtl,
        });
    }
    async inspect(key) {
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
    async delete(key) {
        await this.requiredClient().send(new DeleteObjectCommand({ Bucket: this.requiredBucket(), Key: key }), { abortSignal: AbortSignal.timeout(5000) });
    }
    async putPrivateJson(key, document) {
        await this.requiredClient().send(new PutObjectCommand({
            Bucket: this.requiredBucket(),
            Key: key,
            Body: JSON.stringify(document),
            ContentType: 'application/json; charset=utf-8',
            ServerSideEncryption: 'AES256',
        }), { abortSignal: AbortSignal.timeout(10_000) });
    }
    expiresAt() { return new Date(Date.now() + this.signedUrlTtl * 1000).toISOString(); }
    requiredClient() {
        if (!this.client) {
            throw new ServiceUnavailableException({ code: 'MEDIA_STORAGE_UNAVAILABLE', message: 'Media storage is not configured' });
        }
        return this.client;
    }
    requiredBucket() {
        if (!this.bucket) {
            throw new ServiceUnavailableException({ code: 'MEDIA_STORAGE_UNAVAILABLE', message: 'Media storage is not configured' });
        }
        return this.bucket;
    }
};
ObjectStorageService = __decorate([
    Injectable(),
    __metadata("design:paramtypes", [ConfigService])
], ObjectStorageService);
export { ObjectStorageService };
//# sourceMappingURL=object-storage.service.js.map