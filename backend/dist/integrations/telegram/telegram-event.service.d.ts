import { ObjectStorageService } from '../../modules/media/infrastructure/object-storage.service.js';
import { TelegramClient } from './telegram.client.js';
import { TelegramRepository } from './telegram.repository.js';
export declare class TelegramEventService {
    private readonly repository;
    private readonly client;
    private readonly storage;
    constructor(repository: TelegramRepository, client: TelegramClient, storage: ObjectStorageService);
    handle(type: string, data: Record<string, unknown>): Promise<void>;
    private sendDailySummary;
    private sendSignup;
    private sendReport;
    private sendReviewAlert;
    private syncReview;
    private deleteReviewMessage;
}
export declare function escapeHtml(value: string | null | undefined): string;
