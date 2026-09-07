import { Injectable } from '@nestjs/common';
import { LeaderboardRepository } from '../infrastructure/leaderboard.repository.js';

@Injectable()
export class LeaderboardService {
  constructor(private readonly repository: LeaderboardRepository) {}

  list(viewerId: string, scope: 'global' | 'following', limit: number, offset: number) {
    return this.repository.list(viewerId, scope, limit, offset);
  }
}
