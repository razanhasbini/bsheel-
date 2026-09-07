import { SocialRepository } from '../infrastructure/social.repository.js';
export declare class SocialService {
    private readonly repository;
    constructor(repository: SocialRepository);
    getVote(userId: string, postId: string): Promise<import("pg").QueryResultRow>;
    vote(userId: string, postId: string, type: 'upvote' | 'downvote'): Promise<any>;
    removeVote(userId: string, postId: string): Promise<void>;
    comments(postId: string, limit: number, offset: number): Promise<import("pg").QueryResultRow[]>;
    addComment(userId: string, postId: string, body: string, parentId?: string): Promise<any>;
    deleteComment(userId: string, role: string, id: string): Promise<void>;
    isFollowing(userId: string, targetId: string): Promise<boolean>;
    follow(userId: string, targetId: string): Promise<string>;
    unfollow(userId: string, targetId: string): Promise<void>;
    connections(userId: string, followers: boolean, limit: number, offset: number): Promise<import("pg").QueryResultRow[]>;
    counts(userId: string): Promise<{
        followers: number;
        following: number;
    }>;
    block(userId: string, targetId: string, reason: string): Promise<void>;
    unblock(userId: string, targetId: string): Promise<void>;
    blockedUsers(userId: string, limit: number, offset: number): Promise<import("pg").QueryResultRow[]>;
    report(userId: string, type: string, id: string, reason: string): Promise<string>;
    savePost(userId: string, id: string, saved: boolean): Promise<void>;
    isPostSaved(userId: string, id: string): Promise<boolean>;
    saveQuest(userId: string, id: string, saved: boolean): Promise<void>;
    isQuestSaved(userId: string, id: string): Promise<boolean>;
    savedQuests(userId: string, limit: number, offset: number): Promise<import("pg").QueryResultRow[]>;
    savedPosts(userId: string, limit: number, offset: number): Promise<import("pg").QueryResultRow[]>;
}
