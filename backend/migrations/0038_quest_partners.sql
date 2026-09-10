BEGIN;

-- Sponsored quests need a partner they point at, not a name typed into the
-- quest (#51, and the proposal's B2B2C model).
--
-- `quests.sponsor_name` is left in place and still rendered: it is live data,
-- and dropping a column to make a diagram tidier is how you lose attribution
-- on quests someone already published. New content uses the relation; the
-- text column is the fallback until the last row is migrated.
--
-- This is attribution and campaign windows only. Partner *accounts* (#14)
-- and vendor analytics (#50) are separate products, and building them here
-- would ship them by accident.
CREATE TABLE IF NOT EXISTS quest_partners (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name         text NOT NULL CHECK (length(btrim(name)) BETWEEN 1 AND 120),
  slug         text NOT NULL UNIQUE CHECK (slug ~ '^[a-z0-9][a-z0-9-]{1,79}$'),
  kind         text NOT NULL DEFAULT 'business' CHECK (kind IN (
    'business', 'restaurant', 'museum', 'hotel', 'attraction',
    'event_organizer', 'tourism_authority', 'municipality', 'other'
  )),
  country_code char(2) REFERENCES map_countries(code) ON DELETE SET NULL,
  -- Seeded demo partners must be impossible to mistake for a paying one.
  -- A boolean here is what lets the API refuse to serve them in production
  -- rather than relying on someone noticing the name.
  is_demo      boolean NOT NULL DEFAULT false,
  campaign_starts_at timestamptz,
  campaign_ends_at   timestamptz,
  created_at   timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT quest_partners_campaign_window CHECK (
    campaign_starts_at IS NULL OR campaign_ends_at IS NULL
    OR campaign_ends_at > campaign_starts_at
  )
);

COMMENT ON TABLE quest_partners IS
  'Sponsor/campaign attribution for quests. is_demo marks seed partners that '
  'must never be presented as real commercial relationships.';

ALTER TABLE quests ADD COLUMN IF NOT EXISTS partner_id uuid
  REFERENCES quest_partners(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS quests_partner_idx ON quests (partner_id)
  WHERE partner_id IS NOT NULL;

COMMENT ON COLUMN quests.partner_id IS
  'Sponsoring partner. Supersedes sponsor_name, which stays readable for '
  'quests published before this relation existed.';

COMMIT;
