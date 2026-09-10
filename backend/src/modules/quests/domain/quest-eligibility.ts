/**
 * One definition of "may this user be shown this quest", shared by the roll,
 * Home discovery, the map, search and country pages.
 *
 * It exists because the conditions are the same everywhere and the cost of
 * disagreement is asymmetric: a discovery surface that forgets one clause
 * leaks a hidden quest's content, offers a festival that ended in March, or
 * hands somebody step 3 of a chain they have not started. Each surface
 * re-deriving the rules is how one of them ends up wrong.
 *
 * These are SQL fragments rather than a row-by-row predicate on purpose. The
 * filters have to run inside the query that ranks and paginates — pulling
 * candidates into Node to filter them there would read the whole catalogue
 * to render five cards.
 */

/** Why a quest is being looked up. Different surfaces admit different content. */
export type DiscoveryChannel =
  /** The random roll. The narrowest pool: immediately doable, no travel implied. */
  | 'ROLL'
  /** Curated flagship destination content, browsable from anywhere. */
  | 'WORTH_THE_TRIP'
  /** Ranked by community participation. */
  | 'TRENDING'
  /** Destination quests near the user's verified country. */
  | 'NEAR_YOU'
  /** Active event windows only. */
  | 'LIMITED_TIME'
  /** Collections the user has started or could start. */
  | 'JOURNEY'
  /** Hidden quests this user has actually opened. */
  | 'HIDDEN_DISCOVERED'
  /** Everything published in one country. */
  | 'COUNTRY'
  /** Map pins. */
  | 'MAP'
  /** Sponsored placement. */
  | 'PARTNER'
  /** The one community quest for today. No viewer, so no per-user clauses. */
  | 'QUEST_OF_DAY';

export interface EligibilityOptions {
  /** Table alias the fragment is applied to. */
  readonly alias: string;
  /**
   * Bound parameter holding the viewer's id, e.g. `'$1'`.
   *
   * Omitted for surfaces with no viewer — Quest of the Day is one quest for
   * the whole community, so there is nobody to ask "have you unlocked this".
   * Without a viewer the per-user clauses cannot be evaluated, so the engine
   * falls back to the strict reading: hidden content and chain steps are
   * excluded outright rather than assumed available.
   */
  readonly userParam?: string;
}

/**
 * Clauses true of any quest anyone may see, on any surface.
 *
 * Deliberately does NOT include the destination exclusion. That belongs to
 * the roll alone: a destination quest is perfectly legitimate on the map and
 * in discovery, and folding it in here is what made destination content
 * invisible everywhere except the map.
 */
export function baseVisible({ alias }: EligibilityOptions): string {
  return `${alias}.is_active
    AND (${alias}.available_from  IS NULL OR ${alias}.available_from  <= now())
    AND (${alias}.available_until IS NULL OR ${alias}.available_until >  now())`;
}

/**
 * Hidden content, withheld until this user has opened it.
 *
 * Reads `user_quest_unlocks` rather than re-evaluating the rules, so a
 * discovery cannot be taken back by evidence expiring or a place being
 * unpublished later. Finding something is an event, not a live condition.
 */
export function hiddenVisibleToUser({ alias, userParam }: EligibilityOptions): string {
  if (!userParam) return `NOT ${alias}.is_hidden`;
  return `(NOT ${alias}.is_hidden OR EXISTS (
    SELECT 1 FROM user_quest_unlocks u
    WHERE u.quest_id = ${alias}.id AND u.user_id = ${userParam}
  ))`;
}

/**
 * Chain steps the user is not entitled to yet.
 *
 * `solo` chains ask whether THIS user has the previous step approved.
 * `group` chains ask whether ANY member of the chain's collab group does —
 * which is the whole point of a relay, and the case that silently never
 * worked because the original gate only ever checked the caller.
 *
 * `all_steps_any_order` chains gate nothing: a cross-country challenge has
 * no reason to make Palestine wait for Lebanon.
 */
