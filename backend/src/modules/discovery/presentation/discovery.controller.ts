import { Controller, Get, Param, Query } from '@nestjs/common';
import { ApiOperation, ApiTags } from '@nestjs/swagger';
import { IsIn, IsInt, IsOptional, IsString, Matches, Max, MaxLength, Min } from 'class-validator';
import { Type } from 'class-transformer';
import { CurrentUser } from '../../../common/auth/current-user.decorator.js';
import type { AuthUser } from '../../../common/auth/auth-user.js';
import { HomeDiscoveryService } from '../application/home-discovery.service.js';
import { DiscoveryRepository } from '../infrastructure/discovery.repository.js';
import type { HomeModule } from '../domain/discovery.types.js';

export class QuestIdParam {
  @Matches(/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i)
  id!: string;
}

export class CountryParam {
  @Matches(/^[A-Z]{2}$/, { message: 'country must be a two-letter ISO code' })
  code!: string;
}

export class DiscoveryLimitQuery {
  @IsOptional() @Type(() => Number) @IsInt() @Min(1) @Max(30) limit?: number;
}

export class GenerateQuery {
  /** Which shelf's pool to reach into. */
  @IsIn(['WORTH_THE_TRIP', 'TRENDING', 'LIMITED_TIME', 'COUNTRY'])
  channel!: 'WORTH_THE_TRIP' | 'TRENDING' | 'LIMITED_TIME' | 'COUNTRY';

  @IsOptional() @Matches(/^[A-Z]{2}$/) country?: string;

  /**
   * What the shelf is already showing, so GENERATE reaches past it.
   * Comma-separated because it arrives on a query string; capped so a client
   * cannot turn an exclusion list into an unbounded IN clause.
   */
  @IsOptional() @IsString() @MaxLength(2000) exclude?: string;

  /** How many to offer. Three by default, matching the roll. */
  @IsOptional() @Type(() => Number) @IsInt() @Min(1) @Max(10) count?: number;
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

  @Get('countries')
  @ApiOperation({ summary: 'Countries that have published quests, for the EXPLORE picker' })
  countries() {
    return this.repository.countriesWithContent();
  }

  @Get('generate')
  @ApiOperation({ summary: "One more quest from a shelf's pool, past what is already shown" })
  generate(@CurrentUser() user: AuthUser, @Query() query: GenerateQuery) {
    // The exclusion list is what makes this feel like reaching further rather
    // than reshuffling: without it, a small catalogue hands back a card the
    // player is already looking at.
    const exclude = (query.exclude ?? '')
      .split(',')
      .map((id) => id.trim())
      .filter((id) => /^[0-9a-f-]{36}$/i.test(id))
      .slice(0, 50);
    const options = { countryCode: query.country, excludeIds: exclude };
    // The remaining count travels with the cards so the client can say
    // "that is everything" honestly rather than discovering it by asking
    // once more and getting nothing back.
    return Promise.all([
      this.repository.generateFor(user.id, query.channel, { ...options, count: query.count ?? 3 }),
      this.repository.remainingFor(user.id, query.channel, options),
    ]).then(([quests, remaining]) => ({ quests, remaining }));
  }

  @Get('quests/:id/journey')
  @ApiOperation({ summary: 'The milestone line for a multi-step quest, resolved for this viewer' })
  journey(@CurrentUser() user: AuthUser, @Param() param: QuestIdParam) {
    return this.repository.journeyFor(user.id, param.id);
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
