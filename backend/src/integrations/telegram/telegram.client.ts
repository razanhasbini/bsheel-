import { Injectable, ServiceUnavailableException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import type { Environment } from '../../config/environment.js';

interface TelegramResponse {
  readonly ok?: boolean;
  readonly description?: string;
  readonly result?: { readonly message_id?: number };
}

export type TelegramKeyboard = readonly (readonly { text: string; callback_data: string }[])[];

@Injectable()
export class TelegramClient {
  private readonly enabled: boolean;
  private readonly botToken?: string;
  private readonly adminChatId?: string;
  private readonly timeoutMs: number;
  private readonly apiBaseUrl: string;
  private failures = 0;
  private circuitOpenUntil = 0;

  constructor(config: ConfigService<Environment, true>) {
    this.enabled = config.get('TELEGRAM_ENABLED', { infer: true });
    this.botToken = config.get('TELEGRAM_BOT_TOKEN', { infer: true });
    this.adminChatId = config.get('TELEGRAM_ADMIN_CHAT_ID', { infer: true });
    this.timeoutMs = config.get('TELEGRAM_TIMEOUT_MS', { infer: true });
    this.apiBaseUrl = config.get('TELEGRAM_API_BASE_URL', { infer: true }).replace(/\/$/, '');
  }

  isEnabled(): boolean { return this.enabled; }

  async sendAdminMessage(
    text: string,
    keyboard?: TelegramKeyboard,
  ): Promise<number | null> {
    return this.sendMessage(this.requiredChatId(), text, keyboard);
  }

  async sendMessage(chatId: string, text: string, keyboard?: TelegramKeyboard): Promise<number | null> {
    const result = await this.call('sendMessage', {
      chat_id: chatId,
      text,
      parse_mode: 'HTML',
      ...(keyboard ? { reply_markup: { inline_keyboard: keyboard } } : {}),
    });
    return result.result?.message_id ?? null;
  }

  async sendAdminMediaGroup(
    urls: readonly string[],
    mediaType: string,
    caption: string,
  ): Promise<void> {
    const media = urls.slice(0, 10).map((url, index) => ({
      type: isVideo(url, mediaType) ? 'video' : 'photo',
      media: url,
      ...(index === 0 ? { caption: caption.slice(0, 1024), parse_mode: 'HTML' } : {}),
    }));
    if (media.length) await this.call('sendMediaGroup', { chat_id: this.requiredChatId(), media });
  }

  async editAdminMessage(messageId: number, text: string): Promise<void> {
    await this.editMessage(this.requiredChatId(), messageId, text, true);
  }

  async editMessage(chatId: string, messageId: number, text: string, clearKeyboard = false): Promise<void> {
    await this.call('editMessageText', {
      chat_id: chatId,
      message_id: messageId,
      text,
      parse_mode: 'HTML',
      ...(clearKeyboard ? { reply_markup: { inline_keyboard: [] } } : {}),
    }, true);
  }

  async answerCallback(callbackQueryId: string, text: string): Promise<void> {
    await this.call('answerCallbackQuery', { callback_query_id: callbackQueryId, text }, true);
  }

  async deleteAdminMessage(messageId: number): Promise<void> {
    await this.call('deleteMessage', {
      chat_id: this.requiredChatId(),
      message_id: messageId,
    }, true);
  }

  private async call(method: string, body: Record<string, unknown>, allowBenign400 = false): Promise<TelegramResponse> {
    if (!this.enabled || !this.botToken) {
      throw new ServiceUnavailableException({ code: 'TELEGRAM_UNAVAILABLE', message: 'Telegram is not configured' });
    }
    if (this.circuitOpenUntil > Date.now()) {
      throw new ServiceUnavailableException({ code: 'TELEGRAM_CIRCUIT_OPEN', message: 'Telegram is temporarily unavailable' });
    }
    try {
      const response = await fetch(`${this.apiBaseUrl}/bot${this.botToken}/${method}`, {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify(body),
        signal: AbortSignal.timeout(this.timeoutMs),
      });
      const result = await response.json() as TelegramResponse;
      if (!response.ok || result.ok === false) {
        const benign = allowBenign400 && response.status === 400
          && /not modified|not found/i.test(result.description ?? '');
        if (benign) return result;
        throw new Error(`Telegram ${method} failed: ${result.description ?? response.status}`);
      }
      this.failures = 0;
      return result;
    } catch (error) {
      this.failures += 1;
      if (this.failures >= 5) {
        this.circuitOpenUntil = Date.now() + 30_000;
        this.failures = 0;
      }
      throw error;
    }
  }

  private requiredChatId(): string {
    if (!this.adminChatId) throw new Error('Telegram admin chat id is missing');
    return this.adminChatId;
  }
}

function isVideo(url: string, mediaType: string): boolean {
  if (mediaType === 'video') return true;
  const path = url.toLowerCase().split('?')[0];
  return ['.mp4', '.mov', '.webm', '.m4v'].some((extension) => path.endsWith(extension));
}
