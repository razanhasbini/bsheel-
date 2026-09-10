import { Controller, Get, Param, Query } from '@nestjs/common';
import { ApiOperation, ApiTags } from '@nestjs/swagger';
import { IsInt, IsOptional, Matches, Max, Min } from 'class-validator';
import { Type } from 'class-transformer';
import { CurrentUser } from '../../../common/auth/current-user.decorator.js';
import type { AuthUser } from '../../../common/auth/auth-user.js';
import { HomeDiscoveryService } from '../application/home-discovery.service.js';
import { DiscoveryRepository } from '../infrastructure/discovery.repository.js';
import type { HomeModule } from '../domain/discovery.types.js';

export class CountryParam {
  @Matches(/^[A-Z]{2}$/, { message: 'country must be a two-letter ISO code' })
  code!: string;
}

export class DiscoveryLimitQuery {
  @IsOptional() @Type(() => Number) @IsInt() @Min(1) @Max(30) limit?: number;
}

/**
 * Discovery surfaces. One source of truth for Home, the map and country
 * pages, so a quest cannot be visible on one and withheld on another.
 *
 * Everything returned is already eligible for the caller: hidden quests they
 * have opened, events still running, campaigns still live. The client renders
 * what it is given and never re-decides.
 */
@ApiTags('discovery')
@Controller({ path: 'discovery', version: '1' })
export class DiscoveryController {
  constructor(
    private readonly home: HomeDiscoveryService,
    private readonly repository: DiscoveryRepository,
  ) {}

  @Get('home')
  @ApiOperation({ summary: 'The discovery modules Home should render, already filtered and ranked' })
  homeModules(@CurrentUser() user: AuthUser): Promise<{ modules: readonly HomeModule[] }> {
    return this.home.modulesFor(user.id).then((modules) => ({ modules }));
  }

  @Get('worth-the-trip')
  @ApiOperation({ summary: 'Flagship destination quests, browsable from anywhere' })
  worthTheTrip(@CurrentUser() user: AuthUser, @Query() query: DiscoveryLimitQuery) {
    return this.repository.worthTheTrip(user.id, query.limit ?? 10);
  }

  @Get('trending')
  @ApiOperation({ summary: 'Quests ranked by participation — activations and votes, decayed by age' })
  trending(@CurrentUser() user: AuthUser, @Query() query: DiscoveryLimitQuery) {
    return this.repository.trending(user.id, query.limit ?? 10);
  }

  @Get('countries/:code')
  @ApiOperation({ summary: 'Destination quests in one country. Presence is not required to browse.' })
  byCountry(
    @CurrentUser() user: AuthUser,
    @Param() param: CountryParam,
    @Query() query: DiscoveryLimitQuery,
  ) {
    return this.repository.byCountry(user.id, param.code, query.limit ?? 20);
  }
}
