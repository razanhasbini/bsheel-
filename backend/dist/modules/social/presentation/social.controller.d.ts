import type { AuthUser } from '../../../common/auth/auth-user.js';
import { SocialService } from '../application/social.service.js';
import { AddCommentDto, BlockUserDto, ReportContentDto, VoteDto } from './social.dto.js';
declare class IdParam {
    id: string;
}
declare class ListQuery {
    limit: number;
    offset: number;
}
declare class ConnectionQuery extends ListQuery {
    followers: boolean;
}
export declare class SocialController {
    private readonly service;
    constructor(service: SocialService);
    getVote(u: AuthUser, p: IdParam): Promise<import("pg").QueryResultRow>;
    vote(u: AuthUser, p: IdParam, b: VoteDto): Promise<any>;
    removeVote(u: AuthUser, p: IdParam): Promise<void>;
    comments(p: IdParam, q: ListQuery): Promise<import("pg").QueryResultRow[]>;
    addComment(u: AuthUser, p: IdParam, b: AddCommentDto): Promise<any>;
    deleteComment(u: AuthUser, p: IdParam): Promise<void>;
    isFollowing(u: AuthUser, p: IdParam): Promise<{
        following: boolean;
    }>;
    follow(u: AuthUser, p: IdParam): Promise<{
        id: string;
    }>;
    unfollow(u: AuthUser, p: IdParam): Promise<void>;
    connections(p: IdParam, q: ConnectionQuery): Promise<import("pg").QueryResultRow[]>;
    counts(p: IdParam): Promise<{
        followers: number;
        following: number;
    }>;
    block(u: AuthUser, p: IdParam, b: BlockUserDto): Promise<void>;
    unblock(u: AuthUser, p: IdParam): Promise<void>;
    blockedUsers(u: AuthUser, q: ListQuery): Promise<import("pg").QueryResultRow[]>;
    report(u: AuthUser, b: ReportContentDto): Promise<{
        id: string;
    }>;
    savedPosts(u: AuthUser, q: ListQuery): Promise<import("pg").QueryResultRow[]>;
    isPostSaved(u: AuthUser, p: IdParam): Promise<{
        saved: boolean;
    }>;
    savePost(u: AuthUser, p: IdParam): Promise<void>;
    unsavePost(u: AuthUser, p: IdParam): Promise<void>;
    savedQuests(u: AuthUser, q: ListQuery): Promise<import("pg").QueryResultRow[]>;
    isQuestSaved(u: AuthUser, p: IdParam): Promise<{
        saved: boolean;
    }>;
    saveQuest(u: AuthUser, p: IdParam): Promise<void>;
    unsaveQuest(u: AuthUser, p: IdParam): Promise<void>;
}
export {};