export function chainStepUnlocked({ alias, userParam }: EligibilityOptions): string {
  if (!userParam) {
    // No viewer to attribute an approval to, so no later step can be shown.
    return `NOT EXISTS (
      SELECT 1 FROM quest_chain_steps cs
      WHERE cs.quest_id = ${alias}.id AND cs.step_order > 1
    )`;
  }
  return `NOT EXISTS (
    SELECT 1
    FROM quest_chain_steps cs
    JOIN quest_chains ch ON ch.id = cs.chain_id
    WHERE cs.quest_id = ${alias}.id
      AND cs.step_order > 1
      AND ch.completion_rule = 'sequential'
      AND NOT EXISTS (
        SELECT 1
        FROM quest_chain_steps prev
        JOIN user_quests uq ON uq.quest_id = prev.quest_id
        WHERE prev.chain_id  = cs.chain_id
          AND prev.step_order = cs.step_order - 1
          AND uq.status = 'approved'
          AND (
            ch.mode = 'solo' AND uq.user_id = ${userParam}
            OR ch.mode = 'group' AND EXISTS (
              SELECT 1 FROM collab_group_members m
              WHERE m.group_id = ch.collab_group_id AND m.user_id = uq.user_id
            )
          )
      )
  )`;
}

/** Quests whose destination place is published — an unpublished place hides its quests. */
export function destinationPublished({ alias }: EligibilityOptions): string {
  return `NOT EXISTS (
    SELECT 1 FROM quest_destinations d
    JOIN map_places p ON p.id = d.place_id
    WHERE d.quest_id = ${alias}.id AND NOT p.is_published
  )`;
}

/** A quest with no destination at all — the roll's pool. */
export function locationIndependent({ alias }: EligibilityOptions): string {
  return `NOT EXISTS (SELECT 1 FROM quest_destinations d WHERE d.quest_id = ${alias}.id)`;
}

/** Already taken to a conclusion by this user, so not worth offering again. */
export function notAlreadySettled({ alias, userParam }: EligibilityOptions): string {
  if (!userParam) return 'true';
  return `NOT EXISTS (
    SELECT 1 FROM user_quests uq
    WHERE uq.user_id = ${userParam} AND uq.quest_id = ${alias}.id
      AND uq.status IN ('submitted', 'approved')
  )`;
}

/**
 * The full filter for a channel, as one AND-ed fragment.
 *
 * Every channel gets base visibility, hidden-unlock and chain-step checks;
 * they differ only in what else they admit. Writing them as one function
 * rather than per-surface strings is what stops the surfaces drifting apart.
 */
export function eligibilityFor(channel: DiscoveryChannel, options: EligibilityOptions): string {
  const clauses = [
    baseVisible(options),
    hiddenVisibleToUser(options),
    chainStepUnlocked(options),
    destinationPublished(options),
  ];

  switch (channel) {
    case 'ROLL':
      // The roll stays exactly what it was: something you can start now,
      // without a plane ticket. Discovery is where travel lives.
      clauses.push(locationIndependent(options), notAlreadySettled(options));
      break;
    case 'WORTH_THE_TRIP':
      clauses.push(
        `${options.alias}.editorial_tier = 'flagship'`,
        `${options.alias}.is_globally_discoverable`,
        notAlreadySettled(options),
      );
      break;
    case 'NEAR_YOU':
    case 'COUNTRY':
    case 'MAP':
    case 'TRENDING':
    case 'LIMITED_TIME':
    case 'JOURNEY':
    case 'PARTNER':
      // Browsable from anywhere; presence is only required to COMPLETE a
      // location-verified quest, never to look at one.
      clauses.push(`${options.alias}.is_globally_discoverable`);
      break;
    case 'QUEST_OF_DAY':
      // Everyone gets the same quest, so it must be doable by anyone: no
      // destination, no travel, no per-user unlock.
      clauses.push(locationIndependent(options));
      break;
    case 'HIDDEN_DISCOVERED':
      // Only what this user actually opened, and only while unseen elsewhere.
      clauses.push(`${options.alias}.is_hidden`);
      break;
  }

  return clauses.join('\n    AND ');
}
