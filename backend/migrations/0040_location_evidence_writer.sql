BEGIN;

-- Gives map_location_evidence a writer, and moves the moment location is
-- required (#53, and the proposal's own flagship journey).
--
-- Two problems, one cause.
--
-- 1. The table has had three readers and no writer since 0022. Hidden places
--    could never open and destination quests requiring verification could
--    never be assigned, because the only thing that could clear either gate
--    was a row nothing inserted.
--
-- 2. The gate was in the wrong place. `assertDestinationAccess(assignment)`
--    demanded verified presence BEFORE a quest could be taken. The proposal's
--    central journey is the opposite: a user in Lebanon watches a Lusail
--    Stadium completion, presses Do This Quest, and *saves it for a trip they
--    have not taken yet*. Requiring presence at assignment makes discovery
--    unable to motivate travel, which is the product.
--
-- Presence is now proven where it is actually claimed — at submission, by the
-- CAMARA pipeline that already exists. Browsing and taking a quest need no
-- network evidence; completing a location-verified one does.
--
-- The application-side gate change accompanies this migration; what SQL owns
-- is making the row insertable idempotently.

-- The agent records evidence per user, per place, per submission. A retry of
-- the same verification run must update rather than duplicate, so the
-- provider reference (already unique) is the conflict target and this index
-- makes the freshness lookup cheap.
CREATE INDEX IF NOT EXISTS map_location_evidence_fresh_idx
  ON map_location_evidence (user_id, place_id, verified_at DESC)
  WHERE location_verified AND location_retrieved AND geofence_verified;

COMMENT ON INDEX map_location_evidence_fresh_idx IS
  'Fresh, fully-verified presence per user+place — the read behind hidden '
  'place unlocks and destination completion.';

COMMENT ON TABLE map_location_evidence IS
  'Written by the CAMARA verification pipeline at SUBMISSION time, never by '
  'a client and never by a save or a moderation click. Read to open hidden '
  'places and to confirm a destination completion. It is deliberately not '
  'consulted when assigning a quest: taking a challenge in another country '
  'is how a trip starts.';

-- Records that a user reached a country, which `country_entered` unlock
-- rules read. Derived from evidence rather than stored per country, so it
-- cannot drift — a view keeps one definition of "has been there".
CREATE OR REPLACE VIEW user_verified_countries AS
  SELECT DISTINCT e.user_id, p.country_code
  FROM map_location_evidence e
  JOIN map_places p ON p.id = e.place_id
  WHERE e.location_verified AND e.location_retrieved AND e.geofence_verified;

COMMENT ON VIEW user_verified_countries IS
  'Countries a user has network-verified presence in. One definition, shared '
  'by unlock rules and map progress, so the two can never disagree.';

COMMIT;
