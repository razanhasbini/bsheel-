import { Injectable } from '@nestjs/common';
import { DatabaseService } from '../../../infrastructure/database/database.service.js';
import {
  MIN_REPORTABLE_COHORT,
  completionRate,
  isCohortSuppressed,
  type BusinessAnalyticsSummary,
  type BusinessDailyPoint,
  type BusinessPlacePerformance,
  type BusinessPublicProof,
  type BusinessQuestPerformance,
  type BusinessVisitorOrigins,
} from '../domain/business-analytics.js';

/// Every submission that counts as activity at a business's places.
///
/// Two things are load-bearing:
///
/// The scope subquery reads `business_places` for the caller's business, so
/// the place set is derived from membership and can never be widened by a
/// request parameter. There is deliberately no variant of these queries
/// that takes a place id.
///
/// The exclusions match what the rest of the app treats as gone — soft
/// deleted, marked deleted, or removed by a moderator. Without them a
/// business's dashboard would keep counting proof that no longer exists
/// anywhere else in the product, and its totals would disagree with the
/// feed forever.
const ACTIVITY = `
  SELECT s.id, s.user_id, s.status::text AS status, s.submitted_at,
         s.xp_awarded_amount, s.show_in_feed, s.visibility::text AS visibility,
         d.place_id, d.quest_id, uq.id AS user_quest_id
  FROM business_places bp
  JOIN quest_destinations d ON d.place_id = bp.place_id
  JOIN user_quests uq ON uq.quest_id = d.quest_id
  JOIN submissions s ON s.user_quest_id = uq.id
  WHERE bp.business_id = $1
    AND s.deleted_at IS NULL
    AND s.visibility <> 'deleted'
    AND s.moderation_removed_at IS NULL`;

/// Quests offered at a business's places, whether or not anyone has started
/// one. `is_hidden` quests are included: they are real offers at the
/// business's own location, and hiding them from the owner's own dashboard
/// would make the quest count disagree with the place.
const OFFERED_QUESTS = `
  SELECT d.quest_id, d.place_id
  FROM business_places bp
  JOIN quest_destinations d ON d.place_id = bp.place_id
  WHERE bp.business_id = $1`;

@Injectable()
export class BusinessAnalyticsRepository {
  constructor(private readonly database: DatabaseService) {}

  async summary(businessId: string): Promise<BusinessAnalyticsSummary> {
    const result = await this.database.query<{
      places: number;
      completions: number;
      visitors: number;
      awaiting_review: number;
      rejected: number;
      saves: number;
      public_proof: number;
      xp_awarded: string | null;
      first_activity_at: Date | null;
      last_activity_at: Date | null;
    }>(
      `WITH activity AS (${ACTIVITY})
       SELECT
         (SELECT count(*) FROM business_places WHERE business_id = $1)::int AS places,
         (SELECT count(*) FROM saved_map_places sp
           JOIN business_places bp ON bp.place_id = sp.place_id
           WHERE bp.business_id = $1)::int AS saves,
         count(*) FILTER (WHERE status = 'approved')::int AS completions,
         count(DISTINCT user_id) FILTER (WHERE status = 'approved')::int AS visitors,
         count(*) FILTER (WHERE status = 'pending')::int AS awaiting_review,
         count(*) FILTER (WHERE status = 'rejected')::int AS rejected,
         count(*) FILTER (
           WHERE status = 'approved' AND show_in_feed AND visibility = 'visible'
         )::int AS public_proof,
         COALESCE(sum(xp_awarded_amount) FILTER (WHERE status = 'approved'), 0)::text AS xp_awarded,
         min(submitted_at) AS first_activity_at,
         max(submitted_at) AS last_activity_at
       FROM activity`,
      [businessId],
    );
    const row = result.rows[0];
    return {
      places: row.places,
      completions: row.completions,
      visitors: row.visitors,
      awaitingReview: row.awaiting_review,
      rejected: row.rejected,
      saves: row.saves,
      publicProof: row.public_proof,
      // sum() of a bigint comes back as a string; a dashboard total that
      // silently loses precision is worse than one that is plainly a number.
      xpAwarded: Number(row.xp_awarded ?? 0),
      firstActivityAt: row.first_activity_at,
      lastActivityAt: row.last_activity_at,
    };
  }

