import { DatabaseService } from '../../infrastructure/database/database.service.js';
export interface TelegramSubmission {
    readonly id: string;
    readonly media_url: string;
    readonly media_type: string;
    readonly caption: string | null;
    readonly status: string;
    readonly review_note: string | null;
    readonly appeal_note: string | null;
    readonly appealed: boolean;
    readonly telegram_message_id: string | number | null;
    readonly quest_title: string;
    readonly username: string;
    readonly display_name: string;
}
export interface TelegramUser {
    readonly id: string;
    readonly email: string;
    readonly username: string;
    readonly display_name: string;
    readonly providers: string[];
}
export interface TelegramReport {
    readonly id: string;
    readonly reported_type: string;
    readonly reason: string;
    readonly reporter_name: string;
    readonly reported_name: string;
}
export interface TelegramProfileCard {
    readonly id: string;
    readonly username: string;
    readonly display_name: string;
    readonly xp: number;
    readonly level: number;
    readonly quests_completed: number;
    readonly account_status: string;
    readonly created_at: Date;
    readonly pending_submissions: number;
    readonly last_submission_at: Date | null;
}
export interface TelegramCommandState {
    readonly chat_id: string;
    readonly command: string;
    readonly step: string;
    readonly data: Record<string, unknown>;
}
export interface TelegramDailySummary {
    readonly submissions: number;
    readonly approved: number;
    readonly rejected: number;
    readonly signups: number;
    readonly submitters: number;
    readonly pending_submissions: number;
    readonly pending_appeals: number;
    readonly pending_reports: number;
    readonly top_quests: readonly {
        title: string;
        approvals: number;
    }[];
}
export declare class TelegramRepository {
    private readonly database;
    constructor(database: DatabaseService);
    submission(id: string): Promise<TelegramSubmission | null>;
    setSubmissionMessageId(id: string, messageId: number): Promise<void>;
    user(id: string): Promise<TelegramUser | null>;
    report(id: string): Promise<TelegramReport | null>;
    claimUpdate(updateId: string): Promise<boolean>;
    finishUpdate(updateId: string, error?: unknown): Promise<void>;
    pendingCounts(): Promise<{
        submissions: number;
        appeals: number;
        reports: number;
    }>;
    stats(days: 1 | 7): Promise<{
        submissions: number;
        approved: number;
        rejected: number;
        signups: number;
        submitters: number;
    }>;
    profileByHandle(handle: string): Promise<TelegramProfileCard | null>;
    setAccountStatus(userId: string, status: 'active' | 'banned', chatId: string): Promise<void>;
    broadcast(title: string, body: string, chatId: string): Promise<number>;
    activeQuests(): Promise<readonly {
        id: string;
        title: string;
        description: string;
    }[]>;
    audit(handle?: string): Promise<readonly {
        created_at: Date;
        actor_name: string | null;
        action: string;
    }[]>;
    weeklyLeaderboard(): Promise<readonly {
        display_name: string;
        username: string;
        approvals: number;
    }[]>;
    dailySummary(): Promise<TelegramDailySummary>;
    commandState(chatId: string): Promise<TelegramCommandState | null>;
    setCommandState(chatId: string, command: string, step: string, data: Record<string, unknown>): Promise<void>;
    clearCommandState(chatId: string): Promise<void>;
    createQuest(data: Record<string, unknown>, chatId: string): Promise<string>;
    reviewReport(reportId: string, action: 'dismiss' | 'action', chatId: string): Promise<{
        ok: boolean;
        message: string;
    }>;
}
