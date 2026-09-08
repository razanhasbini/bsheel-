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
export interface ReclaimCandidate {
    readonly id: string;
    readonly object_key: string;
    readonly reason: 'abandoned_intent' | 'rejected_upload' | 'superseded_avatar';
}
export declare class MediaRepository {
    private readonly database;
    constructor(database: DatabaseService);
    createOrFind(userId: string, clientRequestId: string, objectKey: string, kind: 'avatar' | 'submission', contentType: string, sizeBytes: number): Promise<MediaObjectRecord>;
    quotaSnapshot(userId: string, kind: 'avatar' | 'submission', clientRequestId: string): Promise<{
        liveCount: number;
        isRetry: boolean;
    }>;
    claimReclaimable(graceHours: number, limit: number): Promise<readonly ReclaimCandidate[]>;
    markReclaimed(ids: readonly string[]): Promise<number>;
    findOwnedForUpdate(userId: string, id: string): Promise<MediaObjectRecord>;
    findOwnedByKey(userId: string, key: string): Promise<MediaObjectRecord>;
    markReady(id: string, storedSize: number, etag?: string): Promise<MediaObjectRecord>;
    markRejected(id: string): Promise<void>;
    markDeleted(userId: string, id: string): Promise<void>;
}
