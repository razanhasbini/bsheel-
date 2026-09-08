var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
var __metadata = (this && this.__metadata) || function (k, v) {
    if (typeof Reflect === "object" && typeof Reflect.metadata === "function") return Reflect.metadata(k, v);
};
import { randomUUID } from 'node:crypto';
import { BadRequestException, Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { MediaRepository } from '../infrastructure/media.repository.js';
import { ObjectStorageService } from '../infrastructure/object-storage.service.js';
const extensions = {
    'image/jpeg': 'jpg', 'image/png': 'png', 'image/gif': 'gif', 'image/webp': 'webp',
    'video/mp4': 'mp4', 'video/quicktime': 'mov', 'video/webm': 'webm',
};
let MediaService = class MediaService {
    repository;
    storage;
    config;
    constructor(repository, storage, config) {
        this.repository = repository;
        this.storage = storage;
        this.config = config;
    }
    async createIntent(userId, requestId, kind, contentType, sizeBytes) {
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
        const maxObjects = kind === 'avatar'
            ? this.config.get('MEDIA_MAX_AVATAR_OBJECTS_PER_USER', { infer: true })
            : this.config.get('MEDIA_MAX_SUBMISSION_OBJECTS_PER_USER', { infer: true });
        const quota = await this.repository.quotaSnapshot(userId, kind, requestId);
        if (!quota.isRetry && quota.liveCount >= maxObjects) {
            throw new BadRequestException({
                code: 'MEDIA_QUOTA_EXCEEDED',
                message: `You have reached the limit of ${maxObjects} stored ${kind === 'avatar' ? 'avatars' : 'files'}`,
            });
        }
        const prefix = kind === 'avatar' ? 'avatars' : 'submissions';
        const generatedKey = `${prefix}/${userId}/${randomUUID()}.${extensions[contentType]}`;
        const object = await this.repository.createOrFind(userId, requestId, generatedKey, kind, contentType, sizeBytes);
        if (object.status === 'deleted' || object.status === 'rejected') {
            throw new BadRequestException({ code: 'MEDIA_INTENT_CLOSED', message: 'This upload intent is closed' });
        }
        const uploadUrl = await this.storage.presignUpload(object.object_key, object.content_type, Number(object.declared_size_bytes), userId);
        return {
            objectId: object.id,
            key: object.object_key,
            uploadUrl,
            headers: { 'content-type': object.content_type, 'content-length': object.declared_size_bytes },
            expiresAt: this.storage.expiresAt(),
            status: object.status,
        };
    }
    async complete(userId, objectId) {
        const object = await this.repository.findOwnedForUpdate(userId, objectId);
        if (object.status === 'ready')
            return { id: object.id, key: object.object_key, status: object.status };
        if (object.status !== 'pending') {
            throw new BadRequestException({ code: 'MEDIA_INTENT_CLOSED', message: 'This upload intent cannot be completed' });
        }
        try {
            const stored = await this.storage.inspect(object.object_key);
            const valid = stored.size === Number(object.declared_size_bytes)
                && stored.contentType === object.content_type
                && matchesMagic(stored.header, object.content_type);
            if (!valid) {
                await this.storage.delete(object.object_key).catch(() => undefined);
                await this.repository.markRejected(object.id);
                throw new BadRequestException({ code: 'INVALID_MEDIA_UPLOAD', message: 'Uploaded content does not match its declared type or size' });
            }
            const ready = await this.repository.markReady(object.id, stored.size, stored.etag);
            return { id: ready.id, key: ready.object_key, status: ready.status };
        }
        catch (error) {
            if (error instanceof BadRequestException)
                throw error;
            throw new BadRequestException({ code: 'MEDIA_UPLOAD_NOT_FOUND', message: 'The uploaded object could not be verified' });
        }
    }
    async sign(rawUrls) {
        const entries = await Promise.all(rawUrls.map(async (raw) => {
            const key = this.extractKey(raw);
            return key ? [raw, await this.storage.presignDownload(key)] : null;
        }));
        return { urls: Object.fromEntries(entries.filter((entry) => entry !== null)) };
    }
    async delete(userId, objectId) {
        const object = await this.repository.findOwnedForUpdate(userId, objectId);
        await this.storage.delete(object.object_key);
        await this.repository.markDeleted(userId, objectId);
    }
    async deleteByKey(userId, key) {
        const object = await this.repository.findOwnedByKey(userId, key);
        if (object.status === 'deleted')
            return;
        await this.storage.delete(object.object_key);
        await this.repository.markDeleted(userId, object.id);
    }
    extractKey(raw) {
        const value = raw.trim();
        if (/^(avatars|submissions)\/[0-9a-f-]{36}\/[A-Za-z0-9._-]+$/i.test(value))
            return value;
        try {
            const url = new URL(value);
            const mediaPath = url.pathname.startsWith('/media/') ? decodeURIComponent(url.pathname.slice(7)) : url.pathname.replace(/^\/+/, '');
            return /^(avatars|submissions)\/[0-9a-f-]{36}\/[A-Za-z0-9._-]+$/i.test(mediaPath) ? mediaPath : null;
        }
        catch {
            return null;
        }
    }
};
MediaService = __decorate([
    Injectable(),
    __metadata("design:paramtypes", [MediaRepository,
        ObjectStorageService,
        ConfigService])
], MediaService);
export { MediaService };
export function matchesMagic(bytes, contentType) {
    const at = (...expected) => expected.every((value, index) => bytes[index] === value);
    if (contentType === 'image/jpeg')
        return at(0xff, 0xd8, 0xff);
    if (contentType === 'image/png')
        return at(0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a);
    if (contentType === 'image/gif')
        return bytes.subarray(0, 6).toString('ascii') === 'GIF87a' || bytes.subarray(0, 6).toString('ascii') === 'GIF89a';
    if (contentType === 'image/webp')
        return bytes.subarray(0, 4).toString('ascii') === 'RIFF' && bytes.subarray(8, 12).toString('ascii') === 'WEBP';
    if (contentType === 'video/mp4' || contentType === 'video/quicktime')
        return bytes.subarray(4, 8).toString('ascii') === 'ftyp';
    if (contentType === 'video/webm')
        return at(0x1a, 0x45, 0xdf, 0xa3);
    return false;
}
//# sourceMappingURL=media.service.js.map