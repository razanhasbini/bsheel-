import { Module } from '@nestjs/common';
import { AnalyticsService } from './application/analytics.service.js';
import { AnalyticsEventsRepository } from './infrastructure/analytics-events.repository.js';
import { AnalyticsController } from './presentation/analytics.controller.js';

/// The event store (#81 §28): ingest here, aggregation read by the business
/// module, which owns the scoping rules.
@Module({
  controllers: [AnalyticsController],
  providers: [AnalyticsService, AnalyticsEventsRepository],
  exports: [AnalyticsEventsRepository],
})
export class AnalyticsModule {}
