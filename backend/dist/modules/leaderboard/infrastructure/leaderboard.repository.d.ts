import { DatabaseService } from '../../../infrastructure/database/database.service.js';
export declare class LeaderboardRepository {
    private readonly database;
    constructor(database: DatabaseService);
    list(viewerId: string, scope: 'global' | 'following', limit: number, offset: number): Promise<import("pg").QueryResultRow[]>;
}
