import type { AuthUser } from '../../../common/auth/auth-user.js';
import { LeaderboardService } from '../application/leaderboard.service.js';
import { LeaderboardQueryDto } from './leaderboard.dto.js';
export declare class LeaderboardController {
    private readonly service;
    constructor(service: LeaderboardService);
    list(user: AuthUser, query: LeaderboardQueryDto): Promise<import("pg").QueryResultRow[]>;
}
