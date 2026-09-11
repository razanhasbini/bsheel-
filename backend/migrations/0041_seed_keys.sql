BEGIN;

-- Stable identity for curated content, so seeding is idempotent (#51).
--
-- Keyed on this rather than on the title, because curated copy gets edited —
-- that is the point of curating it — and keying on a title would insert a
-- second copy of a quest every time somebody fixed a typo in it.
--
-- Null for everything a person authored through the admin console. That is
-- what makes `--prune` safe: it can only ever delete rows inside the
-- `bsheel:` namespace, so it cannot reach user-authored content even by
-- accident.
ALTER TABLE quests            ADD COLUMN IF NOT EXISTS seed_key text UNIQUE;
ALTER TABLE map_places        ADD COLUMN IF NOT EXISTS seed_key text UNIQUE;
ALTER TABLE quest_chains      ADD COLUMN IF NOT EXISTS seed_key text UNIQUE;
ALTER TABLE quest_collections ADD COLUMN IF NOT EXISTS seed_key text UNIQUE;
ALTER TABLE quest_partners    ADD COLUMN IF NOT EXISTS seed_key text UNIQUE;

COMMENT ON COLUMN quests.seed_key IS
  'Stable id for curated seed content, namespaced `bsheel:`. Null for '
  'anything authored by a person; that is what keeps --prune off their work.';

COMMIT;
