import { Injectable } from '@nestjs/common';
import { FeedRepository } from '../infrastructure/feed.repository.js';
import type { FeedQueryDto } from '../presentation/feed.dto.js';

@Injectable()
export class FeedService {
  constructor(private readonly repository: FeedRepository) {}
  list(viewerId: string, query: FeedQueryDto) { return this.repository.list(viewerId, query); }
}

