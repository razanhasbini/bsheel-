/**
 * The one social ranking model, as a SQL fragment every surface embeds.
 *
 * Before this the feed, the map's DISCOVER and search each had their own
 * idea of "trending": the feed decayed net votes alone, the map added
 * completions and comments with weights of its own, search sorted by date.
 * The same post could be first on one screen and invisible on another, and
 * no test could say which was right because there was no "right".
 *
 * Now there is one score per submission — votes, comments, saves, the
 * BSHEEELs that post caused, and the verified completions those BSHEEELs led
 * to — decayed by age the way the feed always has. The feed ranks posts by
 * it, the map ranks a quest by the sum over its approved posts, and search
 * orders posts by it. Change a weight here and every surface moves together.
 *
 * Deliberately a string the callers interpolate, not a SQL function: it has
 * to sit inside keyset-pagination predicates the feed builds (`score < $7`),
 * and a function call there defeats the indexes those predicates rely on.
 * Every input is a fixed alias or a bound-parameter placeholder — never user
 * text.
 */
export const SOCIAL_RANK_WEIGHTS = {
  /** A reply is engagement, but a lighter one than a vote. */
  comment: 0.5,
  /** Saving a post is the strongest passive signal a viewer gives. */
  save: 2,
  /** Somebody pressed BSHEEEL on the quest *from this post*. */
  bsheeelFromPost: 1,
  /** …and then actually did the quest and had it approved. */
  completionInspired: 1.5,
  /** Hours added before decay so a brand-new post is not divided by ~0. */
  decayOffsetHours: 2,
  /** Hacker-News-style gravity; the feed's value since day one. */
  decayPower: 1.5,
} as const;

/**
 * Per-submission social score for a `submissions` row aliased `alias`, as of
 * the timestamp expression `asOf` (a `$n::timestamptz` placeholder or
 * `now()`). Requires the alias to be in scope; `id`, `net_score` and
 * `submitted_at` are read from it.
 */
export function submissionSocialRank(alias: string, asOf: string): string {
  const w = SOCIAL_RANK_WEIGHTS;
  return `((${alias}.net_score::double precision
      + ${w.comment} * (SELECT count(*) FROM comments rc WHERE rc.submission_id = ${alias}.id)
      + ${w.save} * (SELECT count(*) FROM saved_posts rsp WHERE rsp.submission_id = ${alias}.id)
      + ${w.bsheeelFromPost} * (SELECT count(*) FROM analytics_events rae
                                 WHERE rae.source_submission_id = ${alias}.id AND rae.event_type = 'quest_bsheeel')
      + ${w.completionInspired} * (SELECT count(DISTINCT ruq.user_id)
                                    FROM analytics_events rae
                                    JOIN user_quests ruq ON ruq.user_id = rae.user_id AND ruq.quest_id = rae.quest_id
                                                        AND ruq.assigned_at >= rae.occurred_at
                                    JOIN submissions rs2 ON rs2.user_quest_id = ruq.id AND rs2.status = 'approved'
                                                        AND rs2.deleted_at IS NULL
                                    WHERE rae.source_submission_id = ${alias}.id AND rae.event_type = 'quest_bsheeel')
    ) / power(GREATEST(EXTRACT(EPOCH FROM (${asOf} - ${alias}.submitted_at)) / 3600.0, 0) + ${w.decayOffsetHours}, ${w.decayPower}))`;
}
