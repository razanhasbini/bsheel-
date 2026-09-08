import { AuthActionTokenCipher } from '../../auth/infrastructure/auth-action-token-cipher.js';
import { SubmissionsService } from '../../submissions/application/submissions.service.js';
import { AdminRepository } from '../infrastructure/admin.repository.js';
import type { CreateUserDto, InjectQuestDto, SetQotdDto } from '../presentation/admin.dto.js';
export declare class AdminService {
    private readonly repository;
    private readonly submissions;
    private readonly actionTokenCipher;
    constructor(repository: AdminRepository, submissions: SubmissionsService, actionTokenCipher: AuthActionTokenCipher);
    me(userId: string): Promise<import("pg").QueryResultRow>;
    stats(): Promise<import("pg").QueryResultRow>;
    users(q: string | undefined, limit: number, offset: number): Promise<import("pg").QueryResultRow[]>;
    createUser(actorId: string, input: CreateUserDto): Promise<{
        userId: string;
    }>;
    deleteUser(actorId: string, id: string): Promise<void>;
    setAdminRole(actorId: string, id: string, role?: 'moderator' | 'super_admin'): Promise<void>;
    forceResetPassword(actorId: string, id: string, newPassword: string): Promise<void>;
    requestPasswordRecovery(actorId: string, id: string): Promise<void>;
    setStatus(actorId: string, id: string, status: string, reason: string): Promise<void>;
    setXp(actorId: string, id: string, xp: number, level: number, completed: number, reason: string): Promise<void>;
    reports(status: string, limit: number, offset: number): Promise<import("pg").QueryResultRow[]>;
    reviewReport(actorId: string, id: string, status: string, note?: string): Promise<void>;
    removePost(actorId: string, id: string, reason: string): Promise<void>;
    injections(limit: number, offset: number): Promise<import("pg").QueryResultRow[]>;
    inject(actorId: string, input: InjectQuestDto): Promise<any>;
    cancelInjection(actorId: string, id: string): Promise<void>;
    notify(actorId: string, targetId: string | undefined, title: string, body: string, type: string): Promise<{
        recipients: number;
    }>;
    config(): Promise<import("pg").QueryResultRow[]>;
    updateUserProfile(actorId: string, userId: string, input: {
        username?: string;
        displayName?: string;
        bio?: string;
        xp?: number;
        level?: number;
        questsCompleted?: number;
        reason: string;
    }): Promise<void>;
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
}
