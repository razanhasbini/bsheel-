BEGIN;

-- Two editorial facts the catalogue could not previously express (#51).
--
-- Both are deliberately NOT derived from xp_reward. "Worth travelling for"
-- is about how singular the experience is, not how hard it is: learning to
-- fold a manoushe with the baker who has done it for forty years is easy and
-- unrepeatable anywhere else, while a hard fitness quest is neither. Deriving
-- this from difficulty would fill the tourism shelf with burpees.
ALTER TABLE quests ADD COLUMN IF NOT EXISTS editorial_tier text NOT NULL DEFAULT 'standard'
  CHECK (editorial_tier IN ('standard', 'flagship'));

COMMENT ON COLUMN quests.editorial_tier IS
  'Curation, set by a human. flagship = worth crossing a border for; it is '
  'what WORTH THE TRIP draws from. Never inferred from xp or difficulty.';

-- Whether someone who is not there may see it.
--
-- The proposal''s flagship journey depends on this: a user in Lebanon watches
-- a Lusail Stadium completion and presses Do This Quest *before* travelling.
-- If foreign quests were invisible until arrival, discovery could never
-- motivate a trip and the product loses its point.
--
-- Default true, because withholding is the exception and hidden quests
-- already have their own mechanism. A quest that genuinely only makes sense
-- on arrival sets this false rather than being hidden.
ALTER TABLE quests ADD COLUMN IF NOT EXISTS is_globally_discoverable boolean NOT NULL DEFAULT true;

COMMENT ON COLUMN quests.is_globally_discoverable IS
  'Browsable from anywhere. Browsing never requires CAMARA; only completing '
  'a location-verified quest does.';

-- Flagship quests are read together with their destination on every
-- WORTH THE TRIP query, and there will never be many of them.
CREATE INDEX IF NOT EXISTS quests_flagship_idx
  ON quests (created_at DESC)
  WHERE is_active AND NOT is_hidden AND editorial_tier = 'flagship' AND is_globally_discoverable;

COMMENT ON INDEX quests_flagship_idx IS
  'WORTH THE TRIP. Window and per-user exclusions stay in the query since '
  'they depend on now() and the viewer.';

COMMIT;
