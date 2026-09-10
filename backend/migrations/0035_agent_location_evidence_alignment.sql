BEGIN;

-- Nokia enforces one geofencing event type per provider subscription. Keep
-- both the entry and exit subscription ids while retaining the original
-- column for backwards compatibility with already-created rows.
ALTER TABLE geofencing_subscriptions
  ADD COLUMN provider_subscription_ids text[] NOT NULL DEFAULT '{}';
UPDATE geofencing_subscriptions
SET provider_subscription_ids = ARRAY[provider_subscription_id]
WHERE provider_subscription_id IS NOT NULL
  AND cardinality(provider_subscription_ids) = 0;

-- The old map guard required all three location checks before an assignment
-- existed. The current architecture creates the geofence after assignment
-- and evaluates evidence at submission time, so that requirement could not
-- be satisfied through the real quest lifecycle. Preserve the published
-- destination safety check and leave proof verification to the authoritative
-- network_evidence/geofencing + agent pipeline.
CREATE OR REPLACE FUNCTION enforce_destination_assignment() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE destination record;
BEGIN
  PERFORM id FROM quests WHERE id=NEW.quest_id FOR SHARE;
  SELECT d.*, p.is_published INTO destination
  FROM quest_destinations d
  JOIN map_places p ON p.id=d.place_id
  WHERE d.quest_id=NEW.quest_id;
  IF FOUND AND NOT destination.is_published THEN
    RAISE EXCEPTION 'Destination is not published' USING ERRCODE='23514';
  END IF;
  RETURN NEW;
END $$;

COMMENT ON TABLE map_location_evidence IS
  'Legacy pre-assignment location cache. New quest verification uses network_evidence and geofencing events scoped to an assignment window.';

COMMIT;
