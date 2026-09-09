BEGIN;

CREATE TABLE map_countries (
  code text PRIMARY KEY CHECK (code ~ '^[A-Z]{2}$'),
  name text NOT NULL CHECK (length(name) BETWEEN 1 AND 100),
  geometry_id text NOT NULL UNIQUE CHECK (geometry_id ~ '^[0-9]{3}$')
);
CREATE TABLE map_places (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  country_code text NOT NULL REFERENCES map_countries(code),
  name text NOT NULL CHECK (length(name) BETWEEN 1 AND 160),
  description text NOT NULL DEFAULT '',
  city text NOT NULL DEFAULT '',
  category text NOT NULL CHECK (category IN ('landmark','culture','pilgrimage','heritage','hidden')),
  latitude double precision NOT NULL CHECK (latitude BETWEEN -85 AND 85),
  longitude double precision NOT NULL CHECK (longitude BETWEEN -180 AND 180),
  radius_m integer NOT NULL DEFAULT 250 CHECK (radius_m BETWEEN 25 AND 10000),
  is_published boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX map_places_country_idx ON map_places(country_code, id) WHERE is_published;
CREATE TABLE quest_destinations (
  quest_id uuid PRIMARY KEY REFERENCES quests(id) ON DELETE CASCADE,
  place_id uuid NOT NULL REFERENCES map_places(id) ON DELETE RESTRICT,
  requires_verification boolean NOT NULL DEFAULT true
);
CREATE INDEX quest_destinations_place_idx ON quest_destinations(place_id);
CREATE TABLE saved_map_places (
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  place_id uuid NOT NULL REFERENCES map_places(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, place_id)
);

-- Only a trusted CAMARA consumer may write completed verification evidence.
-- There is deliberately no public HTTP endpoint that sets these booleans.
CREATE TABLE map_location_evidence (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  place_id uuid NOT NULL REFERENCES map_places(id) ON DELETE CASCADE,
  provider_reference text NOT NULL UNIQUE,
  location_verified boolean NOT NULL,
  location_retrieved boolean NOT NULL,
  geofence_verified boolean NOT NULL,
  verified_at timestamptz NOT NULL,
  expires_at timestamptz NOT NULL CHECK (expires_at > verified_at)
);
CREATE INDEX map_location_evidence_lookup_idx ON map_location_evidence(user_id, place_id, expires_at);

-- Applies to every assignment path, including group joins and admin overrides.
CREATE FUNCTION enforce_destination_assignment() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE destination record;
BEGIN
  PERFORM id FROM quests WHERE id=NEW.quest_id FOR SHARE;
  SELECT d.*,p.is_published,p.category INTO destination FROM quest_destinations d
    JOIN map_places p ON p.id=d.place_id WHERE d.quest_id=NEW.quest_id;
  IF FOUND AND (NOT destination.is_published OR
      ((destination.requires_verification OR destination.category='hidden') AND NOT EXISTS (
        SELECT 1 FROM map_location_evidence e WHERE e.user_id=NEW.user_id AND e.place_id=destination.place_id
          AND e.location_verified AND e.location_retrieved AND e.geofence_verified
          AND e.verified_at<=now() AND e.expires_at>now()
      ))) THEN
    RAISE EXCEPTION 'Destination location verification required' USING ERRCODE='23514';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER user_quest_destination_guard BEFORE INSERT OR UPDATE OF quest_id,user_id
  ON user_quests FOR EACH ROW EXECUTE FUNCTION enforce_destination_assignment();

-- Real country identifiers, not mock completion data or fabricated quests.
INSERT INTO map_countries(code,name,geometry_id) VALUES ('LB','Lebanon','422'), ('QA','Qatar','634');
COMMIT;
