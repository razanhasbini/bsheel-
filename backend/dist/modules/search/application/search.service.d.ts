import { SearchRepository } from '../infrastructure/search.repository.js';
export declare class SearchService {
    private readonly repository;
    constructor(repository: SearchRepository);
    search(viewerId: string, query: string, limit: number, offset: number): Promise<import("../infrastructure/search.repository.js").SearchResult>;
}
