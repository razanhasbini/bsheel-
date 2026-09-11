import { Injectable } from '@nestjs/common';
import { DatabaseService } from '../../../infrastructure/database/database.service.js';
import { eligibilityFor } from '../../quests/domain/quest-eligibility.js';
import type { DiscoveryQuestCard, JourneyProgress } from '../domain/discovery.types.js';
import type { QuestJourney } from '../domain/quest-journey.types.js';

/** Pools GENERATE can reach into, one per shelf that offers the button. */
export type GenerateChannel =
  | 'WORTH_THE_TRIP' | 'TRENDING' | 'LIMITED_TIME' | 'COUNTRY' | 'MULTI_STAGE';

/**
 * MULTI_STAGE reaches a pool the other channels do not: the opening step of
 * a chain. That needs two extra joins and a step filter, and both the
 * generate query and the remaining-count query have to apply them or the
 * count promises quests the generator cannot produce.
 */
const MULTI_STAGE_JOINS = `
  JOIN quest_chain_steps cs ON cs.quest_id = q.id AND cs.step_order = 1`;

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
  /**
   * The opening step of every multi-stage chain this user has not begun.
   *
   * Multi-stage quests were reachable only through CONTINUE_JOURNEY, which
   * by definition lists chains already under way — so a new account could
   * never see one, and the mechanic did not exist as far as the app was
   * concerned. This is the way in.
   *
   * One row per chain (`DISTINCT ON`), always step 1: showing step 3 of a
   * chain nobody has started would be an invitation the eligibility gate
   * refuses. Chains with any approved step for this viewer are excluded
   * here rather than deduplicated later, so the two shelves can never show
   * the same journey twice.
   */
  async chainOpeners(userId: string, limit: number): Promise<readonly DiscoveryQuestCard[]> {
    const result = await this.database.query<CardRow>(
      `SELECT DISTINCT ON (cs.chain_id) ${CARD_COLUMNS}
       ${CARD_JOINS}
       JOIN quest_chain_steps cs ON cs.quest_id = q.id
       JOIN quest_chains ch ON ch.id = cs.chain_id
       WHERE ${eligibilityFor('MULTI_STAGE', { alias: 'q', userParam: '$1' })}
         AND cs.step_order = 1
         AND NOT EXISTS (
           SELECT 1
           FROM quest_chain_steps started
           JOIN user_quests uq ON uq.quest_id = started.quest_id
           WHERE started.chain_id = cs.chain_id
             AND uq.user_id = $1
             AND uq.status IN ('assigned', 'submitted', 'approved')
         )
       ORDER BY cs.chain_id, q.created_at DESC
       LIMIT $2`,
      [userId, limit],
    );
    return result.rows.map(toCard);
  }

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
      kind: 'collection' as const,
      id: row.id,
      name: row.name,
      description: row.description,
      countryCode: row.country_code,
      countryName: row.country_name,
      totalQuests: row.total_quests,
      completedQuests: row.completed_quests,
    }));
  }

  /**
   * Live chain runs, as journey cards.
   *
   * Chains and collections stay separate tables — ordered progression and
   * themed grouping are genuinely different things — and are merged only
   * here, in presentation, so Home can say "continue your journey" about
   * both without the database pretending they are one concept.
   */
  async chainRunsInProgress(userId: string, limit: number): Promise<readonly JourneyProgress[]> {
    const result = await this.database.query<{
      run_id: string; chain_id: string; name: string; description: string;
      total_steps: number; completed_steps: number;
      next_title: string | null; next_hidden: boolean | null;
      can_continue: boolean; unseen: boolean;
    }>(
      `SELECT r.id AS run_id, r.chain_id, ch.name, ch.description,
              (SELECT count(*)::int FROM quest_chain_steps cs WHERE cs.chain_id = r.chain_id) AS total_steps,
              (SELECT count(*)::int FROM quest_chain_steps cs
                 JOIN user_quests uq ON uq.quest_id = cs.quest_id AND uq.status = 'approved'
                WHERE cs.chain_id = r.chain_id
                  AND (uq.user_id = r.owner_user_id OR EXISTS (
                    SELECT 1 FROM quest_chain_run_participants p
                    WHERE p.chain_run_id = r.id AND p.user_id = uq.user_id))) AS completed_steps,
              mine.title AS next_title, mine.is_hidden AS next_hidden,
              (mine.quest_id IS NOT NULL) AS can_continue,
              COALESCE(mine.unseen, false) AS unseen
       FROM quest_chain_runs r
       JOIN quest_chains ch ON ch.id = r.chain_id
       LEFT JOIN LATERAL (
         SELECT u.quest_id, q.title, q.is_hidden, (u.seen_at IS NULL) AS unseen
         FROM journey_stage_unlocks u
         JOIN quests q ON q.id = u.quest_id
         WHERE u.chain_run_id = r.id AND u.target_user_id = $1
           AND NOT EXISTS (
             SELECT 1 FROM user_quests uq
             WHERE uq.quest_id = u.quest_id AND uq.user_id = $1
               AND uq.status IN ('assigned', 'submitted', 'approved')
           )
         ORDER BY u.step_order LIMIT 1
       ) mine ON true
       WHERE r.status = 'active'
         AND (r.owner_user_id = $1 OR EXISTS (
           SELECT 1 FROM quest_chain_run_participants p
           WHERE p.chain_run_id = r.id AND p.user_id = $1))
       ORDER BY r.started_at DESC NULLS LAST
       LIMIT $2`,
      [userId, limit],
    );
    return result.rows.map((row) => ({
      kind: 'chain' as const,
      id: row.chain_id,
      runId: row.run_id,
      name: row.name,
      description: row.description,
      countryCode: null,
      countryName: null,
      totalQuests: row.total_steps,
      completedQuests: row.completed_steps,
      canContinue: row.can_continue,
      // A hidden checkpoint keeps its name even on the card that offers it —
      // the tease is the point, and Home is not a place to leak it.
      nextCheckpointName: row.next_hidden ? null : row.next_title,
      hasUnseenUnlock: row.unseen && row.can_continue,
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

  /** The country the user's verified phone belongs to, if we map its code. */
  async signupCountry(userId: string): Promise<{ code: string; name: string } | null> {
    const result = await this.database.query<{ code: string; name: string }>(
      `SELECT c.code, c.name
       FROM users u JOIN map_countries c ON c.code = u.signup_country_code
       WHERE u.id = $1`,
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


  /**
   * The chain a quest belongs to, resolved into milestones for this viewer.
   *
   * Returns null when the quest is not part of one, which is most of them —
   * the caller renders nothing rather than an empty timeline.
   *
   * The step states are computed here, in one query, because they depend on
   * approval history the client cannot see. On a `group` chain the approval
   * may belong to any member of the collab group, which is exactly the case
   * that used to be got wrong.
   */
  async journeyFor(userId: string, questId: string): Promise<QuestJourney | null> {
    const chain = await this.database.query<{
      chain_id: string; name: string; description: string;
      mode: 'solo' | 'group'; completion_rule: 'sequential' | 'all_steps_any_order';
    }>(
      `SELECT ch.id AS chain_id, ch.name, ch.description, ch.mode, ch.completion_rule
       FROM quest_chain_steps cs
       JOIN quest_chains ch ON ch.id = cs.chain_id
       WHERE cs.quest_id = $1 AND ch.is_active`,
      [questId],
    );
    const head = chain.rows[0];
    if (!head) return null;

    const steps = await this.database.query<{
      quest_id: string; step_order: number; title: string; xp_reward: number;
      is_hidden: boolean; place_name: string | null; country_name: string | null;
      requires_verification: boolean | null;
      approved: boolean; in_review: boolean; completed_by: string | null;
    }>(
      `SELECT cs.quest_id, cs.step_order, q.title, q.xp_reward, q.is_hidden,
              p.name AS place_name, c.name AS country_name, d.requires_verification,
              EXISTS (
                SELECT 1 FROM user_quests uq
                WHERE uq.quest_id = cs.quest_id AND uq.status = 'approved'
                  AND ($2 = 'solo' AND uq.user_id = $1
                    OR $2 = 'group' AND EXISTS (
                      SELECT 1 FROM collab_group_members m
                      WHERE m.group_id = $3 AND m.user_id = uq.user_id))
              ) AS approved,
              EXISTS (
                SELECT 1 FROM user_quests uq
                WHERE uq.quest_id = cs.quest_id AND uq.status = 'submitted'
                  AND ($2 = 'solo' AND uq.user_id = $1
                    OR $2 = 'group' AND EXISTS (
                      SELECT 1 FROM collab_group_members m
                      WHERE m.group_id = $3 AND m.user_id = uq.user_id))
              ) AS in_review,
              (SELECT pr.username FROM user_quests uq
                 JOIN profiles pr ON pr.id = uq.user_id
                 WHERE uq.quest_id = cs.quest_id AND uq.status = 'approved'
                 ORDER BY uq.completed_at NULLS LAST LIMIT 1) AS completed_by
       FROM quest_chain_steps cs
       JOIN quests q ON q.id = cs.quest_id
       LEFT JOIN quest_destinations d ON d.quest_id = q.id
       LEFT JOIN map_places p ON p.id = d.place_id
       LEFT JOIN map_countries c ON c.code = p.country_code
       WHERE cs.chain_id = $4
       ORDER BY cs.step_order`,
      [userId, head.mode, await this.chainGroupId(head.chain_id), head.chain_id],
    );

    // At most one step is CURRENT on a sequential chain, and a step awaiting
    // a decision CLAIMS that position rather than passing it along.
    //
    // Skipping over an in-review step marked the next one CURRENT — "YOU ARE
    // HERE" — while `chainStepUnlocked` refused to assign it, because the
    // gate needs the previous step APPROVED and a pending submission is not
    // an approval. The line promised a step the API then rejected with
    // QUEST_STEP_LOCKED, which is the precise failure this whole engine
    // exists to prevent. While a decision is outstanding there is nowhere
    // else to be, so nothing after it is current.
    //
    // An any-order chain has no such position at all — every unfinished step
    // is available at once, which is what makes a cross-country challenge
    // work.
    let currentAssigned = head.completion_rule === 'all_steps_any_order';
    const milestones = steps.rows.map((row) => {
      let state: QuestJourney['milestones'][number]['state'];
      if (row.approved) state = 'COMPLETE';
      else if (row.in_review) { state = 'IN_REVIEW'; currentAssigned = true; }
      else if (head.completion_rule === 'all_steps_any_order') state = 'CURRENT';
      else if (!currentAssigned) { state = 'CURRENT'; currentAssigned = true; }
      else state = 'LOCKED';

      return {
        questId: row.quest_id,
        stepOrder: row.step_order,
        state,
        // A locked step of a hidden chain keeps its secret. Knowing there is
        // a third milestone is the tease; knowing what it is spoils it.
        title: state === 'LOCKED' && row.is_hidden ? null : row.title,
        xpReward: row.xp_reward,
        placeName: state === 'LOCKED' && row.is_hidden ? null : row.place_name,
        countryName: row.country_name,
        requiresLocationVerification: row.requires_verification ?? false,
        completedBy: head.mode === 'group' ? row.completed_by : null,
      };
    });

    return {
      chainId: head.chain_id,
      name: head.name,
      description: head.description,
      mode: head.mode,
      completionRule: head.completion_rule,
      milestones,
      completedSteps: milestones.filter((m) => m.state === 'COMPLETE').length,
      totalSteps: milestones.length,
    };
  }

  /** The collab group running a group chain, if any. */
  private async chainGroupId(chainId: string): Promise<string | null> {
    const result = await this.database.query<{ collab_group_id: string | null }>(
      'SELECT collab_group_id FROM quest_chains WHERE id = $1', [chainId],
    );
    return result.rows[0]?.collab_group_id ?? null;
  }

  /** Countries with published content, for the EXPLORE picker. */
  async countriesWithContent(): Promise<readonly { code: string; name: string; questCount: number }[]> {
    const result = await this.database.query<{ code: string; name: string; quest_count: number }>(
      `SELECT c.code, c.name, count(DISTINCT q.id)::int AS quest_count
       FROM map_countries c
       JOIN map_places p ON p.country_code = c.code AND p.is_published
       JOIN quest_destinations d ON d.place_id = p.id
       JOIN quests q ON q.id = d.quest_id AND q.is_active AND NOT q.is_hidden
       GROUP BY c.code, c.name
       HAVING count(DISTINCT q.id) > 0
       ORDER BY c.name`,
    );
    return result.rows.map((r) => ({ code: r.code, name: r.name, questCount: r.quest_count }));
  }

  /**
   * One more quest from a shelf's pool, excluding what the player has
   * already been shown.
   *
   * This is the wider catalogue behind each row: the shelf shows a curated
   * handful, and GENERATE reaches past them without turning the shelf into a
   * list. Random order rather than ranked, because the point is discovery of
   * something you were not being sold.
   */
  async generateFor(
    userId: string,
    channel: GenerateChannel,
    options: { countryCode?: string; excludeIds?: readonly string[]; count?: number } = {},
  ): Promise<readonly DiscoveryQuestCard[]> {
    const exclude = options.excludeIds ?? [];
    // Three, like the roll. One card is a verdict; three is a choice, and
    // choosing is the mechanic the whole app is built around.
    const count = Math.min(Math.max(options.count ?? 3, 1), 10);
    const result = await this.database.query<CardRow>(
      // DISTINCT ON keeps one opener per chain; the other channels have no
      // chain to collapse, so it is a no-op for them.
      `SELECT DISTINCT ON (q.id) ${CARD_COLUMNS}
       ${CARD_JOINS}
       ${channel === 'MULTI_STAGE' ? MULTI_STAGE_JOINS : ''}
       WHERE ${eligibilityFor(channel, { alias: 'q', userParam: '$1' })}
         AND q.id <> ALL($2::uuid[])
         AND ($3::text IS NULL OR p.country_code = $3)
         AND ($4::boolean IS NOT TRUE OR q.available_until IS NOT NULL)
       ORDER BY q.id, random()
       LIMIT $5`,
      [userId, exclude, options.countryCode ?? null, channel === 'LIMITED_TIME', count],
    );
    return result.rows.map(toCard);
  }

  /** How much is left in a shelf's pool, so the client can stop asking. */
  async remainingFor(
    userId: string,
    channel: GenerateChannel,
    options: { countryCode?: string; excludeIds?: readonly string[] } = {},
  ): Promise<number> {
    const result = await this.database.query<{ n: number }>(
      `SELECT count(DISTINCT q.id)::int AS n
       ${CARD_JOINS}
       ${channel === 'MULTI_STAGE' ? MULTI_STAGE_JOINS : ''}
       WHERE ${eligibilityFor(channel, { alias: 'q', userParam: '$1' })}
         AND q.id <> ALL($2::uuid[])
         AND ($3::text IS NULL OR p.country_code = $3)
         AND ($4::boolean IS NOT TRUE OR q.available_until IS NOT NULL)`,
      [userId, options.excludeIds ?? [], options.countryCode ?? null, channel === 'LIMITED_TIME'],
    );
    return result.rows[0]?.n ?? 0;
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
  // A chain quest carries its shape wherever it is shown — on a travel
  // shelf, in trending, in a country row. Somebody deciding whether to take
  // this on needs to know it is three visits and not one, and that is true
  // regardless of which shelf they found it on.
  if (row.chain_length > 1) badges.push(`${row.chain_length}-STEP JOURNEY`);
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
