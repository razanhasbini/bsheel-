import { TelegramWebhookService, type TelegramUpdate } from './telegram-webhook.service.js';
export declare class TelegramController {
    private readonly webhook;
    constructor(webhook: TelegramWebhookService);
    receive(secret: string | undefined, update: TelegramUpdate): Promise<{
        accepted: true;
    }>;
}
