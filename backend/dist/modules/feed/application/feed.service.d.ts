import { FeedRepository } from '../infrastructure/feed.repository.js';
import type { FeedQueryDto } from '../presentation/feed.dto.js';
export declare class FeedService {
    private readonly repository;
    constructor(repository: FeedRepository);
    list(viewerId: string, query: FeedQueryDto): Promise<readonly Record<string, unknown>[]>;
}
