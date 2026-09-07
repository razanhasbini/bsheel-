import { ConfigService } from '@nestjs/config';
import type { Environment } from '../../config/environment.js';
import { SubmissionsService } from '../../modules/submissions/application/submissions.service.js';
import { TelegramClient } from './telegram.client.js';
import { TelegramCommandService } from './telegram-command.service.js';
import { TelegramRepository } from './telegram.repository.js';
interface TelegramMessage {
    readonly message_id?: number;
    readonly text?: string;
    readonly chat?: {
        readonly id?: number | string;
    };
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
export declare class TelegramWebhookService {
    private readonly repository;
    private readonly submissions;
    private readonly commands;
    private readonly client;
    private readonly logger;
    private readonly enabled;
    private readonly secret?;
    private readonly allowedChatIds;
    constructor(config: ConfigService<Environment, true>, repository: TelegramRepository, submissions: SubmissionsService, commands: TelegramCommandService, client: TelegramClient);
    configured(): boolean;
    validSecret(candidate: string | undefined): boolean;
    process(update: TelegramUpdate): Promise<void>;
    private callback;
    private reviewSubmission;
    private reviewReport;
    private message;
    private reviewError;
    private updateId;
    private chatId;
}
export {};
