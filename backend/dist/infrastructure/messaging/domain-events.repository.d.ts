import { DatabaseService } from '../database/database.service.js';
export interface NotificationDelivery {
    readonly notificationId: string;
    readonly deviceTokenId: string;
    readonly encryptedToken: Buffer;
    readonly title: string;
    readonly body: string;
}
export interface PasswordRecoveryDelivery {
    readonly email: string;
    readonly encryptedToken: Buffer;
}
export declare class DomainEventsRepository {
    private readonly database;
    constructor(database: DatabaseService);
    wasProcessed(consumer: string, messageId: string): Promise<boolean>;
    prepareNotification(notificationId: string, userId: string): Promise<void>;
    pendingNotificationDeliveries(notificationId: string): Promise<readonly NotificationDelivery[]>;
    markDeliverySucceeded(notificationId: string, deviceTokenId: string, messageName?: string): Promise<void>;
    markDeliveryFailed(notificationId: string, deviceTokenId: string, error: string, invalidToken: boolean): Promise<void>;
    markProcessed(consumer: string, messageId: string): Promise<void>;
    passwordRecoveryDelivery(tokenId: string): Promise<PasswordRecoveryDelivery | null>;
    emailConfirmationDelivery(tokenId: string): Promise<PasswordRecoveryDelivery | null>;
    privacyExport(exportId: string, userId: string): Promise<Record<string, unknown> | null>;
    completePrivacyExport(exportId: string, userId: string, objectKey: string): Promise<void>;
    accountMediaKeys(requestId: string, userId: string): Promise<readonly string[] | null>;
    deleteAccount(requestId: string, userId: string): Promise<void>;
}
