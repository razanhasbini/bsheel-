import type { AuthUser } from '../../../common/auth/auth-user.js';
import { NotificationsService } from '../application/notifications.service.js';
import { DeleteDeviceTokenDto, NotificationListQueryDto, RegisterDeviceTokenDto } from './notifications.dto.js';
declare class NotificationIdParam {
    id: string;
}
export declare class NotificationsController {
    private readonly service;
    constructor(service: NotificationsService);
    list(user: AuthUser, query: NotificationListQueryDto): Promise<{
        items: readonly import("../infrastructure/notifications.repository.js").NotificationRow[];
        nextCursor: string | null;
    }>;
    unreadCount(user: AuthUser): Promise<{
        count: number;
    }>;
    markRead(user: AuthUser, param: NotificationIdParam): Promise<void>;
    markAllRead(user: AuthUser): Promise<{
        updated: number;
    }>;
    registerDevice(user: AuthUser, body: RegisterDeviceTokenDto): Promise<{
        id: string;
    }>;
    deleteDevice(user: AuthUser, body: DeleteDeviceTokenDto): Promise<void>;
}
export {};
