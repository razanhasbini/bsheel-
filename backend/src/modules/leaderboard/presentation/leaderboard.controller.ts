import { Controller, Get, Query } from '@nestjs/common';
import { ApiTags } from '@nestjs/swagger';
import type { AuthUser } from '../../../common/auth/auth-user.js';
import { CurrentUser } from '../../../common/auth/current-user.decorator.js';
import { LeaderboardService } from '../application/leaderboard.service.js';
import { LeaderboardQueryDto } from './leaderboard.dto.js';

@ApiTags('leaderboard')
@Controller({ path: 'leaderboard', version: '1' })
export class LeaderboardController {
  constructor(private readonly service: LeaderboardService) {}

  @Get()
  list(@CurrentUser() user: AuthUser, @Query() query: LeaderboardQueryDto) {
    return this.service.list(user.id, query.scope, query.limit, query.offset);
  }
}
