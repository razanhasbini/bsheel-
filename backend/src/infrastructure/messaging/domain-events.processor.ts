import { Processor, WorkerHost } from '@nestjs/bullmq';
import { Logger } from '@nestjs/common';
import type { Job } from 'bullmq';
import { AuthActionTokenCipher } from '../../modules/auth/infrastructure/auth-action-token-cipher.js';
import { TransactionalEmailService } from '../../modules/auth/infrastructure/transactional-email.service.js';
import { DeviceTokenCipher } from '../../modules/notifications/infrastructure/device-token-cipher.js';
import { FirebasePushService } from '../../modules/notifications/infrastructure/firebase-push.service.js';
import { ObjectStorageService } from '../../modules/media/infrastructure/object-storage.service.js';
import { DomainEventsRepository } from './domain-events.repository.js';
import { RealtimeEventPublisher } from '../realtime/realtime-event.publisher.js';
import { TelegramEventService } from '../../integrations/telegram/telegram-event.service.js';

interface NotificationCreatedPayload {
  readonly notificationId: string;
  readonly userId: string;
}

@Processor('domain-events', { concurrency: 10 })
export class DomainEventsProcessor extends WorkerHost {
  private readonly logger = new Logger(DomainEventsProcessor.name);
  private readonly consumer = 'domain-side-effects-v1';

  constructor(
    private readonly repository: DomainEventsRepository,
    private readonly deviceCipher: DeviceTokenCipher,
    private readonly push: FirebasePushService,
    private readonly storage: ObjectStorageService,
    private readonly actionTokenCipher: AuthActionTokenCipher,
    private readonly email: TransactionalEmailService,
    private readonly realtime: RealtimeEventPublisher,
    private readonly telegram: TelegramEventService,
  ) {
    super();
  }

  async process(
    job: Job<Record<string, unknown>, unknown, string>,
  ): Promise<void> {
    const messageId = String(job.id);
    if (await this.repository.wasProcessed(this.consumer, messageId)) return;

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
    } else if (job.name === 'privacy.export.requested') {
      await this.createPrivacyExport(this.exportPayload(job.data));
    } else if (job.name === 'account.deletion.requested') {
      await this.deleteAccount(this.deletionPayload(job.data));
    } else if (job.name === 'auth.password_recovery.requested') {
      await this.deliverPasswordRecovery(this.actionTokenPayload(job.data));
    } else if (job.name === 'auth.email_confirmation.requested') {
      await this.deliverEmailConfirmation(this.actionTokenPayload(job.data));
    } else {
      this.logger.debug(
        { eventType: job.name, messageId },
        'Domain event has no external side effect',
      );
    }
    await this.repository.markProcessed(this.consumer, messageId);
  }

  private async deliverPasswordRecovery(payload: {
    tokenId: string;
  }): Promise<void> {
    const delivery = await this.repository.passwordRecoveryDelivery(
      payload.tokenId,
    );
    if (!delivery) return;
    const token = this.actionTokenCipher.unprotect(delivery.encryptedToken);
    await this.email.sendPasswordRecovery(delivery.email, token);
  }

  private async deliverEmailConfirmation(payload: {
    tokenId: string;
  }): Promise<void> {
    const delivery = await this.repository.emailConfirmationDelivery(
      payload.tokenId,
    );
    if (!delivery) return;
    const token = this.actionTokenCipher.unprotect(delivery.encryptedToken);
    await this.email.sendEmailConfirmation(delivery.email, token);
  }

  private async createPrivacyExport(payload: {
    exportId: string;
    userId: string;
  }): Promise<void> {
    const document = await this.repository.privacyExport(
      payload.exportId,
      payload.userId,
    );
    if (!document) return;
    const objectKey = `privacy-exports/${payload.userId}/${payload.exportId}.json`;
    await this.storage.putPrivateJson(objectKey, document);
    await this.repository.completePrivacyExport(
      payload.exportId,
      payload.userId,
      objectKey,
    );
  }

  private async deleteAccount(payload: {
    requestId: string;
    userId: string;
  }): Promise<void> {
    const keys = await this.repository.accountMediaKeys(
      payload.requestId,
      payload.userId,
    );
    if (!keys) return;
    for (const key of keys) await this.storage.delete(key);
    await this.repository.deleteAccount(payload.requestId, payload.userId);
  }

  private async deliverNotification(
    payload: NotificationCreatedPayload,
  ): Promise<void> {
    await this.repository.prepareNotification(
      payload.notificationId,
      payload.userId,
    );
    const deliveries = await this.repository.pendingNotificationDeliveries(
      payload.notificationId,
    );
    for (const delivery of deliveries) {
      let token: string;
      try {
        token = this.deviceCipher.unprotect(delivery.encryptedToken);
      } catch (error) {
        await this.repository.markDeliveryFailed(
          delivery.notificationId,
          delivery.deviceTokenId,
          error instanceof Error
            ? error.message
            : 'Device token decryption failed',
          true,
        );
        continue;
      }

      try {
        const result = await this.push.send(
          token,
          delivery.title,
          delivery.body,
        );
        if (result.invalidToken) {
          await this.repository.markDeliveryFailed(
            delivery.notificationId,
            delivery.deviceTokenId,
            'FCM rejected the registration token',
            true,
          );
        } else {
          await this.repository.markDeliverySucceeded(
            delivery.notificationId,
            delivery.deviceTokenId,
            result.messageName,
          );
        }
      } catch (error) {
        await this.repository.markDeliveryFailed(
          delivery.notificationId,
          delivery.deviceTokenId,
          error instanceof Error ? error.message : 'Push delivery failed',
          false,
        );
        throw error;
      }
    }
  }

  private notificationPayload(
    data: Record<string, unknown>,
  ): NotificationCreatedPayload {
    if (
      typeof data.notificationId !== 'string' ||
      typeof data.userId !== 'string'
    ) {
      throw new Error('notification.created payload is malformed');
    }
    return { notificationId: data.notificationId, userId: data.userId };
  }

  private exportPayload(data: Record<string, unknown>): {
    exportId: string;
    userId: string;
  } {
    if (typeof data.exportId !== 'string' || typeof data.userId !== 'string') {
      throw new Error('privacy.export.requested payload is malformed');
    }
    return { exportId: data.exportId, userId: data.userId };
  }

  private deletionPayload(data: Record<string, unknown>): {
    requestId: string;
    userId: string;
  } {
    if (typeof data.requestId !== 'string' || typeof data.userId !== 'string') {
      throw new Error('account.deletion.requested payload is malformed');
    }
    return { requestId: data.requestId, userId: data.userId };
  }

  private actionTokenPayload(data: Record<string, unknown>): {
    tokenId: string;
  } {
    if (typeof data.tokenId !== 'string') {
      throw new Error('Auth action token event payload is malformed');
    }
    return { tokenId: data.tokenId };
  }

  private isRealtimeEvent(type: string): boolean {
    return (
      type.startsWith('notification.') ||
      type === 'profile.updated' ||
      type.startsWith('quest.') ||
      type.startsWith('report.') ||
      type.startsWith('submission.') ||
      type.startsWith('social.') ||
      type.startsWith('admin.')
    );
  }
}
