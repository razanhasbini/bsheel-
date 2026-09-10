BEGIN;

-- CAMARA Geofencing Subscriptions, plus the per-user dynamic quest timer
-- and XP the agent computes from how far a user actually has to travel.

-- One subscription per location-based assignment, created just after the
-- quest is assigned and expiring with it — so entry/exit events only ever
-- count DURING the quest's own window, never before or after it.
CREATE TABLE geofencing_subscriptions (
  id                       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_quest_id            uuid NOT NULL REFERENCES user_quests(id) ON DELETE CASCADE,
  place_id                 uuid NOT NULL REFERENCES map_places(id) ON DELETE CASCADE,
  provider_subscription_id text,
  status                   text NOT NULL DEFAULT 'pending'
                             CHECK (status IN ('pending', 'active', 'failed', 'expired')),
  -- Shared secret echoed back by the provider on every callback; the
  -- webhook rejects anything that doesn't match. Custom callback URLs are
  -- public by nature, so possession of this is what authenticates them.
  callback_secret          text NOT NULL,
  failure_reason           text,
  starts_at                timestamptz NOT NULL,
  expires_at               timestamptz NOT NULL CHECK (expires_at > starts_at),
  created_at               timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX geofencing_subscriptions_user_quest_idx
  ON geofencing_subscriptions (user_quest_id);
CREATE INDEX geofencing_subscriptions_provider_idx
  ON geofencing_subscriptions (provider_subscription_id)
  WHERE provider_subscription_id IS NOT NULL;

CREATE TABLE geofencing_events (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  subscription_id uuid NOT NULL REFERENCES geofencing_subscriptions(id) ON DELETE CASCADE,
  event_type      text NOT NULL CHECK (event_type IN ('ENTER', 'EXIT')),
  occurred_at     timestamptz NOT NULL,
  received_at     timestamptz NOT NULL DEFAULT now(),
  -- Provider event id where supplied, so a redelivered notification is
  -- recorded once rather than counted twice as evidence.
  provider_event_id text
);
CREATE INDEX geofencing_events_subscription_idx
  ON geofencing_events (subscription_id, occurred_at);
CREATE UNIQUE INDEX geofencing_events_provider_id_idx
  ON geofencing_events (subscription_id, provider_event_id)
  WHERE provider_event_id IS NOT NULL;

-- How far this user was from the quest's destination when it was assigned.
-- Measured once, right after assignment, from the network's own view of the
-- device (CAMARA Location Retrieval) — never a client-supplied coordinate.
-- Drives both the timer the agent grants and the XP it later recommends,
-- which is why two users can get different values for the same quest.
ALTER TABLE user_quests ADD COLUMN IF NOT EXISTS assignment_distance_meters double precision
  CHECK (assignment_distance_meters IS NULL OR assignment_distance_meters >= 0);

-- The agent's per-user XP recommendation for this specific submission,
-- written during verification. Approval prefers it when present and falls
-- back to the quest's flat xp_reward when it is null, so an unconfigured
-- or slower-than-the-moderator agent changes nothing.
ALTER TABLE submissions ADD COLUMN IF NOT EXISTS recommended_xp integer
  CHECK (recommended_xp IS NULL OR recommended_xp >= 0);

COMMENT ON TABLE geofencing_subscriptions IS
  'CAMARA Geofencing Subscriptions, scoped to one assignment''s active window so presence only counts during the quest.';
COMMENT ON COLUMN user_quests.assignment_distance_meters IS
  'Network-measured distance from the user to the quest destination at assignment time; drives the per-user timer and XP.';
COMMENT ON COLUMN submissions.recommended_xp IS
  'Agent-recommended XP for this submission, already clamped to policy bounds. Null falls back to quests.xp_reward.';

COMMIT;
