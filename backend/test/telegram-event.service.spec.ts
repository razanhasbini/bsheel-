import { describe, expect, it, vi } from 'vitest';
import { TelegramEventService } from '../src/integrations/telegram/telegram-event.service.js';
import type { TelegramClient } from '../src/integrations/telegram/telegram.client.js';
import type { TelegramRepository } from '../src/integrations/telegram/telegram.repository.js';
import type { ObjectStorageService } from '../src/modules/media/infrastructure/object-storage.service.js';

const submission = {
  id: 'bb403f1b-8264-4e4c-8998-137ff6822af3',
  media_url: '["submissions/67c58b3a-8efb-4bf6-b084-ff92570b80b8/proof.jpg"]',
  media_type: 'image',
  caption: '<proof & progress>',
  status: 'pending',
  review_note: null,
  appeal_note: null,
  appealed: false,
  telegram_message_id: null,
  quest_title: 'Walk & Learn',
  username: 'quest_user',
  display_name: 'Quest User',
};

describe('TelegramEventService', () => {
  it('signs private media, escapes copy, adds review buttons, and persists the message id', async () => {
    const repository = {
      submission: vi.fn().mockResolvedValue(submission),
      setSubmissionMessageId: vi.fn().mockResolvedValue(undefined),
    };
    const client = {
      isEnabled: vi.fn().mockReturnValue(true),
      sendAdminMediaGroup: vi.fn().mockResolvedValue(undefined),
      sendAdminMessage: vi.fn().mockResolvedValue(487),
    };
    const storage = { presignDownload: vi.fn().mockResolvedValue('https://signed.example/proof.jpg') };
    const service = new TelegramEventService(
      repository as unknown as TelegramRepository,
      client as unknown as TelegramClient,
      storage as unknown as ObjectStorageService,
    );

    await service.handle('submission.created', { submissionId: submission.id });

    expect(storage.presignDownload).toHaveBeenCalledOnce();
    expect(client.sendAdminMediaGroup).toHaveBeenCalledWith(
      ['https://signed.example/proof.jpg'],
      'image',
      expect.stringContaining('&lt;proof &amp; progress&gt;'),
    );
    expect(client.sendAdminMessage).toHaveBeenCalledWith(
      expect.stringContaining('review the media above'),
      [[
        { text: '✅ Approve', callback_data: `approve:${submission.id}` },
        { text: '❌ Reject', callback_data: `reject:${submission.id}` },
      ]],
    );
    expect(repository.setSubmissionMessageId).toHaveBeenCalledWith(submission.id, 487);
  });

  it('deletes the moderation message when the submission is deleted', async () => {
    const repository = {
      submission: vi.fn().mockResolvedValue({ ...submission, telegram_message_id: '812' }),
    };
    const client = {
      isEnabled: vi.fn().mockReturnValue(true),
      deleteAdminMessage: vi.fn().mockResolvedValue(undefined),
    };
    const service = new TelegramEventService(
      repository as unknown as TelegramRepository,
      client as unknown as TelegramClient,
      {} as ObjectStorageService,
    );

    await service.handle('submission.deleted', { submissionId: submission.id });
    expect(client.deleteAdminMessage).toHaveBeenCalledWith(812);
  });

  it('performs no database or network work when Telegram is disabled', async () => {
    const repository = { submission: vi.fn() };
    const service = new TelegramEventService(
      repository as unknown as TelegramRepository,
      { isEnabled: vi.fn().mockReturnValue(false) } as unknown as TelegramClient,
      {} as ObjectStorageService,
    );

    await service.handle('submission.created', { submissionId: submission.id });
    expect(repository.submission).not.toHaveBeenCalled();
  });

  it('builds the scheduled daily summary in one aggregate read', async () => {
    const repository = {
      dailySummary: vi.fn().mockResolvedValue({
        submissions: 8, approved: 5, rejected: 1, signups: 3, submitters: 6,
        pending_submissions: 2, pending_appeals: 1, pending_reports: 4,
        top_quests: [{ title: 'Learn <TypeScript>', approvals: 3 }],
      }),
    };
    const client = {
      isEnabled: vi.fn().mockReturnValue(true),
      sendAdminMessage: vi.fn().mockResolvedValue(1),
    };
    const service = new TelegramEventService(
      repository as unknown as TelegramRepository,
      client as unknown as TelegramClient,
      {} as ObjectStorageService,
    );
    await service.handle('telegram.daily_summary', {});
    expect(repository.dailySummary).toHaveBeenCalledOnce();
    expect(client.sendAdminMessage).toHaveBeenCalledWith(expect.stringContaining('Learn &lt;TypeScript&gt;'));
  });
});
