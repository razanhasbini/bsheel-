import type { Job } from 'bullmq';
import { describe, expect, it, vi } from 'vitest';
import { DomainEventsProcessor } from '../src/infrastructure/messaging/domain-events.processor.js';
import type { DomainEventsRepository } from '../src/infrastructure/messaging/domain-events.repository.js';
import type { ObjectStorageService } from '../src/modules/media/infrastructure/object-storage.service.js';
import type { DeviceTokenCipher } from '../src/modules/notifications/infrastructure/device-token-cipher.js';
import type { FirebasePushService } from '../src/modules/notifications/infrastructure/firebase-push.service.js';
import type { AuthActionTokenCipher } from '../src/modules/auth/infrastructure/auth-action-token-cipher.js';
import type { TransactionalEmailService } from '../src/modules/auth/infrastructure/transactional-email.service.js';
import type { RealtimeEventPublisher } from '../src/infrastructure/realtime/realtime-event.publisher.js';
import type { TelegramEventService } from '../src/integrations/telegram/telegram-event.service.js';
import type { ProofVerificationService } from '../src/modules/submissions/application/proof-verification.service.js';

function notificationJob(data: Record<string, unknown>) {
  return {
    id: '21fbf86d-b765-48f5-8273-628cc8270adf',
    name: 'notification.created',
    data,
  } as Job<Record<string, unknown>, unknown, string>;
}

function setup(pushResult: { invalidToken: boolean; messageName?: string }) {
  const repository = {
    wasProcessed: vi.fn().mockResolvedValue(false),
    prepareNotification: vi.fn().mockResolvedValue(undefined),
    pendingNotificationDeliveries: vi.fn().mockResolvedValue([
      {
        notificationId: 'notification-id',
        deviceTokenId: 'device-id',
        encryptedToken: Buffer.from('encrypted'),
        title: 'Quest approved',
        body: 'Your proof was approved.',
      },
    ]),
    markDeliverySucceeded: vi.fn().mockResolvedValue(undefined),
    markDeliveryFailed: vi.fn().mockResolvedValue(undefined),
    markProcessed: vi.fn().mockResolvedValue(undefined),
  };
  const cipher = { unprotect: vi.fn().mockReturnValue('fcm-token') };
  const push = { send: vi.fn().mockResolvedValue(pushResult) };
  const realtime = { publish: vi.fn().mockResolvedValue(undefined) };
  const processor = new DomainEventsProcessor(
    repository as unknown as DomainEventsRepository,
    cipher as unknown as DeviceTokenCipher,
    push as unknown as FirebasePushService,
    {} as ObjectStorageService,
    {} as AuthActionTokenCipher,
    {} as TransactionalEmailService,
    realtime as unknown as RealtimeEventPublisher,
    {
      handle: vi.fn().mockResolvedValue(undefined),
    } as unknown as TelegramEventService,
    // AI proof verification (#47) runs off submission.created; stubbed
    // because these cases exercise the other side effects.
    { verify: vi.fn().mockResolvedValue(undefined) } as unknown as ProofVerificationService,
  );
  return { processor, repository, cipher, push, realtime };
}

describe('DomainEventsProcessor notification delivery', () => {
  it('delivers each pending token and records message idempotency', async () => {
    const { processor, repository, push } = setup({
      invalidToken: false,
      messageName: 'projects/bitsheel/messages/1',
    });

    await processor.process(
      notificationJob({
        notificationId: 'notification-id',
        userId: 'user-id',
      }),
    );

    expect(push.send).toHaveBeenCalledWith(
      'fcm-token',
      'Quest approved',
      'Your proof was approved.',
    );
    expect(repository.markDeliverySucceeded).toHaveBeenCalledWith(
      'notification-id',
      'device-id',
      'projects/bitsheel/messages/1',
    );
    expect(repository.markProcessed).toHaveBeenCalledWith(
      'domain-side-effects-v1',
      '21fbf86d-b765-48f5-8273-628cc8270adf',
    );
  });

  it('removes a token FCM reports as invalid without failing the whole event', async () => {
    const { processor, repository } = setup({ invalidToken: true });

    await processor.process(
      notificationJob({
        notificationId: 'notification-id',
        userId: 'user-id',
      }),
    );

    expect(repository.markDeliveryFailed).toHaveBeenCalledWith(
      'notification-id',
      'device-id',
      'FCM rejected the registration token',
      true,
    );
    expect(repository.markProcessed).toHaveBeenCalledOnce();
  });

  it('rejects malformed event payloads before marking them processed', async () => {
    const { processor, repository } = setup({ invalidToken: false });

    await expect(
      processor.process(notificationJob({ userId: 'user-id' })),
    ).rejects.toThrow(/malformed/);
    expect(repository.markProcessed).not.toHaveBeenCalled();
  });
});

