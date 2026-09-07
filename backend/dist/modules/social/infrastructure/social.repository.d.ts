import { DatabaseService } from '../../../infrastructure/database/database.service.js';
export declare class SocialRepository {
    private readonly database;
    constructor(database: DatabaseService);
    getVote(userId: string, submissionId: string): Promise<import("pg").QueryResultRow>;
    vote(userId: string, submissionId: string, type: 'upvote' | 'downvote'): Promise<any>;
    removeVote(userId: string, submissionId: string): Promise<void>;
    listComments(submissionId: string, limit: number, offset: number): Promise<import("pg").QueryResultRow[]>;
    addComment(userId: string, submissionId: string, body: string, parentId?: string): Promise<any>;
    deleteComment(userId: string, role: string, commentId: string): Promise<void>;
    isFollowing(userId: string, targetId: string): Promise<boolean>;
    follow(userId: string, targetId: string): Promise<string>;
    unfollow(userId: string, targetId: string): Promise<void>;
    connections(userId: string, followers: boolean, limit: number, offset: number): Promise<import("pg").QueryResultRow[]>;
    followCounts(userId: string): Promise<{
        followers: number;
        following: number;
    }>;
    block(userId: string, targetId: string, reason: string): Promise<void>;
    unblock(userId: string, targetId: string): Promise<void>;
    blockedUsers(userId: string, limit: number, offset: number): Promise<import("pg").QueryResultRow[]>;
    report(userId: string, reportedType: string, reportedId: string, reason: string): Promise<string>;
    setSavedPost(userId: string, submissionId: string, saved: boolean): Promise<void>;
    isPostSaved(userId: string, submissionId: string): Promise<boolean>;
    setSavedQuest(userId: string, questId: string, saved: boolean): Promise<void>;
    isQuestSaved(userId: string, questId: string): Promise<boolean>;
    savedQuests(userId: string, limit: number, offset: number): Promise<import("pg").QueryResultRow[]>;
    savedPosts(userId: string, limit: number, offset: number): Promise<import("pg").QueryResultRow[]>;
    private reactionNotifications;
    private commentNotifications;
    private actorName;
    private notifyAdminsOfReport;
    private notification;
    private emitNotification;
    private emit;
}
