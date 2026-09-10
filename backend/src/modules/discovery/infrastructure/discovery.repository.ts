import { Injectable } from '@nestjs/common';
import { DatabaseService } from '../../../infrastructure/database/database.service.js';
import { eligibilityFor } from '../../quests/domain/quest-eligibility.js';
import type { DiscoveryQuestCard, JourneyProgress } from '../domain/discovery.types.js';

/** The columns every card needs, plus its destination, as one reusable projection. */
const CARD_COLUMNS = `
  q.id, q.title, q.description, q.category, q.difficulty,
  q.xp_reward, q.duration_hours, q.is_hidden, q.editorial_tier,
  q.available_until, q.partner_id, q.sponsor_name,
  d.place_id, p.name AS place_name, p.city, p.country_code,
  c.name AS country_name, p.latitude, p.longitude, d.requires_verification,
  (SELECT count(*)::int FROM quest_chain_steps cs
     JOIN quest_chain_steps mine ON mine.chain_id = cs.chain_id
     WHERE mine.quest_id = q.id) AS chain_length`;

const CARD_JOINS = `
  FROM quests q
  LEFT JOIN quest_destinations d ON d.quest_id = q.id
  LEFT JOIN map_places p ON p.id = d.place_id
  LEFT JOIN map_countries c ON c.code = p.country_code`;

interface CardRow {
  id: string; title: string; description: string; category: string; difficulty: string;
  xp_reward: number; duration_hours: number; is_hidden: boolean; editorial_tier: string;
  available_until: Date | null; partner_id: string | null; sponsor_name: string | null;
  place_id: string | null; place_name: string | null; city: string | null;
  country_code: string | null; country_name: string | null;
  latitude: number | null; longitude: number | null; requires_verification: boolean | null;
  chain_length: number;
  completions?: number; net_score?: number;
}

/**
 * Reads for every discovery surface.
 *
 * Each query applies `eligibilityFor(channel, …)` rather than restating the
 * visibility rules, so a surface cannot forget the clause that withholds a
 * hidden quest or admits a festival that ended in March.
 */
@Injectable()
export class DiscoveryRepository {
  constructor(private readonly database: DatabaseService) {}

  /** Curated flagship quests, browsable from anywhere. One per country, so the shelf reads as a world. */
  async worthTheTrip(userId: string, limit: number): Promise<readonly DiscoveryQuestCard[]> {
    const result = await this.database.query<CardRow>(
      `SELECT DISTINCT ON (p.country_code) ${CARD_COLUMNS}
       ${CARD_JOINS}
       WHERE ${eligibilityFor('WORTH_THE_TRIP', { alias: 'q', userParam: '$1' })}
         AND d.place_id IS NOT NULL
       ORDER BY p.country_code, q.created_at DESC
       LIMIT $2`,
      [userId, limit],
    );
    return result.rows.map(toCard);
  }

  /**
   * Ranked by participation, not attention.
   *
   * The proposal is explicit that a completion mattering is not the same as
   * a completion being watched: what counts is votes, discussion, and above
   * all how many people took the quest on after seeing it. So the score is
   * driven by assignments-after-the-fact and net votes, decayed by age with
   * the same curve the feed already uses — otherwise one old quest owns the
   * shelf forever.
   */
  async trending(userId: string, limit: number): Promise<readonly DiscoveryQuestCard[]> {
    const result = await this.database.query<CardRow>(
      `WITH activity AS (
         SELECT uq.quest_id,
                count(*)::int AS completions,
                COALESCE(sum(s.net_score), 0)::int AS net_score,
                max(uq.assigned_at) AS last_activity
         FROM user_quests uq
         LEFT JOIN submissions s
           ON s.user_quest_id = uq.id AND s.deleted_at IS NULL
          AND s.visibility <> 'deleted' AND s.moderation_removed_at IS NULL
         WHERE uq.assigned_at > now() - interval '30 days'
         GROUP BY uq.quest_id
       )
       SELECT ${CARD_COLUMNS}, a.completions, a.net_score
       ${CARD_JOINS}
       JOIN activity a ON a.quest_id = q.id
       WHERE ${eligibilityFor('TRENDING', { alias: 'q', userParam: '$1' })}
       ORDER BY (a.completions * 3 + a.net_score)::double precision
                / power(GREATEST(EXTRACT(EPOCH FROM (now() - a.last_activity)) / 3600.0, 0) + 2.0, 1.5) DESC
       LIMIT $2`,
      [userId, limit],
    );
    return result.rows.map(toCard);
  }