describe('DomainEventsProcessor quest realtime delivery', () => {
  it('publishes assignment changes before acknowledging the outbox event', async () => {
    const { processor, repository, realtime } = setup({ invalidToken: false });
    const data = {
      userId: 'user-id',
      userQuestId: 'assignment-id',
      questId: 'quest-id',
    };

    await processor.process({
      id: '0e7957f7-b932-4a16-8ea1-8c43438033c3',
      name: 'quest.assigned',
      data,
    } as Job<Record<string, unknown>, unknown, string>);

    expect(realtime.publish).toHaveBeenCalledWith({
      messageId: '0e7957f7-b932-4a16-8ea1-8c43438033c3',
      type: 'quest.assigned',
      data,
    });
    expect(repository.markProcessed).toHaveBeenCalledWith(
      'domain-side-effects-v1',
      '0e7957f7-b932-4a16-8ea1-8c43438033c3',
    );
  });

  it('publishes report changes for admin-room invalidation', async () => {
    const { processor, repository, realtime } = setup({ invalidToken: false });
    const data = { reportId: 'report-id', status: 'resolved' };

    await processor.process({
      id: '5d72452c-41fc-4564-a679-d867fbd58b7f',
      name: 'report.reviewed',
      data,
    } as Job<Record<string, unknown>, unknown, string>);

    expect(realtime.publish).toHaveBeenCalledWith({
      messageId: '5d72452c-41fc-4564-a679-d867fbd58b7f',
      type: 'report.reviewed',
      data,
    });
    expect(repository.markProcessed).toHaveBeenCalledOnce();
  });
});

