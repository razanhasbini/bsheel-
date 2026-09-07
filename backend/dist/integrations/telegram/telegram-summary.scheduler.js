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
import { InjectQueue } from '@nestjs/bullmq';
import { Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
let TelegramSummaryScheduler = class TelegramSummaryScheduler {
    config;
    queue;
    constructor(config, queue) {
        this.config = config;
        this.queue = queue;
    }
    async onApplicationBootstrap() {
        if (!this.config.get('TELEGRAM_ENABLED', { infer: true }))
            return;
        await this.queue.upsertJobScheduler('telegram-daily-summary', { pattern: '0 6 * * *', tz: 'UTC' }, {
            name: 'telegram.daily_summary',
            data: {},
            opts: {
                attempts: 5,
                backoff: { type: 'exponential', delay: 2_000 },
                removeOnComplete: 1_000,
                removeOnFail: 5_000,
            },
        });
    }
};
TelegramSummaryScheduler = __decorate([
    Injectable(),
    __param(1, InjectQueue('domain-events')),
    __metadata("design:paramtypes", [ConfigService, Function])
], TelegramSummaryScheduler);
export { TelegramSummaryScheduler };
//# sourceMappingURL=telegram-summary.scheduler.js.map