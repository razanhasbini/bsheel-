import { Body, Controller, Get, Post, Query } from '@nestjs/common';
import { ApiOperation, ApiTags } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import { IsInt, IsOptional, Max, Min } from 'class-validator';
import { CurrentUser } from '../../../common/auth/current-user.decorator.js';
import type { AuthUser } from '../../../common/auth/auth-user.js';
import { Roles } from '../../../common/auth/roles.decorator.js';
import {
  QuestAuthoringRepository,
  type AuthoredQuest,
  type ChainOverview,
} from '../infrastructure/quest-authoring.repository.js';
import { AuthorChainDto, AuthorQuestDto } from './quest-authoring.dto.js';

export class CatalogueQuery {
  @IsOptional() @Type(() => Number) @IsInt() @Min(1) @Max(200) limit = 100;
  @IsOptional() @Type(() => Number) @IsInt() @Min(0) offset = 0;
}

/**
 * Authoring, for the admin panel.
 *
 * Separate from `QuestsController` because the two answer different
 * questions. That one serves players and carries the narrow create the bulk
 * importer uses; this one carries the full composable shape — hidden,
 * limited, destination, sponsored, chained — and writes several tables per
 * call.
 *
 * Every route is `super_admin`. Authoring decides what the whole player base
 * sees, which is not a moderation action.
 */
@ApiTags('quest-authoring')
@Controller({ path: 'quests/authoring', version: '1' })
export class QuestAuthoringController {
  constructor(private readonly repository: QuestAuthoringRepository) {}

  @Roles('super_admin')
  @Post('quests')
  @ApiOperation({ summary: 'Create one quest with every dimension: hidden, limited, destination, sponsored' })
  authorQuest(
    @CurrentUser() user: AuthUser,
    @Body() body: AuthorQuestDto,
  ): Promise<AuthoredQuest> {
    return this.repository.authorQuest(body, user.id);
  }

  @Roles('super_admin')
  @Post('chains')
  @ApiOperation({ summary: 'Create a whole multi-stage quest — every step and its unlock — in one transaction' })
  authorChain(
    @CurrentUser() user: AuthUser,
    @Body() body: AuthorChainDto,
  ): Promise<ChainOverview> {
    return this.repository.authorChain(body, user.id);
  }

  @Roles('super_admin')
  @Get('catalogue')
  @ApiOperation({ summary: 'Every quest with the dimensions that decide where it can appear' })
  catalogue(@Query() query: CatalogueQuery): Promise<readonly AuthoredQuest[]> {
    return this.repository.catalogue(query.limit, query.offset);
  }

  @Roles('super_admin')
  @Get('chains')
  @ApiOperation({ summary: 'Every chain, its steps, and how players are doing on each step' })
  chains(): Promise<readonly ChainOverview[]> {
    return this.repository.chains();
  }
}