  /// Completions per day across the window, including days with none.
  ///
  /// generate_series is the point: grouping the submissions alone omits
  /// quiet days entirely, and a chart drawn from that connects last
  /// Tuesday to this Friday with a straight line that reads as steady
  /// traffic through a week when nobody came.
  async daily(
    businessId: string,
    window: { from: string; to: string },
  ): Promise<readonly BusinessDailyPoint[]> {
    const result = await this.database.query<{
      date: string;
      completions: number;
      visitors: number;
    }>(
      `WITH activity AS (${ACTIVITY}),
       window_days AS (
         SELECT generate_series($2::date, $3::date, interval '1 day')::date AS day
       )
       SELECT to_char(w.day, 'YYYY-MM-DD') AS date,
              count(a.id)::int AS completions,
              count(DISTINCT a.user_id)::int AS visitors
       FROM window_days w
       LEFT JOIN activity a
         ON (a.submitted_at AT TIME ZONE 'UTC')::date = w.day
        AND a.status = 'approved'
       GROUP BY w.day
       ORDER BY w.day ASC`,
      [businessId, window.from, window.to],
    );
    return result.rows;
  }

  /// Which quests attract people, and which of those people follow through.
  ///
  /// Starts come from `user_quests` rather than from submissions: someone
  /// who took the quest and never submitted is exactly the signal a business
  /// wants, and counting submissions would make follow-through look perfect
  /// by hiding everyone who gave up.
  async quests(
    businessId: string,
    limit: number,
    offset: number,
  ): Promise<readonly BusinessQuestPerformance[]> {
    const result = await this.database.query<{
      quest_id: string;
      title: string;
      category: string;
      difficulty: string;
      xp_reward: number;
      place_id: string;
      place_name: string;
      starts: number;
      completions: number;
      visitors: number;
      awaiting_review: number;
    }>(
      `WITH offered AS (${OFFERED_QUESTS}),
       starts AS (
         SELECT o.quest_id, count(*)::int AS starts
         FROM offered o JOIN user_quests uq ON uq.quest_id = o.quest_id
         GROUP BY o.quest_id
       ),
       outcomes AS (
         SELECT a.quest_id,
                count(*) FILTER (WHERE a.status = 'approved')::int AS completions,
                count(DISTINCT a.user_id) FILTER (WHERE a.status = 'approved')::int AS visitors,
                count(*) FILTER (WHERE a.status = 'pending')::int AS awaiting_review
         FROM (${ACTIVITY}) a
         GROUP BY a.quest_id
       )
       SELECT o.quest_id, q.title, q.category, q.difficulty, q.xp_reward,
              o.place_id, p.name AS place_name,
              COALESCE(st.starts, 0) AS starts,
              COALESCE(oc.completions, 0) AS completions,
              COALESCE(oc.visitors, 0) AS visitors,
              COALESCE(oc.awaiting_review, 0) AS awaiting_review
       FROM offered o
       JOIN quests q ON q.id = o.quest_id
       JOIN map_places p ON p.id = o.place_id
       LEFT JOIN starts st ON st.quest_id = o.quest_id
       LEFT JOIN outcomes oc ON oc.quest_id = o.quest_id
       -- Most-completed first, then most-started, so the ordering is stable
       -- and a quest nobody has touched sorts last rather than arbitrarily.
       ORDER BY COALESCE(oc.completions, 0) DESC,
                COALESCE(st.starts, 0) DESC,
                q.title ASC, o.quest_id ASC
       LIMIT $2 OFFSET $3`,
      [businessId, limit, offset],
    );
    return result.rows.map((row) => ({
      questId: row.quest_id,
      title: row.title,
      category: row.category,
      difficulty: row.difficulty,
      xpReward: row.xp_reward,
      placeId: row.place_id,
      placeName: row.place_name,
      starts: row.starts,
      completions: row.completions,
      completionRate: completionRate(row.starts, row.completions),
      awaitingReview: row.awaiting_review,
      cohortSuppressed: isCohortSuppressed(row.visitors),
    }));
  }

