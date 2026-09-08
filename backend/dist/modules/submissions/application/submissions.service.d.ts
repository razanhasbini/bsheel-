import { SubmissionsRepository, type SubmissionRecord } from '../infrastructure/submissions.repository.js';
import type { CreateSubmissionDto } from '../presentation/submission.dto.js';
export declare class SubmissionsService {
    private readonly repository;
    constructor(repository: SubmissionsRepository);
    create(userId: string, input: CreateSubmissionDto): Promise<SubmissionRecord>;
    detail(id: string, viewerId: string): Promise<Record<string, unknown>>;
    listUser(userId: string, viewerId: string, limit: number, offset: number): Promise<readonly SubmissionRecord[]>;
    adminDetail(id: string): Promise<Record<string, unknown>>;
    reviewQueue(limit: number, offset: number): Promise<readonly Record<string, unknown>[]>;
    listForAdmin(filter: {
        status?: 'pending' | 'approved' | 'rejected' | 'all';
        appealed?: boolean;
        visibility?: 'visible' | 'hidden_from_feed' | 'deleted' | 'not_visible';
        order?: 'asc' | 'desc';
        limit?: number;
        offset?: number;
    }): Promise<readonly Record<string, unknown>[]>;
    appeal(userId: string, id: string, note: string): Promise<void>;
    approve(actorId: string | null, id: string, note?: string, source?: Record<string, unknown>): Promise<void>;
    reject(actorId: string | null, id: string, note: string, source?: Record<string, unknown>): Promise<void>;
    visibility(userId: string, id: string, visibility: 'visible' | 'hidden_from_feed' | 'deleted'): Promise<void>;
    removeByAdmin(actorId: string, id: string, reason: string): Promise<void>;
}
