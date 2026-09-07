import type { ChronologicalCursor } from '../../../common/pagination/cursor.js';
import { DatabaseService } from '../../../infrastructure/database/database.service.js';
export interface NotificationRow extends Record<string, unknown> {
    readonly id: string;
    readonly created_at: Date | string;
}
export declare class NotificationsRepository {
    private readonly database;
    constructor(database: DatabaseService);
    list(userId: string, limit: number, cursor?: ChronologicalCursor): Promise<readonly NotificationRow[]>;
    unreadCount(userId: string): Promise<number>;
    markRead(userId: string, notificationId: string): Promise<void>;
    markAllRead(userId: string): Promise<number>;
    upsertDeviceToken(userId: string, tokenHash: Buffer, encryptedToken: Buffer, platform: string): Promise<string>;
    deleteDeviceToken(userId: string, tokenHash: Buffer): Promise<void>;
    private emitReadEvent;
}