  async places(businessId: string): Promise<readonly BusinessPlacePerformance[]> {
    const result = await this.database.query<{
      place_id: string;
      name: string;
      city: string;
      country_code: string;
      is_published: boolean;
      quests: number;
      starts: number;
      completions: number;
      visitors: number;
      saves: number;
      last_activity_at: Date | null;
    }>(
      `WITH offered AS (${OFFERED_QUESTS}),
       activity AS (${ACTIVITY})
       SELECT bp.place_id, p.name, p.city, p.country_code, p.is_published,
              (SELECT count(*) FROM offered o WHERE o.place_id = bp.place_id)::int AS quests,
              (SELECT count(*) FROM offered o
                 JOIN user_quests uq ON uq.quest_id = o.quest_id
               WHERE o.place_id = bp.place_id)::int AS starts,
              count(a.id) FILTER (WHERE a.status = 'approved')::int AS completions,
              count(DISTINCT a.user_id) FILTER (WHERE a.status = 'approved')::int AS visitors,
              (SELECT count(*) FROM saved_map_places sp WHERE sp.place_id = bp.place_id)::int AS saves,
              max(a.submitted_at) AS last_activity_at
       FROM business_places bp
       JOIN map_places p ON p.id = bp.place_id
       LEFT JOIN activity a ON a.place_id = bp.place_id
       WHERE bp.business_id = $1
       GROUP BY bp.place_id, p.name, p.city, p.country_code, p.is_published
       ORDER BY count(a.id) FILTER (WHERE a.status = 'approved') DESC, p.name ASC`,
      [businessId],
    );
    return result.rows.map((row) => ({
      placeId: row.place_id,
      name: row.name,
      city: row.city,
      countryCode: row.country_code,
      isPublished: row.is_published,
      quests: row.quests,
      starts: row.starts,
      completions: row.completions,
      visitors: row.visitors,
      saves: row.saves,
      lastActivityAt: row.last_activity_at,
      cohortSuppressed: isCohortSuppressed(row.visitors),
    }));
  }

  /// Where this business's visitors say they are from.
  ///
  /// Two rules are enforced in the SQL rather than trusted to the caller:
  ///
  /// A visitor contributes to a country bucket only if they declared a
  /// country **and** set `analytics_consent_at`. Consent is not implied by
  /// having completed a quest at the place — the person came for the quest,
  /// not to be counted — so a declared country without consent stays
  /// undisclosed.
  ///
  /// Buckets below the reporting threshold are never returned as rows. A
  /// single-visitor country is a person: combined with one public feed post
  /// at the same place, "1 visitor from Qatar" names them. Those rows are
  /// collapsed into `suppressedCountries` / `suppressedVisitors` so the
  /// figures still reconcile against `disclosed` instead of quietly not
  /// adding up.
  async visitorOrigins(businessId: string): Promise<BusinessVisitorOrigins> {
    const result = await this.database.query<{
      country_code: string | null;
      visitors: number;
    }>(
      `WITH activity AS (${ACTIVITY}),
       visitors AS (
         -- One row per person, not per submission: someone who completed
         -- three quests here is one visitor from one country.
         SELECT DISTINCT a.user_id
         FROM activity a
         WHERE a.status = 'approved'
       )
       SELECT CASE
                WHEN p.analytics_consent_at IS NOT NULL THEN p.country_code
                ELSE NULL
              END AS country_code,
              count(*)::int AS visitors
       FROM visitors v
       JOIN profiles p ON p.id = v.user_id
       GROUP BY 1`,
      [businessId],
    );

    let visitors = 0;
    let disclosed = 0;
    const buckets: { countryCode: string; visitors: number }[] = [];
    for (const row of result.rows) {
      visitors += row.visitors;
      if (row.country_code === null) continue;
      disclosed += row.visitors;
      buckets.push({ countryCode: row.country_code, visitors: row.visitors });
    }

    const reportable = buckets.filter((bucket) => bucket.visitors >= MIN_REPORTABLE_COHORT);
    const suppressed = buckets.filter((bucket) => bucket.visitors < MIN_REPORTABLE_COHORT);
    return {
      visitors,
      disclosed,
      undisclosed: visitors - disclosed,
      countries: reportable
        .sort((left, right) =>
          right.visitors - left.visitors || left.countryCode.localeCompare(right.countryCode))
        .map((bucket) => ({
          countryCode: bucket.countryCode,
          visitors: bucket.visitors,
          // Share of what is known, so the percentages sum to 100 across
          // the disclosed population rather than to some fraction of it.
          shareOfDisclosed:
            disclosed > 0 ? Math.round((bucket.visitors / disclosed) * 1000) / 1000 : 0,
        })),
      suppressedCountries: suppressed.length,
      suppressedVisitors: suppressed.reduce((sum, bucket) => sum + bucket.visitors, 0),
    };
  }

