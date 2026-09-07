import { describe, expect, it, vi } from 'vitest';
import { TelegramWebhookService } from '../src/integrations/telegram/telegram-webhook.service.js';
import type { TelegramRepository } from '../src/integrations/telegram/telegram.repository.js';
import type { TelegramClient } from '../src/integrations/telegram/telegram.client.js';
import type { TelegramCommandService } from '../src/integrations/telegram/telegram-command.service.js';
import type { SubmissionsService } from '../src/modules/submissions/application/submissions.service.js';
import type { ConfigService } from '@nestjs/config';
import type { Environment } from '../src/config/environment.js';

function setup(allowed = '42') {
  const values: Record<string, unknown> = {
    TELEGRAM_ENABLED: true,
    TELEGRAM_WEBHOOK_SECRET: 'correct-secret',
    TELEGRAM_ALLOWED_CHAT_IDS: allowed,
  };
  const config = { get: vi.fn((key: string) => values[key]) };
  const repository = {
    claimUpdate: vi.fn().mockResolvedValue(true),
    finishUpdate: vi.fn().mockResolvedValue(undefined),
    reviewReport: vi.fn().mockResolvedValue({ ok: true, message: 'Dismissed' }),
  };
  const submissions = {
    approve: vi.fn().mockResolvedValue(undefined),
    reject: vi.fn().mockResolvedValue(undefined),
  };
  const commands = { handle: vi.fn().mockResolvedValue(undefined) };
  const client = {
    answerCallback: vi.fn().mockResolvedValue(undefined),
    editMessage: vi.fn().mockResolvedValue(undefined),
    sendMessage: vi.fn().mockResolvedValue(null),
  };
  const service = new TelegramWebhookService(
    config as unknown as ConfigService<Environment, true>,
    repository as unknown as TelegramRepository,
    submissions as unknown as SubmissionsService,
    commands as unknown as TelegramCommandService,
    client as unknown as TelegramClient,
  );
  return { service, repository, submissions, commands, client };
}

describe('TelegramWebhookService', () => {
  it('compares the configured webhook secret and rejects lookalikes', () => {
    const { service } = setup();
    expect(service.configured()).toBe(true);
    expect(service.validSecret('correct-secret')).toBe(true);
    expect(service.validSecret('correct-secreu')).toBe(false);
    expect(service.validSecret(undefined)).toBe(false);
  });

  it('reviews a submission once with a system actor and Telegram audit context', async () => {
    const { service, repository, submissions, client } = setup();
    await service.process({
      update_id: 91,
      callback_query: {
        id: 'callback-1', data: 'approve:018d7df0-e97b-7ae1-bae2-4423f4b05b85',
        message: { message_id: 33, text: 'Original <text>', chat: { id: 42 } },
      },
    });
    expect(repository.claimUpdate).toHaveBeenCalledWith('91');
    expect(submissions.approve).toHaveBeenCalledWith(
      null,
      '018d7df0-e97b-7ae1-bae2-4423f4b05b85',
      undefined,
      { source: 'telegram', telegram_chat_id: '42', telegram_msg_id: 33 },
    );
    expect(client.answerCallback).toHaveBeenCalledWith('callback-1', 'Approved');
    expect(client.editMessage).toHaveBeenCalledWith(
      '42', 33, expect.stringContaining('Original &lt;text&gt;'), true,
    );
    expect(repository.finishUpdate).toHaveBeenCalledWith('91');
  });

  it('does not run duplicate updates and denies unlisted chats', async () => {
    const { service, repository, submissions, client } = setup();
    repository.claimUpdate.mockResolvedValueOnce(false).mockResolvedValueOnce(true);
    await service.process({ update_id: 92, message: { text: '/help', chat: { id: 42 } } });
    expect(submissions.approve).not.toHaveBeenCalled();
    await service.process({
      update_id: 93,
      callback_query: { id: 'callback-2', data: 'approve:id', message: { chat: { id: 404 } } },
    });
    expect(client.answerCallback).toHaveBeenCalledWith('callback-2', 'Not authorized');
  });
});
