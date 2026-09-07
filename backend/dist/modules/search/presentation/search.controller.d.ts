import type { AuthUser } from '../../../common/auth/auth-user.js';
import { SearchService } from '../application/search.service.js';
import { SearchQueryDto } from './search.dto.js';
export declare class SearchController {
    private readonly service;
    constructor(service: SearchService);
    search(user: AuthUser, query: SearchQueryDto): Promise<import("../infrastructure/search.repository.js").SearchResult>;
}