describe('DomainEventsProcessor password recovery delivery', () => {
  it('decrypts and delivers a current recovery action before acknowledging it', async () => {
    const repository = {
      wasProcessed: vi.fn().mockResolvedValue(false),
      passwordRecoveryDelivery: vi.fn().mockResolvedValue({
        email: 'recover@example.test',
        encryptedToken: Buffer.from('encrypted-action-token'),
      }),
      markProcessed: vi.fn().mockResolvedValue(undefined),
    };
    const actionTokenCipher = {
      unprotect: vi.fn().mockReturnValue('raw-action-token'),
    };
    const email = {
      sendPasswordRecovery: vi.fn().mockResolvedValue(undefined),
    };
    const processor = new DomainEventsProcessor(
      repository as unknown as DomainEventsRepository,
      {} as DeviceTokenCipher,
      {} as FirebasePushService,
      {} as ObjectStorageService,
      actionTokenCipher as unknown as AuthActionTokenCipher,
      email as unknown as TransactionalEmailService,
      {
        publish: vi.fn().mockResolvedValue(undefined),
      } as unknown as RealtimeEventPublisher,
      {
        handle: vi.fn().mockResolvedValue(undefined),
      } as unknown as TelegramEventService,
      // AI proof verification (#47) runs off submission.created; stubbed
      // because these cases exercise the other side effects.
      { verify: vi.fn().mockResolvedValue(undefined) } as unknown as ProofVerificationService,
    );

    await processor.process({
      id: '4654825c-0863-4935-8eaf-77fe439002a8',
      name: 'auth.password_recovery.requested',
      data: { tokenId: 'action-token-id' },
    } as Job<Record<string, unknown>, unknown, string>);

    expect(actionTokenCipher.unprotect).toHaveBeenCalledWith(
      Buffer.from('encrypted-action-token'),
    );
    expect(email.sendPasswordRecovery).toHaveBeenCalledWith(
      'recover@example.test',
      'raw-action-token',
    );
    expect(repository.markProcessed).toHaveBeenCalledOnce();
  });

  it('does not acknowledge a recovery event when delivery fails', async () => {
    const repository = {
      wasProcessed: vi.fn().mockResolvedValue(false),
      passwordRecoveryDelivery: vi.fn().mockResolvedValue({
        email: 'recover@example.test',
        encryptedToken: Buffer.from('encrypted-action-token'),
      }),
      markProcessed: vi.fn().mockResolvedValue(undefined),
    };
    const processor = new DomainEventsProcessor(
      repository as unknown as DomainEventsRepository,
      {} as DeviceTokenCipher,
      {} as FirebasePushService,
      {} as ObjectStorageService,
      {
        unprotect: vi.fn().mockReturnValue('raw-action-token'),
      } as unknown as AuthActionTokenCipher,
      {
        sendPasswordRecovery: vi
          .fn()
          .mockRejectedValue(new Error('provider unavailable')),
      } as unknown as TransactionalEmailService,
      {
        publish: vi.fn().mockResolvedValue(undefined),
      } as unknown as RealtimeEventPublisher,
      {
        handle: vi.fn().mockResolvedValue(undefined),
      } as unknown as TelegramEventService,
      // AI proof verification (#47) runs off submission.created; stubbed
      // because these cases exercise the other side effects.
      { verify: vi.fn().mockResolvedValue(undefined) } as unknown as ProofVerificationService,
    );

    await expect(
      processor.process({
        id: 'fe3f5516-1f2f-47ca-845f-bab7aa564116',
        name: 'auth.password_recovery.requested',
        data: { tokenId: 'action-token-id' },
      } as Job<Record<string, unknown>, unknown, string>),
    ).rejects.toThrow('provider unavailable');
    expect(repository.markProcessed).not.toHaveBeenCalled();
  });
});

describe('DomainEventsProcessor email confirmation delivery', () => {
  it('decrypts and delivers a current confirmation action', async () => {
    const repository = {
      wasProcessed: vi.fn().mockResolvedValue(false),
      emailConfirmationDelivery: vi.fn().mockResolvedValue({
        email: 'confirm@example.test',
        encryptedToken: Buffer.from('encrypted-confirmation-token'),
      }),
      markProcessed: vi.fn().mockResolvedValue(undefined),
    };
    const email = {
      sendEmailConfirmation: vi.fn().mockResolvedValue(undefined),
    };
    const processor = new DomainEventsProcessor(
      repository as unknown as DomainEventsRepository,
      {} as DeviceTokenCipher,
      {} as FirebasePushService,
      {} as ObjectStorageService,
      {
        unprotect: vi.fn().mockReturnValue('raw-confirmation-token'),
      } as unknown as AuthActionTokenCipher,
      email as unknown as TransactionalEmailService,
      {
        publish: vi.fn().mockResolvedValue(undefined),
      } as unknown as RealtimeEventPublisher,
      {
        handle: vi.fn().mockResolvedValue(undefined),
      } as unknown as TelegramEventService,
      // AI proof verification (#47) runs off submission.created; stubbed
      // because these cases exercise the other side effects.
      { verify: vi.fn().mockResolvedValue(undefined) } as unknown as ProofVerificationService,
    );

    await processor.process({
      id: '8b911873-a208-4ddc-b16d-8de80fc55079',
      name: 'auth.email_confirmation.requested',
      data: { tokenId: 'action-token-id' },
    } as Job<Record<string, unknown>, unknown, string>);

    expect(email.sendEmailConfirmation).toHaveBeenCalledWith(
      'confirm@example.test',
      'raw-confirmation-token',
    );
    expect(repository.markProcessed).toHaveBeenCalledOnce();
  });
});
