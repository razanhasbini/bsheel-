import { Injectable, Logger } from '@nestjs/common';
import { DatabaseService } from '../../../infrastructure/database/database.service.js';

/**
 * Opens hidden quests when their conditions are met.
 *
 * Runs after the events that could plausibly change the answer — verified
 * presence recorded, a submission approved — rather than on a timer, so the
 * "Hidden Quest Discovered" moment lands while the player is still standing
 * where they earned it.
 *
 * Evaluating rules is separate from reading them back: `user_quest_unlocks`
 * is written once here and every discovery surface reads that instead of
 * re-deriving. Otherwise a quest a player genuinely found could close again
 * when evidence expires or a place is unpublished, and a discovery that can
 * be taken away is not a discovery.
 */
@Injectable()
export class QuestUnlockService {
  private readonly logger = new Logger(QuestUnlockService.name);

  constructor(private readonly database: DatabaseService) {}

  /**
   * Evaluates every rule for one user and records what newly opened.
   *
   * Returns the quests that opened on THIS call, so the caller can notify.
   * Idempotent: a rule that was already satisfied inserts nothing, because
   * the primary key already holds that row.
   */
  async evaluateFor(userId: string): Promise<readonly { questId: string; title: string }[]> {
    const result = await this.database.query<{ quest_id: string; title: string }>(
      `WITH satisfied AS (
         SELECT r.quest_id, r.id AS rule_id
         FROM quest_unlock_rules r
         JOIN quests q ON q.id = r.quest_id AND q.is_active AND q.is_hidden
         WHERE
           CASE r.unlock_type
             -- Verified presence anywhere in the country. Reads the shared
             -- view so "has been there" means one thing everywhere.
             WHEN 'country_entered' THEN EXISTS (
               SELECT 1 FROM user_verified_countries v
               WHERE v.user_id = $1 AND v.country_code = r.country_code
             )
             WHEN 'place_entered' THEN EXISTS (
               SELECT 1 FROM map_location_evidence e
               WHERE e.user_id = $1 AND e.place_id = r.place_id
                 AND e.location_verified AND e.location_retrieved AND e.geofence_verified
             )
             -- Approval, not submission. A pending or rejected attempt must
             -- not open anything.
             WHEN 'prerequisite_quest' THEN EXISTS (
               SELECT 1 FROM user_quests uq
               WHERE uq.user_id = $1 AND uq.quest_id = r.prerequisite_quest_id
                 AND uq.status = 'approved'
             )
             WHEN 'collection_progress' THEN (
               SELECT count(*) FROM quest_collection_items ci
               JOIN user_quests uq ON uq.quest_id = ci.quest_id
               WHERE ci.collection_id = r.collection_id
                 AND uq.user_id = $1 AND uq.status = 'approved'
             ) >= r.threshold
             WHEN 'date_event' THEN
               q.available_from IS NOT NULL AND q.available_from <= now()
               AND (q.available_until IS NULL OR q.available_until > now())
             ELSE false
           END
       )
       INSERT INTO user_quest_unlocks (user_id, quest_id, rule_id)
       SELECT $1, s.quest_id, s.rule_id FROM satisfied s
       ON CONFLICT (user_id, quest_id) DO NOTHING
       RETURNING quest_id, (SELECT title FROM quests WHERE id = quest_id) AS title`,
      [userId],
    );

    if (result.rows.length > 0) {
      this.logger.log(
        { userId, opened: result.rows.length },
        'Hidden quests unlocked',
      );
    }
    return result.rows.map((row) => ({ questId: row.quest_id, title: row.title }));
  }
}
