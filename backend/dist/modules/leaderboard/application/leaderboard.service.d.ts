import { LeaderboardRepository } from '../infrastructure/leaderboard.repository.js';
export declare class LeaderboardService {
    private readonly repository;
    constructor(repository: LeaderboardRepository);
    list(viewerId: string, scope: 'global' | 'following', limit: number, offset: number): Promise<import("pg").QueryResultRow[]>;
}
