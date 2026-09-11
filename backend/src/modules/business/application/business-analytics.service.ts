import { BadRequestException, Injectable } from '@nestjs/common';
import { BusinessAnalyticsRepository } from '../infrastructure/business-analytics.repository.js';
import { AnalyticsEventsRepository } from '../../analytics/infrastructure/analytics-events.repository.js';
import { conversion, type BusinessFunnel } from '../../analytics/domain/analytics-events.js';
import {
  MAX_DAILY_SPAN_DAYS,
  MIN_REPORTABLE_COHORT,
  resolveDailyWindow,
  type DailyWindowError,
} from '../domain/business-analytics.js';
import type {
  BusinessDailyQueryDto,
  BusinessProofQueryDto,
} from '../presentation/business-analytics.dto.js';

@Injectable()
export class BusinessAnalyticsService {
  constructor(
    private readonly analytics: BusinessAnalyticsRepository,
    private readonly events: AnalyticsEventsRepository,
  ) {}

  /// The dashboard's headline figures.
  ///
  /// `minReportableCohort` travels with the response so the client renders
  /// the same threshold the server enforced, instead of hard-coding a number
  /// that could drift from it.
  async summary(businessId: string) {
    const summary = await this.analytics.summary(businessId);
    return { ...summary, minReportableCohort: MIN_REPORTABLE_COHORT };
  }

  /// The completion series, over a preset window or an explicit range.
  ///
  /// The resolved window travels back in the response so the chart labels
  /// the dates the server actually drew rather than recomputing them and
  /// risking a one-day disagreement across a timezone boundary.
  async daily(businessId: string, query: BusinessDailyQueryDto) {
    const resolved = resolveDailyWindow(
      { days: query.days, from: query.from, to: query.to },
      new Date(),
    );
    if ('error' in resolved) {
      throw new BadRequestException({
        code: resolved.error,
        message: dailyWindowMessage(resolved.error),
      });
    }
    const points = await this.analytics.daily(businessId, resolved.window);
    return { window: resolved.window, points };
  }

  quests(businessId: string, limit: number, offset: number) {
    return this.analytics.quests(businessId, limit, offset);
  }

  places(businessId: string) {
    return this.analytics.places(businessId);
  }

  visitorOrigins(businessId: string) {
    return this.analytics.visitorOrigins(businessId);
  }

  /// The funnel (#81 §8), in two halves that are never merged.
  ///
  /// `exposure` is client-attested — a phone reported that it drew a card,
  /// and nothing server-side can confirm it. `participation` is what the
  /// server wrote while doing the work. Presenting them as one sequence of
  /// equally solid numbers is the mistake this shape exists to prevent, so
  /// they stay in separate objects all the way to the screen, and
  /// `exposure` is **null** rather than zeroed when no telemetry exists:
  /// "nothing was reported" is a statement about us, "nobody saw it" is a
  /// statement about the business.
  async funnel(businessId: string, query: BusinessDailyQueryDto) {
    const resolved = resolveDailyWindow(
      { days: query.days, from: query.from, to: query.to },
      new Date(),
    );
    if ('error' in resolved) {
      throw new BadRequestException({
        code: resolved.error,
        message: dailyWindowMessage(resolved.error),
      });
    }
    const [exposure, participation] = await Promise.all([
      this.events.exposureFor(businessId, resolved.window),
      this.events.participationFor(businessId, resolved.window),
    ]);
    const funnel: BusinessFunnel = { exposure, participation };
    return {
      window: resolved.window,
      ...funnel,
      /// Ratios only where both ends are known. Every one crossing the
      /// attested/authoritative boundary is null when exposure is absent,
      /// rather than inventing a denominator.
      conversion: {
        impressionToView: exposure
          ? conversion(exposure.impressions, exposure.detailViews)
          : null,
        viewToBsheeel: exposure
          ? conversion(exposure.detailViews, exposure.bsheeels)
          : null,
        bsheeelToActivation: exposure
          ? conversion(exposure.bsheeels, participation.activations)
          : null,
        activationToCompletion: conversion(
          participation.activations,
          participation.completions,
        ),
      },
      /// Said in the payload, not only in a doc, because a client that
      /// forgets it will draw one uniform funnel and a business will read
      /// impressions as solidly as completions.
      attestation: {
        exposure: 'client_reported',
        participation: 'server_authoritative',
      },
    };
  }

  /// Publicly published proof at this business's places, newest first.
  ///
  /// The cursor is two fields because the sort is two fields; accepting one
  /// without the other would produce a boundary the query cannot resolve,
  /// so it is rejected rather than silently ignored.
  async publicProof(businessId: string, query: BusinessProofQueryDto) {
    const hasBefore = query.beforeSubmittedAt !== undefined || query.beforeId !== undefined;
    if (hasBefore && (query.beforeSubmittedAt === undefined || query.beforeId === undefined)) {
      throw new BadRequestException({
        code: 'INCOMPLETE_CURSOR',
        message: 'beforeSubmittedAt and beforeId must be supplied together',
      });
    }
    const timestamp = query.beforeSubmittedAt ? new Date(query.beforeSubmittedAt) : undefined;
    if (timestamp && Number.isNaN(timestamp.getTime())) {
      throw new BadRequestException({
        code: 'INVALID_CURSOR',
        message: 'beforeSubmittedAt is not a valid timestamp',
      });
    }

    // One extra row decides whether there is another page, without a second
    // count query over the same joins.
    const rows = await this.analytics.publicProof(
      businessId,
      query.limit + 1,
      timestamp && query.beforeId
        ? { submittedAt: timestamp, id: query.beforeId }
        : undefined,
    );
    const page = rows.slice(0, query.limit);
    const last = page.at(-1);
    return {
      items: page,
      nextCursor:
        rows.length > query.limit && last
          ? { beforeSubmittedAt: last.submittedAt.toISOString(), beforeId: last.submissionId }
          : null,
    };
  }
}

/// Each reason has a different fix, so each gets its own sentence: a bare
/// "invalid range" leaves a caller guessing which of three things to change.
function dailyWindowMessage(error: DailyWindowError): string {
  switch (error) {
    case 'INVALID_DATE':
      return 'from and to must be calendar dates in YYYY-MM-DD form';
    case 'RANGE_REVERSED':
      return 'from must not be later than to';
    case 'RANGE_TOO_LONG':
      return `The range must span at most ${MAX_DAILY_SPAN_DAYS} days`;
  }
}
