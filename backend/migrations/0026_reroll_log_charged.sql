BEGIN;

-- Distinguishes a spin that spent budget from the free first spin of a cycle.
--
-- The cap is meant to be "five rerolls per rolling 24 hours", with the first
-- spin after finishing a quest free. Enforcing that needs the free spin
-- recorded — otherwise there is no way to tell the second spin of a cycle from
-- the first, and a gate keyed on "has anything been logged since the last
-- assignment" lets every spin through as free.
--
-- Existing rows were all charged: before this column the log was written only
-- by the charging path.
ALTER TABLE quest_reroll_log
  ADD COLUMN charged boolean NOT NULL DEFAULT true;

-- The cap counts charged rows inside the window, so that is what the index
-- has to cover.
CREATE INDEX quest_reroll_log_charged_window_idx
  ON quest_reroll_log (user_id, rerolled_at DESC)
  WHERE charged;

COMMENT ON COLUMN quest_reroll_log.charged IS
  'False for the free first spin of a roll cycle; the 5-per-24h cap counts only charged rows.';

COMMIT;
