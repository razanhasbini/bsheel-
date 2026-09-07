var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
var __metadata = (this && this.__metadata) || function (k, v) {
    if (typeof Reflect === "object" && typeof Reflect.metadata === "function") return Reflect.metadata(k, v);
};
var __param = (this && this.__param) || function (paramIndex, decorator) {
    return function (target, key) { decorator(target, key, paramIndex); }
};
import { Body, Controller, ForbiddenException, Headers, HttpCode, Post, ServiceUnavailableException } from '@nestjs/common';
import { Throttle } from '@nestjs/throttler';
import { Public } from '../../common/auth/public.decorator.js';
import { TelegramWebhookService } from './telegram-webhook.service.js';
let TelegramController = class TelegramController {
    webhook;
    constructor(webhook) {
        this.webhook = webhook;
    }
    async receive(secret, update) {
        if (!this.webhook.configured()) {
            throw new ServiceUnavailableException({ code: 'TELEGRAM_NOT_CONFIGURED', message: 'Telegram is not configured' });
        }
        if (!this.webhook.validSecret(secret)) {
            throw new ForbiddenException({ code: 'INVALID_TELEGRAM_SECRET', message: 'Forbidden' });
        }
        await this.webhook.process(update);
        return { accepted: true };
    }
};
__decorate([
    Public(),
    Post('webhook'),
    HttpCode(200),
    Throttle({ default: { limit: 120, ttl: 60_000 } }),
    __param(0, Headers('x-telegram-bot-api-secret-token')),
    __param(1, Body()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, Object]),
    __metadata("design:returntype", Promise)
], TelegramController.prototype, "receive", null);
TelegramController = __decorate([
    Controller({ path: 'integrations/telegram', version: '1' }),
    __metadata("design:paramtypes", [TelegramWebhookService])
], TelegramController);
export { TelegramController };
//# sourceMappingURL=telegram.controller.js.map