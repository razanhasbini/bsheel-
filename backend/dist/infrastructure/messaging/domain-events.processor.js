var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
var __metadata = (this && this.__metadata) || function (k, v) {
    if (typeof Reflect === "object" && typeof Reflect.metadata === "function") return Reflect.metadata(k, v);
};
var DomainEventsProcessor_1;
import { Processor, WorkerHost } from '@nestjs/bullmq';
import { Logger } from '@nestjs/common';
import { AuthActionTokenCipher } from '../../modules/auth/infrastructure/auth-action-token-cipher.js';
import { TransactionalEmailService } from '../../modules/auth/infrastructure/transactional-email.service.js';
import { DeviceTokenCipher } from '../../modules/notifications/infrastructure/device-token-cipher.js';
import { FirebasePushService } from '../../modules/notifications/infrastructure/firebase-push.service.js';
import { ObjectStorageService } from '../../modules/media/infrastructure/object-storage.service.js';
import { DomainEventsRepository } from './domain-events.repository.js';
import { RealtimeEventPublisher } from '../realtime/realtime-event.publisher.js';
import { TelegramEventService } from '../../integrations/telegram/telegram-event.service.js';
let DomainEventsProcessor = DomainEventsProcessor_1 = class DomainEventsProcessor extends WorkerHost {
    repository;
    deviceCipher;
    push;
    storage;
    actionTokenCipher;
    email;
    realtime;
    telegram;
    logger = new Logger(DomainEventsProcessor_1.name);
    consumer = 'domain-side-effects-v1';
    constructor(repository, deviceCipher, push, storage, actionTokenCipher, email, realtime, telegram) {
        super();
        this.repository = repository;
        this.deviceCipher = deviceCipher;
        this.push = push;
        this.storage = storage;
        this.actionTokenCipher = actionTokenCipher;
        this.email = email;
        this.realtime = realtime;
        this.telegram = telegram;
    }
    async process(job) {
        const messageId = String(job.id);
        if (await this.repository.wasProcessed(this.consumer, messageId))
            return;
        if (this.isRealtimeEvent(job.name)) {
            await this.realtime.publish({
                messageId,
                type: job.name,
                data: job.data,
            });
        }
        await this.telegram.handle(job.name, job.data);
        if (job.name === 'notification.created') {
            await this.deliverNotification(this.notificationPayload(job.data));
        }
        else if (job.name === 'privacy.export.requested') {
            await this.createPrivacyExport(this.exportPayload(job.data));
        }
        else if (job.name === 'account.deletion.requested') {
            await this.deleteAccount(this.deletionPayload(job.data));
        }
        else if (job.name === 'auth.password_recovery.requested') {
            await this.deliverPasswordRecovery(this.actionTokenPayload(job.data));
        }
        else if (job.name === 'auth.email_confirmation.requested') {
            await this.deliverEmailConfirmation(this.actionTokenPayload(job.data));
        }
        else {
            this.logger.debug({ eventType: job.name, messageId }, 'Domain event has no external side effect');
        }
        await this.repository.markProcessed(this.consumer, messageId);
    }
    async deliverPasswordRecovery(payload) {
        const delivery = await this.repository.passwordRecoveryDelivery(payload.tokenId);
        if (!delivery)
            return;
        const token = this.actionTokenCipher.unprotect(delivery.encryptedToken);
        await this.email.sendPasswordRecovery(delivery.email, token);
    }
    async deliverEmailConfirmation(payload) {
        const delivery = await this.repository.emailConfirmationDelivery(payload.tokenId);
        if (!delivery)
            return;
        const token = this.actionTokenCipher.unprotect(delivery.encryptedToken);
        await this.email.sendEmailConfirmation(delivery.email, token);
    }
    async createPrivacyExport(payload) {
        const document = await this.repository.privacyExport(payload.exportId, payload.userId);
        if (!document)
            return;
        const objectKey = `privacy-exports/${payload.userId}/${payload.exportId}.json`;
        await this.storage.putPrivateJson(objectKey, document);
        await this.repository.completePrivacyExport(payload.exportId, payload.userId, objectKey);
    }
    async deleteAccount(payload) {
        const keys = await this.repository.accountMediaKeys(payload.requestId, payload.userId);
        if (!keys)
            return;
        for (const key of keys)
            await this.storage.delete(key);
        await this.repository.deleteAccount(payload.requestId, payload.userId);
    }
    async deliverNotification(payload) {
        await this.repository.prepareNotification(payload.notificationId, payload.userId);
        const deliveries = await this.repository.pendingNotificationDeliveries(payload.notificationId);
        for (const delivery of deliveries) {
            let token;
            try {
                token = this.deviceCipher.unprotect(delivery.encryptedToken);
            }
            catch (error) {
                await this.repository.markDeliveryFailed(delivery.notificationId, delivery.deviceTokenId, error instanceof Error
                    ? error.message
                    : 'Device token decryption failed', true);
                continue;
            }
            try {
                const result = await this.push.send(token, delivery.title, delivery.body);
                if (result.invalidToken) {
                    await this.repository.markDeliveryFailed(delivery.notificationId, delivery.deviceTokenId, 'FCM rejected the registration token', true);
                }
                else {
                    await this.repository.markDeliverySucceeded(delivery.notificationId, delivery.deviceTokenId, result.messageName);
                }
            }
            catch (error) {
                await this.repository.markDeliveryFailed(delivery.notificationId, delivery.deviceTokenId, error instanceof Error ? error.message : 'Push delivery failed', false);
                throw error;
            }
        }
    }
    notificationPayload(data) {
        if (typeof data.notificationId !== 'string' ||
            typeof data.userId !== 'string') {
            throw new Error('notification.created payload is malformed');
        }
        return { notificationId: data.notificationId, userId: data.userId };
    }
    exportPayload(data) {
        if (typeof data.exportId !== 'string' || typeof data.userId !== 'string') {
            throw new Error('privacy.export.requested payload is malformed');
        }
        return { exportId: data.exportId, userId: data.userId };
    }
    deletionPayload(data) {
        if (typeof data.requestId !== 'string' || typeof data.userId !== 'string') {
            throw new Error('account.deletion.requested payload is malformed');
        }
        return { requestId: data.requestId, userId: data.userId };
    }
    actionTokenPayload(data) {
        if (typeof data.tokenId !== 'string') {
            throw new Error('Auth action token event payload is malformed');
        }
        return { tokenId: data.tokenId };
    }
    isRealtimeEvent(type) {
        return (type.startsWith('notification.') ||
            type === 'profile.updated' ||
            type.startsWith('quest.') ||
            type.startsWith('report.') ||
            type.startsWith('submission.') ||
            type.startsWith('social.') ||
            type.startsWith('admin.'));
    }
};
DomainEventsProcessor = DomainEventsProcessor_1 = __decorate([
    Processor('domain-events', { concurrency: 10 }),
    __metadata("design:paramtypes", [DomainEventsRepository,
        DeviceTokenCipher,
        FirebasePushService,
        ObjectStorageService,
        AuthActionTokenCipher,
        TransactionalEmailService,
        RealtimeEventPublisher,
        TelegramEventService])
], DomainEventsProcessor);
export { DomainEventsProcessor };
//# sourceMappingURL=domain-events.processor.js.map