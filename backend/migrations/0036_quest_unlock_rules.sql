BEGIN;

-- Hidden quests need a reason to open (#51, #6).
--
-- `quests.is_hidden` already withholds content server-side, which is the
-- half that matters for safety — but nothing has ever been able to clear it,
-- so every hidden quest is permanently invisible and the mechanic does not
-- exist in practice. These two tables are the missing half.
--
-- Rules are DATA, not code branches, because the set of unlock conditions is
-- product surface that will keep growing: put them in a switch statement and
-- every new condition is a deploy. Five types cover everything the proposal
-- describes; a sixth is an INSERT, not a migration.
CREATE TABLE IF NOT EXISTS quest_unlock_rules (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  quest_id    uuid NOT NULL REFERENCES quests(id) ON DELETE CASCADE,
  unlock_type text NOT NULL CHECK (unlock_type IN (
    'country_entered',      -- verified presence anywhere in a country
    'place_entered',        -- verified presence at one place
    'prerequisite_quest',   -- another quest approved
    'collection_progress',  -- N approved quests inside a collection
    'date_event'            -- the quest's own availability window opened
  )),
  -- What the rule points at. Which column is used depends on unlock_type,
  -- and the CHECK below makes an incoherent row impossible to insert rather
  -- than leaving it to be discovered by a null at read time.
  country_code  char(2) REFERENCES map_countries(code) ON DELETE CASCADE,
  place_id      uuid    REFERENCES map_places(id)      ON DELETE CASCADE,
  prerequisite_quest_id uuid REFERENCES quests(id)     ON DELETE CASCADE,
  collection_id uuid    REFERENCES quest_collections(id) ON DELETE CASCADE,
  threshold     integer CHECK (threshold IS NULL OR threshold >= 1),
  created_at    timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT quest_unlock_rules_target_matches_type CHECK (
    CASE unlock_type
      WHEN 'country_entered'     THEN country_code IS NOT NULL
      WHEN 'place_entered'       THEN place_id IS NOT NULL
      WHEN 'prerequisite_quest'  THEN prerequisite_quest_id IS NOT NULL
      WHEN 'collection_progress' THEN collection_id IS NOT NULL AND threshold IS NOT NULL
      WHEN 'date_event'          THEN true
    END
  ),
  -- A quest that is its own prerequisite can never open.
  CONSTRAINT quest_unlock_rules_no_self_prerequisite
    CHECK (prerequisite_quest_id IS NULL OR prerequisite_quest_id <> quest_id)
);

CREATE INDEX IF NOT EXISTS quest_unlock_rules_quest_idx ON quest_unlock_rules (quest_id);
CREATE INDEX IF NOT EXISTS quest_unlock_rules_place_idx ON quest_unlock_rules (place_id)
  WHERE place_id IS NOT NULL;

COMMENT ON TABLE quest_unlock_rules IS
  'What opens a hidden quest. Multiple rules on one quest are OR-ed: any '
  'satisfied rule reveals it, so a landmark can be reached either by going '
  'there or by finishing the chain that leads there.';

-- The record that a user opened something, kept rather than recomputed.
--
-- Recomputing would mean a quest could silently close again — evidence
-- expires, a place is unpublished, a collection is re-scoped — and a player
-- who genuinely discovered something would watch it vanish. Discovery is an
-- event that happened; it does not un-happen.
CREATE TABLE IF NOT EXISTS user_quest_unlocks (
  user_id     uuid NOT NULL REFERENCES users(id)  ON DELETE CASCADE,
  quest_id    uuid NOT NULL REFERENCES quests(id) ON DELETE CASCADE,
  rule_id     uuid REFERENCES quest_unlock_rules(id) ON DELETE SET NULL,
  unlocked_at timestamptz NOT NULL DEFAULT now(),
  -- Cleared when the user has seen the "Hidden Quest Discovered" moment, so
  -- Home can surface it exactly once.
  seen_at     timestamptz,
  PRIMARY KEY (user_id, quest_id)
);

CREATE INDEX IF NOT EXISTS user_quest_unlocks_unseen_idx
  ON user_quest_unlocks (user_id, unlocked_at DESC) WHERE seen_at IS NULL;

COMMENT ON TABLE user_quest_unlocks IS
  'Durable record that a hidden quest opened for a user. Never recomputed: '
  'a discovery must not be revocable by later data changes.';

COMMIT;
