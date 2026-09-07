var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
var __metadata = (this && this.__metadata) || function (k, v) {
    if (typeof Reflect === "object" && typeof Reflect.metadata === "function") return Reflect.metadata(k, v);
};
var TelegramWebhookService_1;
import { HttpException, Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { createHash, timingSafeEqual } from 'node:crypto';
import { SubmissionsService } from '../../modules/submissions/application/submissions.service.js';
import { TelegramClient } from './telegram.client.js';
import { TelegramCommandService } from './telegram-command.service.js';
import { escapeHtml } from './telegram-event.service.js';
import { TelegramRepository } from './telegram.repository.js';
let TelegramWebhookService = TelegramWebhookService_1 = class TelegramWebhookService {
    repository;
    submissions;
    commands;
    client;
    logger = new Logger(TelegramWebhookService_1.name);
    enabled;
    secret;
    allowedChatIds;
    constructor(config, repository, submissions, commands, client) {
        this.repository = repository;
        this.submissions = submissions;
        this.commands = commands;
        this.client = client;
        this.enabled = config.get('TELEGRAM_ENABLED', { infer: true });
        this.secret = config.get('TELEGRAM_WEBHOOK_SECRET', { infer: true });
        this.allowedChatIds = new Set(config.get('TELEGRAM_ALLOWED_CHAT_IDS', { infer: true })
            .split(',').map((value) => value.trim()).filter(Boolean));
    }
    configured() { return this.enabled && Boolean(this.secret); }
    validSecret(candidate) {
        if (!this.secret || !candidate)
            return false;
        const expected = createHash('sha256').update(this.secret).digest();
        const actual = createHash('sha256').update(candidate).digest();
        return timingSafeEqual(expected, actual);
    }
    async process(update) {
        const updateId = this.updateId(update.update_id);
        if (updateId && !await this.repository.claimUpdate(updateId))
            return;
        try {
            if (update.callback_query)
                await this.callback(update.callback_query);
            else if (update.message)
                await this.message(update.message);
            if (updateId)
                await this.repository.finishUpdate(updateId);
        }
        catch (error) {
            if (updateId)
                await this.repository.finishUpdate(updateId, error);
            this.logger.error({ error, updateId }, 'Telegram webhook update failed');
        }
    }
    async callback(callback) {
        const callbackId = callback.id;
        if (!callbackId)
            return;
        const chatId = this.chatId(callback.message?.chat?.id);
        if (!chatId || !this.allowedChatIds.has(chatId)) {
            await this.client.answerCallback(callbackId, 'Not authorized');
            return;
        }
        const [action, targetId] = (callback.data ?? '').split(':');
        if (!targetId)
            return this.client.answerCallback(callbackId, 'Unknown action');
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
    async reviewSubmission(callback, chatId, action, submissionId) {
        let ok = true;
        let message = action === 'approve' ? 'Approved' : 'Rejected';
        try {
            const source = {
                source: 'telegram', telegram_chat_id: chatId,
                telegram_msg_id: callback.message?.message_id ?? null,
            };
            if (action === 'approve')
                await this.submissions.approve(null, submissionId, undefined, source);
            else
                await this.submissions.reject(null, submissionId, 'Rejected via Telegram', source);
        }
        catch (error) {
            ok = false;
            message = this.reviewError(error);
        }
        await this.client.answerCallback(callback.id, message);
        if (callback.message?.message_id) {
            const prefix = ok ? action === 'approve' ? '✅ APPROVED' : '❌ REJECTED' : `⚠️ ${message}`;
            await this.client.editMessage(chatId, callback.message.message_id, `${prefix}\n\n${escapeHtml(callback.message.text ?? '')}`, ok);
        }
    }
    async reviewReport(callback, chatId, action, reportId) {
        const result = await this.repository.reviewReport(reportId, action === 'report_action' ? 'action' : 'dismiss', chatId);
        await this.client.answerCallback(callback.id, result.message);
        if (callback.message?.message_id) {
            const prefix = result.ok
                ? action === 'report_action' ? '✅ ACTIONED · user banned' : '❌ DISMISSED'
                : `⚠️ ${result.message}`;
            await this.client.editMessage(chatId, callback.message.message_id, `${prefix}\n\n${escapeHtml(callback.message.text ?? '')}`, result.ok);
        }
    }
    async message(message) {
        const chatId = this.chatId(message.chat?.id);
        if (!chatId)
            return;
        if (!this.allowedChatIds.has(chatId)) {
            await this.client.sendMessage(chatId, 'Not authorized.');
            return;
        }
        await this.commands.handle(chatId, message.text ?? '');
    }
    reviewError(error) {
        if (error instanceof HttpException) {
            const response = error.getResponse();
            if (response && typeof response === 'object' && 'code' in response) {
                const code = String(response.code);
                if (code === 'SUBMISSION_NOT_FOUND')
                    return 'Submission not found';
                if (code === 'SUBMISSION_ALREADY_REVIEWED')
                    return 'Already moderated';
            }
        }
        this.logger.error({ error }, 'Telegram submission review failed');
        return 'Internal error';
    }
    updateId(value) {
        const normalized = String(value ?? '');
        return /^\d+$/.test(normalized) ? normalized : null;
    }
    chatId(value) {
        const normalized = String(value ?? '');
        return /^-?\d+$/.test(normalized) ? normalized : null;
    }
};
TelegramWebhookService = TelegramWebhookService_1 = __decorate([
    Injectable(),
    __metadata("design:paramtypes", [ConfigService,
        TelegramRepository,
        SubmissionsService,
        TelegramCommandService,
        TelegramClient])
], TelegramWebhookService);
export { TelegramWebhookService };
//# sourceMappingURL=telegram-webhook.service.js.map