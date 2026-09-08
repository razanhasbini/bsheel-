import { Body, Controller, Get, Param, Patch, Post, Query } from '@nestjs/common';
import { Type } from 'class-transformer';
import { IsInt, IsOptional, Length, Matches, Max, Min, IsUUID } from 'class-validator';
import { ApiTags } from '@nestjs/swagger';
import { CurrentUser } from '../../../common/auth/current-user.decorator.js';
import type { AuthUser } from '../../../common/auth/auth-user.js';
import { ProfilesService } from '../application/profiles.service.js';
import { AnalyticsConsentDto, UpdateProfileDto } from './profile.dto.js';

/// Validates `:id` as a UUID before it reaches a uuid-typed query.
///
/// An unvalidated id reached Postgres and raised 22P02, which surfaced as a
/// 500 rather than a 400 — a client's bad id should not read as a server
/// fault, in the response or in the logs.
class ProfileIdParam {
  @IsUUID() id!: string;
}

/// Validates `:username`. Not a UUID, so it is bounded by the same rule the
/// registration DTO enforces rather than passed through unchecked.
class ProfileUsernameParam {
  @Length(3, 30)
  @Matches(/^[A-Za-z0-9_]+$/)
  username!: string;
}

class ProfileListQuery {
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(200)
  limit = 200;
}

@ApiTags('profiles')
@Controller({ path: 'profiles', version: '1' })
export class ProfilesController {
  constructor(private readonly service: ProfilesService) {}

  @Get('me/xp-stats')
  xpStats(@CurrentUser() user: AuthUser) { return this.service.xpStats(user.id); }

  @Get('me')
  me(@CurrentUser() user: AuthUser) { return this.service.ownProfile(user.id); }

  @Patch('me')
  update(@CurrentUser() user: AuthUser, @Body() body: UpdateProfileDto) { return this.service.update(user.id, body); }

  @Patch('me/analytics-consent')
  async analyticsConsent(@CurrentUser() user: AuthUser, @Body() body: AnalyticsConsentDto) {
    return { analytics_consent_at: await this.service.setAnalyticsConsent(user.id, body.consented) };
  }

  @Post('me/accept-terms')
  async acceptTerms(@CurrentUser() user: AuthUser) {
    return { accepted_terms_at: await this.service.acceptTerms(user.id) };
  }

  @Get('me/account-status')
  accountStatus(@CurrentUser() user: AuthUser) { return this.service.accountStatus(user.id); }

  @Get()
  list(@Query() query: ProfileListQuery) { return this.service.list(query.limit); }

  @Get('by-username/:username')
  getByUsername(@Param() param: ProfileUsernameParam) {
    return this.service.publicProfileByUsername(param.username);
  }

  @Get(':id')
  get(@Param() param: ProfileIdParam) { return this.service.publicProfile(param.id); }
}
