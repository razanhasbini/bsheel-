import { DeviceTokenCipher } from '../infrastructure/device-token-cipher.js';
import { NotificationsRepository } from '../infrastructure/notifications.repository.js';
export declare class NotificationsService {
    private readonly repository;
    private readonly cipher;
    constructor(repository: NotificationsRepository, cipher: DeviceTokenCipher);
    list(userId: string, limit: number, rawCursor?: string): Promise<{
        items: readonly import("../infrastructure/notifications.repository.js").NotificationRow[];
        nextCursor: string | null;
    }>;
    unreadCount(userId: string): Promise<{
        count: number;
    }>;
    markRead(userId: string, notificationId: string): Promise<void>;
    markAllRead(userId: string): Promise<{
        updated: number;
    }>;
    registerDevice(userId: string, token: string, platform: string): Promise<{
        id: string;
    }>;
    deleteDevice(userId: string, token: string): Promise<void>;
}
