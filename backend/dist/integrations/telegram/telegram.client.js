var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
var __metadata = (this && this.__metadata) || function (k, v) {
    if (typeof Reflect === "object" && typeof Reflect.metadata === "function") return Reflect.metadata(k, v);
};
import { Injectable, ServiceUnavailableException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
let TelegramClient = class TelegramClient {
    enabled;
    botToken;
    adminChatId;
    timeoutMs;
    apiBaseUrl;
    failures = 0;
    circuitOpenUntil = 0;
    constructor(config) {
        this.enabled = config.get('TELEGRAM_ENABLED', { infer: true });
        this.botToken = config.get('TELEGRAM_BOT_TOKEN', { infer: true });
        this.adminChatId = config.get('TELEGRAM_ADMIN_CHAT_ID', { infer: true });
        this.timeoutMs = config.get('TELEGRAM_TIMEOUT_MS', { infer: true });
        this.apiBaseUrl = config.get('TELEGRAM_API_BASE_URL', { infer: true }).replace(/\/$/, '');
    }
    isEnabled() { return this.enabled; }
    async sendAdminMessage(text, keyboard) {
        return this.sendMessage(this.requiredChatId(), text, keyboard);
    }
    async sendMessage(chatId, text, keyboard) {
        const result = await this.call('sendMessage', {
            chat_id: chatId,
            text,
            parse_mode: 'HTML',
            ...(keyboard ? { reply_markup: { inline_keyboard: keyboard } } : {}),
        });
        return result.result?.message_id ?? null;
    }
    async sendAdminMediaGroup(urls, mediaType, caption) {
        const media = urls.slice(0, 10).map((url, index) => ({
            type: isVideo(url, mediaType) ? 'video' : 'photo',
            media: url,
            ...(index === 0 ? { caption: caption.slice(0, 1024), parse_mode: 'HTML' } : {}),
        }));
        if (media.length)
            await this.call('sendMediaGroup', { chat_id: this.requiredChatId(), media });
    }
    async editAdminMessage(messageId, text) {
        await this.editMessage(this.requiredChatId(), messageId, text, true);
    }
    async editMessage(chatId, messageId, text, clearKeyboard = false) {
        await this.call('editMessageText', {
            chat_id: chatId,
            message_id: messageId,
            text,
            parse_mode: 'HTML',
            ...(clearKeyboard ? { reply_markup: { inline_keyboard: [] } } : {}),
        }, true);
    }
    async answerCallback(callbackQueryId, text) {
        await this.call('answerCallbackQuery', { callback_query_id: callbackQueryId, text }, true);
    }
    async deleteAdminMessage(messageId) {
        await this.call('deleteMessage', {
            chat_id: this.requiredChatId(),
            message_id: messageId,
        }, true);
    }
    async call(method, body, allowBenign400 = false) {
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
            const result = await response.json();
            if (!response.ok || result.ok === false) {
                const benign = allowBenign400 && response.status === 400
                    && /not modified|not found/i.test(result.description ?? '');
                if (benign)
                    return result;
                throw new Error(`Telegram ${method} failed: ${result.description ?? response.status}`);
            }
            this.failures = 0;
            return result;
        }
        catch (error) {
            this.failures += 1;
            if (this.failures >= 5) {
                this.circuitOpenUntil = Date.now() + 30_000;
                this.failures = 0;
            }
            throw error;
        }
    }
    requiredChatId() {
        if (!this.adminChatId)
            throw new Error('Telegram admin chat id is missing');
        return this.adminChatId;
    }
};
TelegramClient = __decorate([
    Injectable(),
    __metadata("design:paramtypes", [ConfigService])
], TelegramClient);
export { TelegramClient };
function isVideo(url, mediaType) {
    if (mediaType === 'video')
        return true;
    const path = url.toLowerCase().split('?')[0];
    return ['.mp4', '.mov', '.webm', '.m4v'].some((extension) => path.endsWith(extension));
}
//# sourceMappingURL=telegram.client.js.map