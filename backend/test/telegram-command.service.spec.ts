import { describe, expect, it, vi } from 'vitest';
import { TelegramCommandService } from '../src/integrations/telegram/telegram-command.service.js';
import type { TelegramRepository } from '../src/integrations/telegram/telegram.repository.js';
import type { TelegramClient } from '../src/integrations/telegram/telegram.client.js';

function setup() {
  const repository = {
    commandState: vi.fn(),
    setCommandState: vi.fn().mockResolvedValue(undefined),
    clearCommandState: vi.fn().mockResolvedValue(undefined),
    createQuest: vi.fn().mockResolvedValue('quest-id'),
    broadcast: vi.fn().mockResolvedValue(17),
  };
  const client = { sendMessage: vi.fn().mockResolvedValue(null) };
  const service = new TelegramCommandService(
    repository as unknown as TelegramRepository,
    client as unknown as TelegramClient,
  );
  return { service, repository, client };
}

describe('TelegramCommandService', () => {
  it('parses and safely escapes broadcast copy', async () => {
    const { service, repository, client } = setup();
    await service.handle('42', '/broadcast <Release> | A & B');
    expect(repository.broadcast).toHaveBeenCalledWith('<Release>', 'A & B', '42');
    expect(client.sendMessage).toHaveBeenCalledWith(
      '42', expect.stringContaining('&lt;Release&gt;'),
    );
    expect(client.sendMessage).toHaveBeenLastCalledWith('42', 'Queued for <b>17</b> users.');
  });

  it('preserves the legacy quest-add validation and creates after YES', async () => {
    const { service, repository } = setup();
    await service.handle('42', '/quest add');
    expect(repository.setCommandState).toHaveBeenCalledWith('42', 'quest_add', 'awaiting_title', {});

    repository.commandState.mockResolvedValue({
      chat_id: '42', command: 'quest_add', step: 'awaiting_confirm',
      data: { title: 'Walk', description: 'Walk for ten minutes', category: 'fitness', difficulty: 'easy', xp_reward: 10 },
    });
    await service.handle('42', 'YES');
    expect(repository.createQuest).toHaveBeenCalledWith(expect.objectContaining({ title: 'Walk', xp_reward: 10 }), '42');
    expect(repository.clearCommandState).toHaveBeenCalledWith('42');
  });
});
