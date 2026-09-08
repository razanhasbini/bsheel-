import type { AuthUser } from '../../../common/auth/auth-user.js';
import { SubmissionsService } from '../application/submissions.service.js';
import { AppealSubmissionDto, CreateSubmissionDto, RejectSubmissionDto, ReviewSubmissionDto, SetVisibilityDto } from './submission.dto.js';
declare class SubmissionListQuery {
    limit: number;
    offset: number;
}
declare class SubmissionIdParam {
    id: string;
}
declare class AdminSubmissionListQuery {
    status: 'pending' | 'approved' | 'rejected' | 'all';
    appealed?: string;
    visibility?: 'visible' | 'hidden_from_feed' | 'deleted' | 'not_visible';
    order: 'asc' | 'desc';
    limit: number;
    offset: number;
}
export declare class SubmissionsController {
    private readonly service;
    constructor(service: SubmissionsService);
    create(user: AuthUser, body: CreateSubmissionDto): Promise<import("../infrastructure/submissions.repository.js").SubmissionRecord>;
    listUser(user: AuthUser, params: SubmissionIdParam, query: SubmissionListQuery): Promise<readonly import("../infrastructure/submissions.repository.js").SubmissionRecord[]>;
    pending(query: AdminSubmissionListQuery): Promise<readonly Record<string, unknown>[]>;
    reviewQueue(query: AdminSubmissionListQuery): Promise<readonly Record<string, unknown>[]>;
    adminList(query: AdminSubmissionListQuery): Promise<readonly Record<string, unknown>[]>;
    adminDetail(params: SubmissionIdParam): Promise<Record<string, unknown>>;
    detail(user: AuthUser, params: SubmissionIdParam): Promise<Record<string, unknown>>;
    appeal(user: AuthUser, params: SubmissionIdParam, body: AppealSubmissionDto): Promise<void>;
    approve(user: AuthUser, params: SubmissionIdParam, body: ReviewSubmissionDto): Promise<void>;
    reject(user: AuthUser, params: SubmissionIdParam, body: RejectSubmissionDto): Promise<void>;
    visibility(user: AuthUser, params: SubmissionIdParam, body: SetVisibilityDto): Promise<void>;
}
export {};
