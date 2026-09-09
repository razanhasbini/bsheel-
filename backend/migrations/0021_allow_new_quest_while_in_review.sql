BEGIN;

-- Let a user roll a new quest while earlier submissions are still awaiting
-- review, while still holding them to one *active* quest at a time.
--
-- The old index treated 'assigned' and 'submitted' as one bucket, so a user
-- who submitted proof was locked out of the app until a moderator got to it.
-- With review latency measured in hours (the dashboard tracks "oldest 6h 12m")
-- that is a dead end the user cannot clear themselves, and it is the single
-- biggest reason the home screen has nothing to offer a waiting player.
--
-- What stays enforced:
--   * exactly one 'assigned' quest per user, still database-enforced;
--   * the five-rerolls-per-24h cap (quest_reroll_log), which is now the real
--     limit on how fast quests can be taken on;
--   * one appeal per submission, which is per-submission and unaffected;
--   * XP awarded once per approval, which is per-submission and unaffected.
--
-- What changes: a user may hold any number of 'submitted' rows. Each is
-- reviewed and awarded independently, so this does not let anyone earn XP
-- twice for the same submission.

DROP INDEX IF EXISTS user_quests_one_in_progress_idx;

CREATE UNIQUE INDEX user_quests_one_assigned_idx
  ON user_quests (user_id)
  WHERE status = 'assigned';

COMMENT ON INDEX user_quests_one_assigned_idx IS
  'One active quest per user. Submitted-but-unreviewed quests are deliberately '
  'excluded so a user is not blocked by moderation latency; see migration 0021.';

COMMIT;
