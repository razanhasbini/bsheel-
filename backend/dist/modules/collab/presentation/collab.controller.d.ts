import type { AuthUser } from '../../../common/auth/auth-user.js';
import { CollabService } from '../application/collab.service.js';
import { CollabAssignmentParam, CollabCodeParam, CollabVoteParam, CreateCollabGroupDto, JoinCollabGroupDto } from './collab.dto.js';
export declare class CollabController {
    private readonly service;
    constructor(service: CollabService);
    create(user: AuthUser, body: CreateCollabGroupDto): Promise<{
        group_id: string;
        code: string;
        mode: "with" | "versus";
        expires_at: Date;
    }>;
    preview(param: CollabCodeParam): Promise<import("pg").QueryResultRow>;
    join(user: AuthUser, body: JoinCollabGroupDto): Promise<{
        group_id: string;
        user_quest_id: string;
        quest_id: string;
        expires_at: Date;
        mode: "with" | "versus";
    }>;
    status(user: AuthUser, param: CollabAssignmentParam): Promise<{
        is_collab: boolean;
        group_id?: undefined;
        mode?: undefined;
        status?: undefined;
        code?: undefined;
        max_members?: undefined;
        expires_at?: undefined;
        members?: undefined;
    } | {
        is_collab: boolean;
        group_id: string;
        mode: "with" | "versus";
        status: string;
        code: string;
        max_members: number;
        expires_at: Date;
        members: import("pg").QueryResultRow[];
    }>;
    abandon(user: AuthUser, param: CollabAssignmentParam): Promise<void>;
    vote(user: AuthUser, param: CollabVoteParam): Promise<void>;
    unvote(user: AuthUser, param: CollabVoteParam): Promise<void>;
}
