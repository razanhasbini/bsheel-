import { DatabaseService } from '../../../infrastructure/database/database.service.js';
import type { CreateSubmissionDto } from '../presentation/submission.dto.js';
export interface SubmissionRecord {
    readonly id: string;
    readonly user_quest_id: string;
    readonly user_id: string;
    readonly media_url: string;
    readonly media_type: string;
    readonly caption: string | null;
    readonly status: string;
    readonly reviewed_by: string | null;
    readonly review_note: string | null;
    readonly submitted_at: Date;
    readonly reviewed_at: Date | null;
    readonly appeal_note: string | null;
    readonly appealed: boolean;
    readonly show_in_feed: boolean;
    readonly visibility: string;
    readonly deleted_at: Date | null;
    readonly xp_awarded: boolean;
    readonly xp_awarded_amount: number;
}
export declare class SubmissionsRepository {
    private readonly database;
    constructor(database: DatabaseService);
    create(userId: string, input: CreateSubmissionDto): Promise<SubmissionRecord>;
    private parseMediaKeys;
    findVisibleToUser(id: string, viewerId: string): Promise<Record<string, unknown> | null>;
    listUser(userId: string, viewerId: string, limit: number, offset: number): Promise<readonly SubmissionRecord[]>;
    listPending(limit: number, offset: number): Promise<readonly Record<string, unknown>[]>;
    appeal(userId: string, id: string, appealNote: string): Promise<void>;
    approve(actorId: string | null, id: string, reviewNote?: string, source?: Record<string, unknown>): Promise<void>;
    reject(actorId: string | null, id: string, reviewNote: string, source?: Record<string, unknown>): Promise<void>;
    setVisibility(userId: string, id: string, visibility: 'visible' | 'hidden_from_feed' | 'deleted'): Promise<void>;
    removeByAdmin(actorId: string, id: string, reason: string): Promise<void>;
    private transitionVisibility;
    private lockForReview;
    private notifyAdmins;
    private createNotification;
    private notifyCollabPartners;
    private emit;
    private audit;
}
