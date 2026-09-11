import { Controller, Get, Param, Query, UseGuards } from '@nestjs/common';
import { ApiTags } from '@nestjs/swagger';
import { BusinessAccessGuard } from '../application/business-access.guard.js';
import { BusinessAnalyticsGuard } from '../application/business-analytics.guard.js';
import { BusinessAnalyticsService } from '../application/business-analytics.service.js';
import { BusinessIdDto } from './business.dto.js';
import {
  BusinessDailyQueryDto,
  BusinessProofQueryDto,
  BusinessQuestQueryDto,
} from './business-analytics.dto.js';

/// The business analytics dashboard (#50).
///
/// Every route is under :businessId and guarded by BusinessAccessGuard, so
/// the scope of every figure is the caller's own membership. There is
/// deliberately no place-id parameter anywhere here: the place set is
/// derived, never requested, which is what makes it impossible to ask about
/// somebody else's location.
@ApiTags('businesses')
// Order matters: access resolves the membership, entitlement reads it.
@UseGuards(BusinessAccessGuard, BusinessAnalyticsGuard)
@Controller({ path: 'businesses/:businessId/analytics', version: '1' })
export class BusinessAnalyticsController {
  constructor(private readonly analytics: BusinessAnalyticsService) {}

  @Get('summary')
  summary(@Param() params: BusinessIdDto) {
    return this.analytics.summary(params.businessId);
  }

  @Get('daily')
  daily(@Param() params: BusinessIdDto, @Query() query: BusinessDailyQueryDto) {
    return this.analytics.daily(params.businessId, query.days);
  }

  /// Which quests attract people, and which of those people follow through.
  @Get('quests')
  quests(@Param() params: BusinessIdDto, @Query() query: BusinessQuestQueryDto) {
    return this.analytics.quests(params.businessId, query.limit, query.offset);
  }

  @Get('places')
  places(@Param() params: BusinessIdDto) {
    return this.analytics.places(params.businessId);
  }

  /// Where visitors say they are from — aggregate, consented, and above the
  /// reporting threshold only.
  @Get('countries')
  countries(@Param() params: BusinessIdDto) {
    return this.analytics.visitorOrigins(params.businessId);
  }

  /// Proof the author published to the feed, at this business's places.
  @Get('proof')
  proof(@Param() params: BusinessIdDto, @Query() query: BusinessProofQueryDto) {
    return this.analytics.publicProof(params.businessId, query);
  }
}