  /// Proof the author published, at one of this business's places.
  ///
  /// The predicate is the feed's, exactly: approved, show_in_feed, visible,
  /// not deleted, not moderator-removed. It has to be, because `media_url`
  /// is an object key and POST /media/sign does not re-check who may see
  /// the submission — so a looser predicate here would hand a business the
  /// bytes of proof its author never published, and the author's name with
  /// it. `show_in_feed` is the author's own opt-in and is the reason this
  /// endpoint is defensible at all: everything it returns is already
  /// visible to every signed-in user on the feed.
  async publicProof(
    businessId: string,
    limit: number,
    before?: { submittedAt: Date; id: string },
  ): Promise<readonly BusinessPublicProof[]> {
    // Keyset pagination, so a new submission arriving mid-scroll cannot
    // shift a page boundary and duplicate or skip a row. No OFFSET: the
    // cursor is the position, and an offset on top of it would skip rows.
    //
    // The interpolated fragment is one of two literals chosen here, never
    // anything from the request; the cursor values themselves are bound.
    const cursor = before
      ? 'AND (s.submitted_at, s.id) < ($3::timestamptz, $4::uuid)'
      : '';
    const values: unknown[] = [businessId, limit];
    if (before) values.push(before.submittedAt, before.id);

    const result = await this.database.query<{
      submission_id: string;
      quest_id: string;
      quest_title: string;
      place_id: string;
      place_name: string;
      username: string;
      display_name: string;
      avatar_url: string | null;
      media_url: string;
      media_type: string;
      caption: string | null;
      net_score: string;
      submitted_at: Date;
    }>(
      `SELECT s.id AS submission_id, d.quest_id, q.title AS quest_title,
              d.place_id, p.name AS place_name,
              pr.username::text AS username, pr.display_name, pr.avatar_url,
              s.media_url, s.media_type::text AS media_type, s.caption,
              s.net_score::text AS net_score, s.submitted_at
       FROM business_places bp
       JOIN quest_destinations d ON d.place_id = bp.place_id
       JOIN user_quests uq ON uq.quest_id = d.quest_id
       JOIN submissions s ON s.user_quest_id = uq.id
       JOIN quests q ON q.id = d.quest_id
       JOIN map_places p ON p.id = d.place_id
       JOIN profiles pr ON pr.id = s.user_id
       WHERE bp.business_id = $1
         AND s.status = 'approved'
         AND s.show_in_feed
         AND s.visibility = 'visible'
         AND s.deleted_at IS NULL
         AND s.moderation_removed_at IS NULL
         ${cursor}
       ORDER BY s.submitted_at DESC, s.id DESC
       LIMIT $2`,
      values,
    );
    return result.rows.map((row) => ({
      submissionId: row.submission_id,
      questId: row.quest_id,
      questTitle: row.quest_title,
      placeId: row.place_id,
      placeName: row.place_name,
      username: row.username,
      displayName: row.display_name,
      avatarUrl: row.avatar_url,
      mediaUrl: row.media_url,
      mediaType: row.media_type,
      caption: row.caption,
      netScore: Number(row.net_score),
      submittedAt: row.submitted_at,
    }));
  }
}
