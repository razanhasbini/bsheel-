import { ConfigService } from '@nestjs/config';
import type { Environment } from '../../config/environment.js';
export type TelegramKeyboard = readonly (readonly {
    text: string;
    callback_data: string;
}[])[];
export declare class TelegramClient {
    private readonly enabled;
    private readonly botToken?;
    private readonly adminChatId?;
    private readonly timeoutMs;
    private readonly apiBaseUrl;
    private failures;
    private circuitOpenUntil;
    constructor(config: ConfigService<Environment, true>);
    isEnabled(): boolean;
    sendAdminMessage(text: string, keyboard?: TelegramKeyboard): Promise<number | null>;
    sendMessage(chatId: string, text: string, keyboard?: TelegramKeyboard): Promise<number | null>;
    sendAdminMediaGroup(urls: readonly string[], mediaType: string, caption: string): Promise<void>;
    editAdminMessage(messageId: number, text: string): Promise<void>;
    editMessage(chatId: string, messageId: number, text: string, clearKeyboard?: boolean): Promise<void>;
    answerCallback(callbackQueryId: string, text: string): Promise<void>;
    deleteAdminMessage(messageId: number): Promise<void>;
    private call;
    private requiredChatId;
}
