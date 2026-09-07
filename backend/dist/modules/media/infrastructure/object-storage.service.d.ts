import { OnModuleDestroy } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import type { Environment } from '../../../config/environment.js';
export declare class ObjectStorageService implements OnModuleDestroy {
    private readonly config;
    private readonly client?;
    private readonly bucket?;
    private readonly signedUrlTtl;
    constructor(config: ConfigService<Environment, true>);
    onModuleDestroy(): void;
    presignUpload(key: string, contentType: string, sizeBytes: number, userId: string): Promise<string>;
    presignDownload(key: string): Promise<string>;
    inspect(key: string): Promise<{
        size: number;
        contentType: string;
        etag?: string;
        header: Buffer;
    }>;
    delete(key: string): Promise<void>;
    putPrivateJson(key: string, document: Record<string, unknown>): Promise<void>;
    expiresAt(): string;
    private requiredClient;
    private requiredBucket;
}
