BEGIN;

-- Business / destination accounts (#14), and the ownership edge the
-- analytics dashboard (#50) is scoped by.
--
-- A business is NOT a rung on the admin ladder. `admins.role` is an ordered
-- ladder — moderator, then super_admin — carried in the access token and
-- checked by RolesGuard, and every `@Roles` decorator reads it as "at least
-- this much authority over the whole system". A business has no authority
-- over the system at all: it is an ordinary player everywhere in the app,
-- and its extra rights are over *its own places* and nothing else. Modelling
-- it as a third role would have put a non-admin into the admin enum, forced
-- every existing @Roles site and the admin dashboard's route gating to
-- special-case a role that isn't ordered against the others, and changed
-- what an already-issued token's `role` claim means.
--
-- So authority here is membership, not rank, and it is resolved per request
-- against these tables rather than read off the token. That also means
-- granting or revoking business access takes effect immediately, instead of
-- when the user's token happens to expire.

CREATE TABLE businesses (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name          text NOT NULL CHECK (length(btrim(name)) BETWEEN 2 AND 120),
  -- Stable public handle, so a dashboard link can be shared and a place can
  -- be attributed without exposing the primary key.
  slug          citext NOT NULL UNIQUE CHECK (slug ~ '^[a-z0-9][a-z0-9-]{1,62}[a-z0-9]$'),
  description   text NOT NULL DEFAULT '',
  contact_email citext,
  website_url   text,
  logo_url      text,
  -- 'suspended' revokes the dashboard without deleting the ownership edges,
  -- so a dispute can be resolved without losing which places were claimed.
  status        text NOT NULL DEFAULT 'active'
                  CHECK (status IN ('active', 'suspended')),
  created_by    uuid REFERENCES users(id) ON DELETE SET NULL,
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now()
);

-- Which real-world places a business speaks for.
--
-- The UNIQUE constraint on place_id alone is the load-bearing one: a place
-- has at most one owner. Without it two businesses could both claim the
-- same landmark and both read its visitor analytics, which is a data leak
-- between competitors dressed up as a modelling mistake. Postgres is the
-- final guard for that, not application code.
CREATE TABLE business_places (
  business_id uuid NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
  place_id    uuid NOT NULL REFERENCES map_places(id) ON DELETE CASCADE,
  linked_by   uuid REFERENCES users(id) ON DELETE SET NULL,
  linked_at   timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (business_id, place_id),
  UNIQUE (place_id)
);

-- Who may act for a business. A person, not an account type: the same user
-- logs into the app as themselves and reaches the dashboard through this
-- edge, so nothing about their quests, feed or social graph changes.
--
-- 'owner' may manage members; 'manager' may only read the dashboard. Both
-- are scoped to one business — there is no global business role.
CREATE TABLE business_members (
  business_id uuid NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
  user_id     uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  role        text NOT NULL DEFAULT 'manager'
                CHECK (role IN ('owner', 'manager')),
  created_at  timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (business_id, user_id)
);

-- The dashboard's hot path is "everything this signed-in user may see",
-- which starts from user_id; the primary key leads with business_id and so
-- cannot serve it.
CREATE INDEX business_members_user_idx ON business_members (user_id);

-- Every analytics query starts by resolving the caller's places, so this is
-- the join it enters through.
CREATE INDEX business_places_business_idx ON business_places (business_id);

COMMIT;
