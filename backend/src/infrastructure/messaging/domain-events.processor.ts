import { InjectQueue, Processor, WorkerHost } from '@nestjs/bullmq';
import { Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import type { Job, Queue } from 'bullmq';
import type { Environment } from '../../config/environment.js';
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
    private readonly config: ConfigService<Environment, true>,
    @InjectQueue('submission-verification') private readonly submissionVerificationQueue: Queue,
    @InjectQueue('quest-assignment-agent') private readonly questAssignmentQueue: Queue,
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
    } else if (job.name === 'submission.created') {
      // Only enqueues the dedicated job — CV/CAMARA/OpenAI calls never run
      // inline in this shared processor. submission.appealed is a distinct
      // event type and never reaches this branch, so an appeal can never be
      // auto re-decided by the agent; appeals stay human-only.
      await this.enqueueSubmissionVerification(job.data);
    } else if (job.name === 'quest.assigned') {
      // Same rule: enqueue only. The post-assignment work measures the
      // user's distance over CAMARA and opens a geofence, neither of which
      // belongs in a processor shared with notification delivery.
      await this.enqueueQuestAssignmentAgent(job.data);
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

  private async enqueueSubmissionVerification(data: Record<string, unknown>): Promise<void> {
    if (!this.config.get('AGENT_SUBMISSION_VERIFICATION_ENABLED', { infer: true })) return;
    const payload = this.submissionCreatedPayload(data);
    await this.submissionVerificationQueue.add(
      'submission.verify',
      { submissionId: payload.submissionId },
      {
        // Deterministic id: a retried outbox publish of the same
        // submission.created event can never enqueue a second run.
        jobId: `submission:${payload.submissionId}:verification:v1`,
        attempts: 3,
        backoff: { type: 'exponential', delay: 5_000 },
        removeOnComplete: { age: 86_400, count: 10_000 },
        removeOnFail: { age: 604_800, count: 50_000 },
      },
    );
  }

  private submissionCreatedPayload(data: Record<string, unknown>): { submissionId: string } {
    if (typeof data.submissionId !== 'string') {
      throw new Error('submission.created payload is malformed');
    }
    return { submissionId: data.submissionId };
  }

  private async enqueueQuestAssignmentAgent(data: Record<string, unknown>): Promise<void> {
    if (!this.config.get('AGENT_SUBMISSION_VERIFICATION_ENABLED', { infer: true })) return;
    if (typeof data.userQuestId !== 'string') {
      throw new Error('quest.assigned payload is malformed');
    }
    await this.questAssignmentQueue.add(
      'quest.assignment-agent',
      { userQuestId: data.userQuestId },
      {
        jobId: `user-quest:${data.userQuestId}:assignment-agent:v1`,
        attempts: 3,
        backoff: { type: 'exponential', delay: 5_000 },
        removeOnComplete: { age: 86_400, count: 10_000 },
        removeOnFail: { age: 604_800, count: 50_000 },
      },
    );
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
