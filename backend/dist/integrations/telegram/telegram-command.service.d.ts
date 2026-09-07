import { TelegramClient } from './telegram.client.js';
import { TelegramRepository } from './telegram.repository.js';
export declare class TelegramCommandService {
    private readonly repository;
    private readonly client;
    constructor(repository: TelegramRepository, client: TelegramClient);
    handle(chatId: string, rawText: string): Promise<void>;
    private help;
    private broadcast;
    private pending;
    private stats;
    private user;
    private ban;
    private quest;
    private audit;
    private leaderboard;
    private routeState;
    private questStep;
    private say;
}
