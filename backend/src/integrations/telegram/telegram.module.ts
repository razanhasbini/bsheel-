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

@Module({
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
export class TelegramModule {}