  /** Event quests whose window is open now and closing soonest. */
  async limitedTime(userId: string, limit: number): Promise<readonly DiscoveryQuestCard[]> {
    const result = await this.database.query<CardRow>(
      `SELECT ${CARD_COLUMNS}
       ${CARD_JOINS}
       WHERE ${eligibilityFor('LIMITED_TIME', { alias: 'q', userParam: '$1' })}
         AND q.available_until IS NOT NULL
       ORDER BY q.available_until ASC
       LIMIT $2`,
      [userId, limit],
    );
    return result.rows.map(toCard);
  }

  /** Destination quests in a country, for EXPLORE_COUNTRY and NEAR_YOU alike. */
  async byCountry(userId: string, countryCode: string, limit: number): Promise<readonly DiscoveryQuestCard[]> {
    const result = await this.database.query<CardRow>(
      `SELECT ${CARD_COLUMNS}
       ${CARD_JOINS}
       WHERE ${eligibilityFor('COUNTRY', { alias: 'q', userParam: '$1' })}
         AND p.country_code = $2
       ORDER BY (q.editorial_tier = 'flagship') DESC, q.created_at DESC
       LIMIT $3`,
      [userId, countryCode, limit],
    );
    return result.rows.map(toCard);
  }

  /** Hidden quests this user has opened and not yet been shown. */
  async hiddenDiscovered(userId: string, limit: number): Promise<readonly DiscoveryQuestCard[]> {
    const result = await this.database.query<CardRow>(
      `SELECT ${CARD_COLUMNS}
       ${CARD_JOINS}
       JOIN user_quest_unlocks u ON u.quest_id = q.id AND u.user_id = $1
       WHERE ${eligibilityFor('HIDDEN_DISCOVERED', { alias: 'q', userParam: '$1' })}
         AND u.seen_at IS NULL
       ORDER BY u.unlocked_at DESC
       LIMIT $2`,
      [userId, limit],
    );
    return result.rows.map(toCard);
  }

  /** Sponsored placement, restricted to live campaigns and never demo partners outside dev. */
  async featuredPartner(userId: string, limit: number, allowDemo: boolean): Promise<readonly DiscoveryQuestCard[]> {
    const result = await this.database.query<CardRow>(
      `SELECT ${CARD_COLUMNS}
       ${CARD_JOINS}
       JOIN quest_partners pt ON pt.id = q.partner_id
       WHERE ${eligibilityFor('PARTNER', { alias: 'q', userParam: '$1' })}
         AND (pt.campaign_starts_at IS NULL OR pt.campaign_starts_at <= now())
         AND (pt.campaign_ends_at   IS NULL OR pt.campaign_ends_at   >  now())
         AND ($3::boolean OR NOT pt.is_demo)
       ORDER BY random()
       LIMIT $2`,
      [userId, limit, allowDemo],
    );
    return result.rows.map(toCard);
  }

