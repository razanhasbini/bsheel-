import { Injectable } from '@nestjs/common';
import { DatabaseService } from '../../../infrastructure/database/database.service.js';
import type { AnalyticsEventType, AnalyticsSurface, ExposureCounts } from '../domain/analytics-events.js';

export interface RecordableEvent {
  readonly clientEventId: string;
  readonly eventType: AnalyticsEventType;
  readonly questId: string;
  readonly surface: AnalyticsSurface;
  readonly occurredAt: Date;
}

@Injectable()
export class AnalyticsEventsRepository {
  constructor(private readonly database: DatabaseService) {}

  /// Appends a batch, ignoring anything already recorded.
  ///
  /// One statement with an unnested array rather than a row per insert: a
  /// client flushes twenty impressions at once and twenty round trips for
  /// telemetry is a cost the user pays in battery for data nobody reads in
  /// real time.
  ///
  /// `ON CONFLICT DO NOTHING` against the per-user unique index is what
  /// makes a retry safe. A phone that loses its connection mid-flush
  /// resends the same client ids, and a resend must not inflate a
  /// business's impressions — which is the one number in this table nobody
  /// can audit from the server side.
  ///
  /// An unknown quest id is skipped rather than failing the batch: the
  /// quest may have been deleted between the impression and the flush, and
  /// losing one event beats losing the nineteen it travelled with.
  async append(userId: string, events: readonly RecordableEvent[]): Promise<number> {
    if (events.length === 0) return 0;
    const result = await this.database.query<{ id: string }>(
      `INSERT INTO analytics_events
         (client_event_id, user_id, event_type, quest_id, surface, occurred_at)
       SELECT e.client_event_id, $1, e.event_type, e.quest_id, e.surface, e.occurred_at
       FROM unnest(
              $2::uuid[], $3::text[], $4::uuid[], $5::text[], $6::timestamptz[]
            ) AS e(client_event_id, event_type, quest_id, surface, occurred_at)
       -- Skips an event whose quest has since been deleted, rather than
       -- failing the whole flush on the foreign key.
       WHERE EXISTS (SELECT 1 FROM quests q WHERE q.id = e.quest_id)
       ON CONFLICT (user_id, client_event_id) DO NOTHING
       RETURNING id`,
      [
        userId,
        events.map((event) => event.clientEventId),
        events.map((event) => event.eventType),
        events.map((event) => event.questId),
        events.map((event) => event.surface),
        events.map((event) => event.occurredAt),
      ],
    );
    return result.rows.length;
  }

  /// Exposure for one business's quests over a window.
  ///
  /// Scoped exactly as every other business query is: from
  /// `business_places` through `quest_destinations`, so the quest set is
  /// derived from membership and no parameter can widen it.
  ///
  /// Returns null when nothing has been reported at all. That is not the
  /// same as zero: "no telemetry was recorded" is a statement about us, and
  /// "nobody saw it" is a statement about the business — only one of which
  /// we are in a position to make.
  async exposureFor(
    businessId: string,
    window: { from: string; to: string },
  ): Promise<ExposureCounts | null> {
    const result = await this.database.query<{
      impressions: number;
      detail_views: number;
      bsheeels: number;
      shares: number;
      reach: number;
      total: number;
    }>(
      `WITH scoped AS (
         SELECT e.event_type, e.user_id
         FROM business_places bp
         JOIN quest_destinations d ON d.place_id = bp.place_id
         JOIN analytics_events e ON e.quest_id = d.quest_id
         WHERE bp.business_id = $1
           AND (e.occurred_at AT TIME ZONE 'UTC')::date BETWEEN $2::date AND $3::date
       )
       SELECT
         count(*) FILTER (WHERE event_type = 'quest_impression')::int AS impressions,
         count(*) FILTER (WHERE event_type = 'quest_detail_view')::int AS detail_views,
         count(*) FILTER (WHERE event_type = 'quest_bsheeel')::int AS bsheeels,
         count(*) FILTER (WHERE event_type = 'quest_share')::int AS shares,
         count(DISTINCT user_id)::int AS reach,
         count(*)::int AS total
       FROM scoped`,
      [businessId, window.from, window.to],
    );
    const row = result.rows[0];
    if (!row || row.total === 0) return null;
    return {
      impressions: row.impressions,
      detailViews: row.detail_views,
      bsheeels: row.bsheeels,
      shares: row.shares,
      reach: row.reach,
    };
  }

  /// Server-authoritative participation over the same window, from the
  /// tables that own each fact rather than from this one.
  async participationFor(
    businessId: string,
    window: { from: string; to: string },
  ): Promise<{ activations: number; completions: number; visitors: number }> {
    const result = await this.database.query<{
      activations: number;
      completions: number;
      visitors: number;
    }>(
      `WITH scope AS (
         SELECT d.quest_id
         FROM business_places bp
         JOIN quest_destinations d ON d.place_id = bp.place_id
         WHERE bp.business_id = $1
       )
       SELECT
         (SELECT count(*)::int FROM scope s
            JOIN user_quests uq ON uq.quest_id = s.quest_id
          WHERE (uq.assigned_at AT TIME ZONE 'UTC')::date BETWEEN $2::date AND $3::date
         ) AS activations,
         (SELECT count(*)::int FROM scope s
            JOIN user_quests uq ON uq.quest_id = s.quest_id
            JOIN submissions sub ON sub.user_quest_id = uq.id
          WHERE sub.status = 'approved'
            AND sub.deleted_at IS NULL
            AND sub.visibility <> 'deleted'
            AND sub.moderation_removed_at IS NULL
            AND (sub.submitted_at AT TIME ZONE 'UTC')::date BETWEEN $2::date AND $3::date
         ) AS completions,
         (SELECT count(DISTINCT sub.user_id)::int FROM scope s
            JOIN user_quests uq ON uq.quest_id = s.quest_id
            JOIN submissions sub ON sub.user_quest_id = uq.id
          WHERE sub.status = 'approved'
            AND sub.deleted_at IS NULL
            AND sub.visibility <> 'deleted'
            AND sub.moderation_removed_at IS NULL
            AND (sub.submitted_at AT TIME ZONE 'UTC')::date BETWEEN $2::date AND $3::date
         ) AS visitors`,
      [businessId, window.from, window.to],
    );
    return result.rows[0];
  }
}
