import { Injectable } from '@nestjs/common';
import { DatabaseService } from '../../../infrastructure/database/database.service.js';
import type {
  AnalyticsEventType,
  AnalyticsSurface,
  ExposureCounts,
  PostAttribution,
} from '../domain/analytics-events.js';

export interface RecordableEvent {
  readonly clientEventId: string;
  readonly eventType: AnalyticsEventType;
  readonly questId: string;
  readonly surface: AnalyticsSurface;
  readonly occurredAt: Date;
  /// The post the event was raised from, if any (0049).
  readonly sourceSubmissionId: string | null;
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
         (client_event_id, user_id, event_type, quest_id, surface, occurred_at, source_submission_id)
       SELECT e.client_event_id, $1, e.event_type, e.quest_id, e.surface, e.occurred_at,
              -- A source post that no longer exists is dropped from the
              -- event, not the event from the batch: the BSHEEEL still
              -- happened and still counts for the quest.
              CASE WHEN EXISTS (SELECT 1 FROM submissions sp WHERE sp.id = e.source_submission_id)
                   THEN e.source_submission_id END
       FROM unnest(
              $2::uuid[], $3::text[], $4::uuid[], $5::text[], $6::timestamptz[], $7::uuid[]
            ) AS e(client_event_id, event_type, quest_id, surface, occurred_at, source_submission_id)
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
        events.map((event) => event.sourceSubmissionId),
      ],
    );
    return result.rows.length;
  }

  /// Who wrote a post, or null when there is no such live post.
  async postAuthor(submissionId: string): Promise<string | null> {
    const result = await this.database.query<{ user_id: string }>(
      'SELECT user_id FROM submissions WHERE id = $1 AND deleted_at IS NULL',
      [submissionId],
    );
    return result.rows[0]?.user_id ?? null;
  }

  /// Everything one post led to (0049).
  ///
  /// Events raised from the post are read directly. Activations and
  /// completions are joined: a person who pressed BSHEEEL *from this post*,
  /// then was assigned the same quest at or after that press, then had a
  /// submission for it approved. The author's own events are excluded — a
  /// post cannot inspire its author. Fourteen days between the press and
  /// the assignment is generous on purpose: the roll is random and the
  /// saved quest may take a while to come up, and a stricter window would
  /// systematically under-credit the posts that made people wait for it.
  async attributionFor(submissionId: string): Promise<PostAttribution | null> {
    const result = await this.database.query<{
      exists: boolean; detail_views: number; viewers: number; bsheeels: number;
      shares: number; activations: number; completions: number;
    }>(
      `WITH src AS (
         SELECT s.id, s.user_id AS author_id, uq.quest_id
         FROM submissions s JOIN user_quests uq ON uq.id = s.user_quest_id
         WHERE s.id = $1
       ), raised AS (
         SELECT e.user_id, e.event_type, e.occurred_at
         FROM analytics_events e JOIN src ON e.source_submission_id = src.id
         WHERE e.user_id <> src.author_id
       ), pressed AS (
         SELECT user_id, min(occurred_at) AS first_press FROM raised
         WHERE event_type = 'quest_bsheeel' GROUP BY user_id
       ), activated AS (
         SELECT DISTINCT p.user_id, uq.id AS user_quest_id
         FROM pressed p JOIN src ON true
         JOIN user_quests uq ON uq.user_id = p.user_id AND uq.quest_id = src.quest_id
                            AND uq.assigned_at >= p.first_press
                            AND uq.assigned_at < p.first_press + interval '14 days'
       )
       SELECT
         EXISTS (SELECT 1 FROM src) AS exists,
         (SELECT count(*)::int FROM raised WHERE event_type = 'quest_detail_view') AS detail_views,
         (SELECT count(DISTINCT user_id)::int FROM raised
           WHERE event_type IN ('quest_detail_view', 'quest_impression')) AS viewers,
         (SELECT count(*)::int FROM pressed) AS bsheeels,
         (SELECT count(*)::int FROM raised WHERE event_type = 'quest_share') AS shares,
         (SELECT count(DISTINCT user_id)::int FROM activated) AS activations,
         (SELECT count(DISTINCT a.user_id)::int FROM activated a
           JOIN submissions s2 ON s2.user_quest_id = a.user_quest_id
          WHERE s2.status = 'approved' AND s2.deleted_at IS NULL) AS completions`,
      [submissionId],
    );
    const row = result.rows[0];
    if (!row?.exists) return null;
    return {
      submissionId,
      detailViews: row.detail_views,
      viewers: row.viewers,
      bsheeels: row.bsheeels,
      shares: row.shares,
      activations: row.activations,
      completions: row.completions,
    };
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
