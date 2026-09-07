import { MediaRepository } from '../infrastructure/media.repository.js';
import { ObjectStorageService } from '../infrastructure/object-storage.service.js';
export declare class MediaService {
    private readonly repository;
    private readonly storage;
    constructor(repository: MediaRepository, storage: ObjectStorageService);
    createIntent(userId: string, requestId: string, kind: 'avatar' | 'submission', contentType: string, sizeBytes: number): Promise<{
        objectId: string;
        key: string;
        uploadUrl: string;
        headers: {
            'content-type': string;
            'content-length': string;
        };
        expiresAt: string;
        status: "ready" | "pending";
    }>;
    complete(userId: string, objectId: string): Promise<{
        id: string;
        key: string;
        status: "ready" | "deleted" | "pending" | "rejected";
    }>;
    sign(rawUrls: readonly string[]): Promise<{
        urls: {
            [k: string]: string;
        };
    }>;
    delete(userId: string, objectId: string): Promise<void>;
    deleteByKey(userId: string, key: string): Promise<void>;
    private extractKey;
}
export declare function matchesMagic(bytes: Buffer, contentType: string): boolean;
