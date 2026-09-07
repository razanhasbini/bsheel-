import { DatabaseService } from '../../../infrastructure/database/database.service.js';
import type { FeedQueryDto } from '../presentation/feed.dto.js';
export declare class FeedRepository {
    private readonly database;
    constructor(database: DatabaseService);
    list(viewerId: string, query: FeedQueryDto): Promise<readonly Record<string, unknown>[]>;
}
