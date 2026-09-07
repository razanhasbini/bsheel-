import { DatabaseService } from '../../../infrastructure/database/database.service.js';
export interface MediaObjectRecord {
    readonly id: string;
    readonly user_id: string;
    readonly client_request_id: string;
    readonly object_key: string;
    readonly kind: 'avatar' | 'submission';
    readonly status: 'pending' | 'ready' | 'rejected' | 'deleted';
    readonly content_type: string;
    readonly declared_size_bytes: string;
    readonly stored_size_bytes: string | null;
    readonly etag: string | null;
    readonly created_at: Date;
    readonly completed_at: Date | null;
}
export declare class MediaRepository {
    private readonly database;
    constructor(database: DatabaseService);
    createOrFind(userId: string, clientRequestId: string, objectKey: string, kind: 'avatar' | 'submission', contentType: string, sizeBytes: number): Promise<MediaObjectRecord>;
    findOwnedForUpdate(userId: string, id: string): Promise<MediaObjectRecord>;
    findOwnedByKey(userId: string, key: string): Promise<MediaObjectRecord>;
    markReady(id: string, storedSize: number, etag?: string): Promise<MediaObjectRecord>;
    markRejected(id: string): Promise<void>;
    markDeleted(userId: string, id: string): Promise<void>;
}
