import { Body, Controller, HttpCode, Post } from '@nestjs/common';
import { ApiTags } from '@nestjs/swagger';
import { CurrentUser } from '../../../common/auth/current-user.decorator.js';
import type { AuthUser } from '../../../common/auth/auth-user.js';
import { AnalyticsService } from '../application/analytics.service.js';
import { AnalyticsBatchDto } from './analytics.dto.js';

/// Exposure telemetry ingest (#81 §28).
///
/// Authenticated, and events are always attributed to the caller — there is
/// no `userId` in the payload. A client cannot report on behalf of somebody
/// else, which matters because these counts are sold to businesses.
///
/// What it cannot do is make the numbers true. A phone reporting that it
/// drew a quest card is the only witness, so everything here is
/// client-attested and the business API labels it as such rather than
/// mixing it with server-authoritative completions.
@ApiTags('analytics')
@Controller({ path: 'analytics', version: '1' })
export class AnalyticsController {
  constructor(private readonly analytics: AnalyticsService) {}

  @Post('events')
  @HttpCode(202)
  record(@CurrentUser() user: AuthUser, @Body() body: AnalyticsBatchDto) {
    return this.analytics.record(user.id, body);
  }
}
