import { Controller, Get, Query } from '@nestjs/common';
import { ApiTags } from '@nestjs/swagger';
import type { AuthUser } from '../../../common/auth/auth-user.js';
import { CurrentUser } from '../../../common/auth/current-user.decorator.js';
import { SearchService } from '../application/search.service.js';
import { SearchQueryDto } from './search.dto.js';

@ApiTags('search')
@Controller({ path: 'search', version: '1' })
export class SearchController {
  constructor(private readonly service: SearchService) {}

  @Get()
  search(@CurrentUser() user: AuthUser, @Query() query: SearchQueryDto) {
    return this.service.search(user.id, query.q, query.limit, query.offset);
  }
}