  /**
   * Journeys the user has begun, plus their progress.
   *
   * Progress is derived from approved submissions rather than a counter, so
   * it cannot drift out of step with the quests that actually count toward it.
   */
  async journeysInProgress(userId: string, limit: number): Promise<readonly JourneyProgress[]> {
    const result = await this.database.query<{
      id: string; name: string; description: string;
      country_code: string | null; country_name: string | null;
      total_quests: number; completed_quests: number;
    }>(
      `SELECT col.id, col.name, col.description, col.country_code, c.name AS country_name,
              count(ci.quest_id)::int AS total_quests,
              count(*) FILTER (WHERE uq.status = 'approved')::int AS completed_quests
       FROM quest_collections col
       JOIN quest_collection_items ci ON ci.collection_id = col.id
       LEFT JOIN map_countries c ON c.code = col.country_code
       LEFT JOIN user_quests uq ON uq.quest_id = ci.quest_id AND uq.user_id = $1
       WHERE col.is_published
       GROUP BY col.id, col.name, col.description, col.country_code, c.name
       HAVING count(*) FILTER (WHERE uq.status = 'approved') > 0
          AND count(*) FILTER (WHERE uq.status = 'approved') < count(ci.quest_id)
       ORDER BY count(*) FILTER (WHERE uq.status = 'approved') DESC
       LIMIT $2`,
      [userId, limit],
    );
    return result.rows.map((row) => ({
      id: row.id,
      name: row.name,
      description: row.description,
      countryCode: row.country_code,
      countryName: row.country_name,
      totalQuests: row.total_quests,
      completedQuests: row.completed_quests,
    }));
  }

  /** The country a user most recently has verified presence in, if any. */
  async lastVerifiedCountry(userId: string): Promise<{ code: string; name: string } | null> {
    const result = await this.database.query<{ code: string; name: string }>(
      `SELECT c.code, c.name
       FROM map_location_evidence e
       JOIN map_places p ON p.id = e.place_id
       JOIN map_countries c ON c.code = p.country_code
       WHERE e.user_id = $1
         AND e.location_verified AND e.location_retrieved AND e.geofence_verified
       ORDER BY e.verified_at DESC
       LIMIT 1`,
      [userId],
    );
    return result.rows[0] ?? null;
  }

  /** A country with published destination content, for a first-time user's EXPLORE shelf. */
  async mostPopulatedCountry(): Promise<{ code: string; name: string } | null> {
    const result = await this.database.query<{ code: string; name: string }>(
      `SELECT c.code, c.name
       FROM map_countries c
       JOIN map_places p ON p.country_code = c.code AND p.is_published
       JOIN quest_destinations d ON d.place_id = p.id
       JOIN quests q ON q.id = d.quest_id AND q.is_active AND NOT q.is_hidden
       GROUP BY c.code, c.name
       ORDER BY count(*) DESC, c.name
       LIMIT 1`,
    );
    return result.rows[0] ?? null;
  }

  /** Marks unlocks as shown, so the discovery moment happens exactly once. */
  async markUnlocksSeen(userId: string, questIds: readonly string[]): Promise<void> {
    if (questIds.length === 0) return;
    await this.database.query(
      `UPDATE user_quest_unlocks SET seen_at = now()
       WHERE user_id = $1 AND quest_id = ANY($2::uuid[]) AND seen_at IS NULL`,
      [userId, questIds],
    );
  }
}

/** Turns a row into a card, deciding the mechanic badges once, server-side. */
function toCard(row: CardRow): DiscoveryQuestCard {
  const badges: string[] = [];
  if (row.is_hidden) badges.push('HIDDEN');
  if (row.available_until) badges.push('LIMITED');
  if (row.chain_length > 1) badges.push(`${row.chain_length} STAGES`);
  if (row.partner_id || row.sponsor_name) badges.push('PARTNER');
  if (row.editorial_tier === 'flagship') badges.push('WORTH THE TRIP');
  // The country reads as a badge on a travel shelf, which is the one place a
  // place name is a decision input rather than decoration.
  if (row.country_name) badges.push(row.country_name.toUpperCase());

  return {
    id: row.id,
    title: row.title,
    description: row.description,
    category: row.category,
    difficulty: row.difficulty,
    xpReward: row.xp_reward,
    durationHours: row.duration_hours,
    destination: row.place_id
      ? {
          placeId: row.place_id,
          placeName: row.place_name ?? '',
          city: row.city ?? '',
          countryCode: row.country_code ?? '',
          countryName: row.country_name ?? '',
          latitude: row.latitude ?? 0,
          longitude: row.longitude ?? 0,
          requiresVerification: row.requires_verification ?? false,
        }
      : null,
    badges,
    signal:
      row.completions === undefined
        ? null
        : { completions: row.completions, netScore: row.net_score ?? 0 },
  };
}
