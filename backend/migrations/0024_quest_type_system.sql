BEGIN;

-- The full quest system (#51). Every type in the proposal is now
-- representable, and the existing random-quest algorithm is untouched — the
-- issue is explicit that these types must extend it, not replace it.
--
-- The controlling risk is the ROLL, not the schema. Adding rows for a
-- stage-3 quest or a finished festival is harmless; letting the random
-- picker offer them is not. Every column here exists so `pickerOptions` can
-- exclude what a user must not be handed, and the eligibility filter is
-- widened in the same change.

-- ── Event / time-limited quests ──────────────────────────────────────
-- Festivals, sports events, pilgrimage seasons, national occasions. Null
-- means unbounded, so every existing quest keeps its current behaviour.
ALTER TABLE quests ADD COLUMN IF NOT EXISTS available_from  timestamptz;
ALTER TABLE quests ADD COLUMN IF NOT EXISTS available_until timestamptz;

ALTER TABLE quests DROP CONSTRAINT IF EXISTS quests_availability_window_check;
ALTER TABLE quests ADD CONSTRAINT quests_availability_window_check
  CHECK (available_from IS NULL OR available_until IS NULL OR available_from < available_until);

COMMENT ON COLUMN quests.available_from IS
  'Event quests (#51): inclusive start of the availability window; null = always.';
COMMENT ON COLUMN quests.available_until IS
  'Event quests (#51): exclusive end of the availability window; null = never expires.';

-- ── Hidden quests ────────────────────────────────────────────────────
-- Content that must stay server-side until unlocked. A hidden quest is never
-- offered by the roll; it is reached by unlocking a place, by an admin
-- injection, or as a later step of a chain. #6 and #51 both require that the
-- content itself stays withheld, not merely un-rendered.
ALTER TABLE quests ADD COLUMN IF NOT EXISTS is_hidden boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN quests.is_hidden IS
  'Hidden quests (#51): excluded from the random roll. Reachable only via an '
  'unlock, an admin injection, or a chain step.';

-- ── Sponsored / partner attribution ──────────────────────────────────
-- Attribution only, deliberately. Partner *accounts* are #14 and vendor
-- analytics is #50; building either here would ship a separate product by
-- accident, which docs/design/MAP_REQUIREMENTS.md warns against. A name is
-- enough to represent a sponsored quest and to render its credit.
ALTER TABLE quests ADD COLUMN IF NOT EXISTS sponsor_name text;
ALTER TABLE quests DROP CONSTRAINT IF EXISTS quests_sponsor_name_check;
ALTER TABLE quests ADD CONSTRAINT quests_sponsor_name_check
  CHECK (sponsor_name IS NULL OR length(btrim(sponsor_name)) BETWEEN 1 AND 120);

COMMENT ON COLUMN quests.sponsor_name IS
  'Sponsored quests (#51): display credit only. Partner accounts are #14.';

-- ── Multi-stage, sequential-group and cross-country chains ───────────
-- One mechanism covers all three: an ordered sequence of quests where a step
-- unlocks only once the previous step has APPROVED proof.
--
--  * multi-stage      — every step assigned to the same user
--  * sequential group — steps advance across members of a collab group
--  * cross-country    — steps carry destination links in different countries
--
-- The difference is who the next step is offered to, which is a property of
-- the chain, not of a new table each.
CREATE TABLE IF NOT EXISTS quest_chains (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name        text NOT NULL CHECK (length(btrim(name)) BETWEEN 1 AND 160),
  description text NOT NULL DEFAULT '',
  -- 'solo'  : the same user completes every step (multi-stage)
  -- 'group' : an approved step unlocks the next member's step
  mode        text NOT NULL DEFAULT 'solo' CHECK (mode IN ('solo', 'group')),
  is_active   boolean NOT NULL DEFAULT true,
  created_by  uuid REFERENCES profiles(id) ON DELETE SET NULL,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS quest_chain_steps (
  chain_id   uuid NOT NULL REFERENCES quest_chains(id) ON DELETE CASCADE,
  quest_id   uuid NOT NULL REFERENCES quests(id) ON DELETE CASCADE,
  step_order integer NOT NULL CHECK (step_order >= 1),
  PRIMARY KEY (chain_id, step_order),
  -- A quest belongs to at most one position in one chain, so "which step is
  -- this?" always has a single answer.
  UNIQUE (quest_id)
);

CREATE INDEX IF NOT EXISTS quest_chain_steps_quest_idx ON quest_chain_steps (quest_id);

COMMENT ON TABLE quest_chains IS
  'Multi-stage / sequential-group / cross-country quests (#51, #6). A step '
  'unlocks only when the previous step has approved proof.';

-- ── Collection / journey quests ──────────────────────────────────────
-- "Discover Lebanon — 50 Quests": a campaign grouping with progress toward
-- the whole set. Membership is many-to-many because a quest can belong to a
-- country journey and a seasonal campaign at once.
CREATE TABLE IF NOT EXISTS quest_collections (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name         text NOT NULL CHECK (length(btrim(name)) BETWEEN 1 AND 160),
  description  text NOT NULL DEFAULT '',
  -- Optional so a campaign need not be tied to one country.
  country_code char(2) REFERENCES map_countries(code) ON DELETE SET NULL,
  is_published boolean NOT NULL DEFAULT false,
  created_by   uuid REFERENCES profiles(id) ON DELETE SET NULL,
  created_at   timestamptz NOT NULL DEFAULT now(),
  updated_at   timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS quest_collection_items (
  collection_id uuid NOT NULL REFERENCES quest_collections(id) ON DELETE CASCADE,
  quest_id      uuid NOT NULL REFERENCES quests(id) ON DELETE CASCADE,
  PRIMARY KEY (collection_id, quest_id)
);

CREATE INDEX IF NOT EXISTS quest_collection_items_quest_idx
  ON quest_collection_items (quest_id);

COMMENT ON TABLE quest_collections IS
  'Collection / journey quests (#51): a campaign with progress over its set.';

-- ── Roll eligibility ─────────────────────────────────────────────────
-- The reason the columns above are safe. A partial index over exactly what
-- the picker treats as rollable, so widening the filter does not cost a scan.
CREATE INDEX IF NOT EXISTS quests_rollable_idx
  ON quests (created_at DESC)
  WHERE is_active AND NOT is_hidden;

COMMENT ON INDEX quests_rollable_idx IS
  'Random-roll candidates (#51): active, not hidden. Window and chain-step '
  'exclusions are applied per-query since they depend on now() and the user.';

COMMIT;
