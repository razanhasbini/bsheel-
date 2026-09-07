import { DatabaseService } from '../../../infrastructure/database/database.service.js';
export interface SearchResult {
    readonly users: readonly Record<string, unknown>[];
    readonly quests: readonly Record<string, unknown>[];
    readonly posts: readonly Record<string, unknown>[];
}
export declare class SearchRepository {
    private readonly database;
    constructor(database: DatabaseService);
    search(viewerId: string, query: string, limit: number, offset: number): Promise<SearchResult>;
}
