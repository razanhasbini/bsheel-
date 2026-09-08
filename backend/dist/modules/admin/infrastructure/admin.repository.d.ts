import { DatabaseService } from '../../../infrastructure/database/database.service.js';
import type { InjectQuestDto, SetQotdDto } from '../presentation/admin.dto.js';
export declare class AdminRepository {
    private readonly database;
    constructor(database: DatabaseService);
    me(userId: string): Promise<import("pg").QueryResultRow>;
    stats(): Promise<import("pg").QueryResultRow>;
    users(query: string | undefined, limit: number, offset: number): Promise<import("pg").QueryResultRow[]>;
    createUser(actorId: string, input: {
        email: string;
        passwordHash: string;
        username: string;
        displayName: string;
    }): Promise<{
        userId: string;
    }>;
    queueUserDeletion(actorId: string, userId: string): Promise<void>;
    setAdminRole(actorId: string, userId: string, role?: 'moderator' | 'super_admin'): Promise<void>;
    passwordIdentity(userId: string): Promise<{
        email: string;
        username: string;
    } | null>;
    forceResetPassword(actorId: string, userId: string, passwordHash: string): Promise<void>;
    queuePasswordRecovery(actorId: string, userId: string, token: {
        tokenHash: Buffer;
        encryptedToken: Buffer;
        expiresAt: Date;
    }): Promise<void>;
    setStatus(actorId: string, userId: string, status: string, reason: string): Promise<void>;
    updateUserProfile(actorId: string, userId: string, input: {
        username?: string;
        displayName?: string;
        bio?: string;
        xp?: number;
        level?: number;
        questsCompleted?: number;
        reason: string;
    }): Promise<void>;
    setXp(actorId: string, userId: string, xp: number, level: number, completed: number, reason: string): Promise<void>;
    reports(status: string, limit: number, offset: number): Promise<import("pg").QueryResultRow[]>;
    reviewReport(actorId: string, id: string, status: string, note?: string): Promise<void>;
    injections(limit: number, offset: number): Promise<import("pg").QueryResultRow[]>;
    inject(actorId: string, input: InjectQuestDto): Promise<any>;
    cancelInjection(actorId: string, id: string): Promise<void>;
    notify(actorId: string, targetUserId: string | undefined, title: string, body: string, type: string): Promise<{
        recipients: number;
    }>;
    config(): Promise<import("pg").QueryResultRow[]>;
    xpAudit(limit: number, offset: number): Promise<import("pg").QueryResultRow[]>;
    notifications(limit: number, offset: number): Promise<import("pg").QueryResultRow[]>;
    publicConfig(): Promise<import("pg").QueryResultRow[]>;
    setConfig(actorId: string, key: string, value: unknown, description: string | undefined, isPublic: boolean): Promise<import("pg").QueryResultRow>;
    qotd(limit: number, offset: number): Promise<import("pg").QueryResultRow[]>;
    setQotd(actorId: string, input: SetQotdDto): Promise<import("pg").QueryResultRow>;
    deleteQotd(id: string): Promise<void>;
    waitlist(limit: number, offset: number): Promise<import("pg").QueryResultRow[]>;
    suggestions(status: string, limit: number, offset: number): Promise<import("pg").QueryResultRow[]>;
    reviewSuggestion(actorId: string, id: string, status: 'approved' | 'rejected', xpReward: number, durationHours: number): Promise<any>;
    private audit;
}
