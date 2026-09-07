var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
import { Module } from '@nestjs/common';
import { MediaModule } from '../../modules/media/media.module.js';
import { SubmissionsModule } from '../../modules/submissions/submissions.module.js';
import { TelegramClient } from './telegram.client.js';
import { TelegramCommandService } from './telegram-command.service.js';
import { TelegramEventService } from './telegram-event.service.js';
import { TelegramRepository } from './telegram.repository.js';
import { TelegramController } from './telegram.controller.js';
import { TelegramWebhookService } from './telegram-webhook.service.js';
import { TelegramSummaryScheduler } from './telegram-summary.scheduler.js';
let TelegramModule = class TelegramModule {
};
TelegramModule = __decorate([
    Module({
        imports: [MediaModule, SubmissionsModule],
        controllers: [TelegramController],
        providers: [
            TelegramClient,
            TelegramRepository,
            TelegramEventService,
            TelegramCommandService,
            TelegramWebhookService,
            TelegramSummaryScheduler,
        ],
        exports: [TelegramClient, TelegramRepository, TelegramEventService],
    })
], TelegramModule);
export { TelegramModule };
//# sourceMappingURL=telegram.module.js.map