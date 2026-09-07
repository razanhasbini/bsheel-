import { CollabRepository } from '../infrastructure/collab.repository.js';
export declare class CollabService {
    private readonly repository;
    constructor(repository: CollabRepository);
    create(userId: string, userQuestId: string, mode: 'with' | 'versus'): Promise<{
        group_id: string;
        code: string;
        mode: "with" | "versus";
        expires_at: Date;
    }>;
    preview(code: string): Promise<import("pg").QueryResultRow>;
    join(userId: string, code: string): Promise<{
        group_id: string;
        user_quest_id: string;
        quest_id: string;
        expires_at: Date;
        mode: "with" | "versus";
    }>;
    status(userId: string, userQuestId: string): Promise<{
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
    abandon(userId: string, userQuestId: string): Promise<void>;
    vote(userId: string, groupId: string, submissionId: string): Promise<void>;
    unvote(userId: string, groupId: string, submissionId: string): Promise<void>;
}
