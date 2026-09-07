import { Controller, Get, Query } from '@nestjs/common';
import { ApiTags } from '@nestjs/swagger';
import { CurrentUser } from '../../../common/auth/current-user.decorator.js';
import type { AuthUser } from '../../../common/auth/auth-user.js';
import { FeedService } from '../application/feed.service.js';
import { FeedQueryDto } from './feed.dto.js';

@ApiTags('feed')
@Controller({ path: 'feed', version: '1' })
export class FeedController {
  constructor(private readonly service: FeedService) {}
  @Get()
  list(@CurrentUser() user: AuthUser, @Query() query: FeedQueryDto) { return this.service.list(user.id, query); }
}

