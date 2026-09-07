import type { AuthUser } from '../../../common/auth/auth-user.js';
import { FeedService } from '../application/feed.service.js';
import { FeedQueryDto } from './feed.dto.js';
export declare class FeedController {
    private readonly service;
    constructor(service: FeedService);
    list(user: AuthUser, query: FeedQueryDto): Promise<readonly Record<string, unknown>[]>;
}
