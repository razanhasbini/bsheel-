import { Module } from '@nestjs/common';
import { LeaderboardService } from './application/leaderboard.service.js';
import { LeaderboardRepository } from './infrastructure/leaderboard.repository.js';
import { LeaderboardController } from './presentation/leaderboard.controller.js';

@Module({ controllers: [LeaderboardController], providers: [LeaderboardService, LeaderboardRepository] })
export class LeaderboardModule {}
