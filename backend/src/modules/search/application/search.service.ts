import { Injectable } from '@nestjs/common';
import { SearchRepository } from '../infrastructure/search.repository.js';

@Injectable()
export class SearchService {
  constructor(private readonly repository: SearchRepository) {}

  search(viewerId: string, query: string, limit: number, offset: number) {
    return this.repository.search(viewerId, query, limit, offset);
  }
}
