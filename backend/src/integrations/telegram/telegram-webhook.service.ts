import { HttpException, Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { createHash, timingSafeEqual } from 'node:crypto';
import type { Environment } from '../../config/environment.js';
import { SubmissionsService } from '../../modules/submissions/application/submissions.service.js';
import { TelegramClient } from './telegram.client.js';
import { TelegramCommandService } from './telegram-command.service.js';
import { escapeHtml } from './telegram-event.service.js';
import { TelegramRepository } from './telegram.repository.js';

interface TelegramMessage {
  readonly message_id?: number;
  readonly text?: string;
  readonly chat?: { readonly id?: number | string };
}

interface TelegramCallback {
  readonly id?: string;
  readonly data?: string;
  readonly message?: TelegramMessage;
}

export interface TelegramUpdate {
  readonly update_id?: number | string;
  readonly message?: TelegramMessage;
  readonly callback_query?: TelegramCallback;
}

@Injectable()
export class TelegramWebhookService {
  private readonly logger = new Logger(TelegramWebhookService.name);
  private readonly enabled: boolean;
  private readonly secret?: string;
  private readonly allowedChatIds: ReadonlySet<string>;

  constructor(
    config: ConfigService<Environment, true>,
    private readonly repository: TelegramRepository,
    private readonly submissions: SubmissionsService,
    private readonly commands: TelegramCommandService,
    private readonly client: TelegramClient,
  ) {
    this.enabled = config.get('TELEGRAM_ENABLED', { infer: true });
    this.secret = config.get('TELEGRAM_WEBHOOK_SECRET', { infer: true });
    this.allowedChatIds = new Set(config.get('TELEGRAM_ALLOWED_CHAT_IDS', { infer: true })
      .split(',').map((value) => value.trim()).filter(Boolean));
  }

  configured(): boolean { return this.enabled && Boolean(this.secret); }

  validSecret(candidate: string | undefined): boolean {
    if (!this.secret || !candidate) return false;
    const expected = createHash('sha256').update(this.secret).digest();
    const actual = createHash('sha256').update(candidate).digest();
    return timingSafeEqual(expected, actual);
  }

  async process(update: TelegramUpdate): Promise<void> {
    const updateId = this.updateId(update.update_id);
    if (updateId && !await this.repository.claimUpdate(updateId)) return;
    try {
      if (update.callback_query) await this.callback(update.callback_query);
      else if (update.message) await this.message(update.message);
      if (updateId) await this.repository.finishUpdate(updateId);
    } catch (error) {
      if (updateId) await this.repository.finishUpdate(updateId, error);
      this.logger.error({ error, updateId }, 'Telegram webhook update failed');
    }
  }

  private async callback(callback: TelegramCallback): Promise<void> {
    const callbackId = callback.id;
    if (!callbackId) return;
    const chatId = this.chatId(callback.message?.chat?.id);
    if (!chatId || !this.allowedChatIds.has(chatId)) {
      await this.client.answerCallback(callbackId, 'Not authorized');
      return;
    }
    const [action, targetId] = (callback.data ?? '').split(':');
    if (!targetId) return this.client.answerCallback(callbackId, 'Unknown action');
    if (action === 'approve' || action === 'reject') {
      await this.reviewSubmission(callback, chatId, action, targetId);
      return;
    }
    if (action === 'report_action' || action === 'report_dismiss') {
      await this.reviewReport(callback, chatId, action, targetId);
      return;
    }
    await this.client.answerCallback(callbackId, 'Unknown action');
  }

  private async reviewSubmission(
    callback: TelegramCallback, chatId: string, action: 'approve' | 'reject', submissionId: string,
  ): Promise<void> {
    let ok = true;
    let message = action === 'approve' ? 'Approved' : 'Rejected';
    try {
      const source = {
        source: 'telegram', telegram_chat_id: chatId,
        telegram_msg_id: callback.message?.message_id ?? null,
      };
      if (action === 'approve') await this.submissions.approve(null, submissionId, undefined, source);
      else await this.submissions.reject(null, submissionId, 'Rejected via Telegram', source);
    } catch (error) {
      ok = false;
      message = this.reviewError(error);
    }
    await this.client.answerCallback(callback.id!, message);
    if (callback.message?.message_id) {
      const prefix = ok ? action === 'approve' ? '✅ APPROVED' : '❌ REJECTED' : `⚠️ ${message}`;
      await this.client.editMessage(
        chatId, callback.message.message_id,
        `${prefix}\n\n${escapeHtml(callback.message.text ?? '')}`, ok,
      );
    }
  }

  private async reviewReport(
    callback: TelegramCallback,
    chatId: string,
    action: 'report_action' | 'report_dismiss',
    reportId: string,
  ): Promise<void> {
    const result = await this.repository.reviewReport(
      reportId, action === 'report_action' ? 'action' : 'dismiss', chatId,
    );
    await this.client.answerCallback(callback.id!, result.message);
    if (callback.message?.message_id) {
      const prefix = result.ok
        ? action === 'report_action' ? '✅ ACTIONED · user banned' : '❌ DISMISSED'
        : `⚠️ ${result.message}`;
      await this.client.editMessage(
        chatId, callback.message.message_id,
        `${prefix}\n\n${escapeHtml(callback.message.text ?? '')}`, result.ok,
      );
    }
  }

  private async message(message: TelegramMessage): Promise<void> {
    const chatId = this.chatId(message.chat?.id);
    if (!chatId) return;
    if (!this.allowedChatIds.has(chatId)) {
      await this.client.sendMessage(chatId, 'Not authorized.');
      return;
    }
    await this.commands.handle(chatId, message.text ?? '');
  }

  private reviewError(error: unknown): string {
    if (error instanceof HttpException) {
      const response = error.getResponse();
      if (response && typeof response === 'object' && 'code' in response) {
        const code = String(response.code);
        if (code === 'SUBMISSION_NOT_FOUND') return 'Submission not found';
        if (code === 'SUBMISSION_ALREADY_REVIEWED') return 'Already moderated';
      }
    }
    this.logger.error({ error }, 'Telegram submission review failed');
    return 'Internal error';
  }

  private updateId(value: number | string | undefined): string | null {
    const normalized = String(value ?? '');
    return /^\d+$/.test(normalized) ? normalized : null;
  }

  private chatId(value: number | string | undefined): string | null {
    const normalized = String(value ?? '');
    return /^-?\d+$/.test(normalized) ? normalized : null;
  }
}
