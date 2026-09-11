BEGIN;

-- A playthrough of a chain (#51). The missing parent state.
--
-- Multi-stage quests were modelled as chains of quests with no record of
-- anybody WALKING one: progress was re-derived by counting user_quests, and
-- there was nowhere to say "this journey is still going". So an approved
-- step left the user with nothing active and no next step, which is exactly
-- how a three-stop journey came to end after one stop.
--
-- The run is that record, and for a relay it is the SHARED instance: three
-- participants cannot hold three conflicting opinions about where the
-- journey is, because there is one row and it belongs to the run.
CREATE TABLE IF NOT EXISTS quest_chain_runs (
  id       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  chain_id uuid NOT NULL REFERENCES quest_chains(id) ON DELETE CASCADE,

  -- A snapshot of quest_chains.mode, not a derivation of it. An admin
  -- editing the chain must not convert a relay already under way into a
  -- solo run; the service asserts these agree when the run is created.
  run_kind text NOT NULL CHECK (run_kind IN ('solo', 'group')),

  -- Solo only. A relay's participants live in the roster table, because a
  -- shared journey has no single owner.
  owner_user_id uuid REFERENCES users(id) ON DELETE CASCADE,

  -- Optional social context. Never the identity of the relay: a
  -- collab_group is bound to one quest_id and cannot own a chain of
  -- different quests, which is why it is nullable and SET NULL here.
  source_collab_group_id uuid REFERENCES collab_groups(id) ON DELETE SET NULL,

  -- Audit context, not lifecycle. Deleting the account that opened a relay
  -- must not delete everyone else's progression with it.
  created_by_user_id uuid REFERENCES users(id) ON DELETE SET NULL,

  -- The code participants use to join, before the roster is finalised.
  join_code citext UNIQUE,

  status text NOT NULL DEFAULT 'forming' CHECK (
    status IN ('forming', 'active', 'completed', 'abandoned', 'expired')
  ),
  started_at   timestamptz,
  completed_at timestamptz,
  created_at   timestamptz NOT NULL DEFAULT now(),
  updated_at   timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT quest_chain_runs_owner_shape CHECK (
    run_kind = 'solo'  AND owner_user_id IS NOT NULL OR
    run_kind = 'group' AND owner_user_id IS NULL
  ),
  CONSTRAINT quest_chain_runs_completed_shape CHECK (
    status =  'completed' AND completed_at IS NOT NULL OR
    status <> 'completed' AND completed_at IS NULL
  ),
  CONSTRAINT quest_chain_runs_started_shape CHECK (
    status = 'forming' AND started_at IS NULL OR
    status <> 'forming' AND started_at IS NOT NULL
  )
);

-- Deliberately NOT storing current_step.
--
-- It cannot be authoritative for both completion rules: a sequential run has
-- a meaningful current step, and an all_steps_any_order run genuinely does
-- not — several checkpoints are open at once by design. A column that is
-- honest for one rule and a lie for the other is worse than deriving it, so
-- progress comes from approved steps and availability comes from
-- journey_stage_unlocks.

-- One active solo run per chain per user. Groups get no such constraint on
-- purpose: the run UUID is the identity, so any number of independent
-- rosters may walk the same chain at the same time.
CREATE UNIQUE INDEX IF NOT EXISTS quest_chain_runs_solo_live_idx
  ON quest_chain_runs (chain_id, owner_user_id)
  WHERE run_kind = 'solo' AND status IN ('forming', 'active');

CREATE INDEX IF NOT EXISTS quest_chain_runs_chain_idx ON quest_chain_runs (chain_id);
CREATE INDEX IF NOT EXISTS quest_chain_runs_live_idx
  ON quest_chain_runs (status) WHERE status IN ('forming', 'active');

COMMENT ON TABLE quest_chain_runs IS
  'One playthrough of a quest chain. For a relay this is the shared journey '
  'instance: the authoritative parent progression, so participants cannot '
  'disagree about where the journey is.';

-- The relay roster. Owned by the run rather than by a collab_group, which
-- cannot host one (collab_groups.quest_id is NOT NULL — a group is several
-- people doing ONE quest, not a baton passing across different quests).
CREATE TABLE IF NOT EXISTS quest_chain_run_participants (
  chain_run_id uuid NOT NULL REFERENCES quest_chain_runs(id) ON DELETE CASCADE,
  user_id      uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  position     integer NOT NULL CHECK (position >= 1),
  joined_at    timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (chain_run_id, position),
  UNIQUE (chain_run_id, user_id)
);

COMMENT ON TABLE quest_chain_run_participants IS
  'Ordered roster of a relay run. Every row is the joiner own authenticated '
  'action — nobody can be conscripted into a relay.';

-- Which participant owns a stage, when round-robin is not the intent.
--
-- Null means round-robin: ((step_order - 1) %% participants) + 1. Set it for
-- an asymmetric relay, a stage bound to a country or a role, or a sequence
-- where the same participant acts twice. Validated against the roster size
-- when the run starts, never discovered midway.
ALTER TABLE quest_chain_steps
  ADD COLUMN IF NOT EXISTS target_position integer
    CHECK (target_position IS NULL OR target_position >= 1);

-- The durable unlock: the authoritative record that a checkpoint opened for
-- somebody, and the thing eligibility reads.
--
-- Scoped to a RUN, which is what stops a user starting stage 3 because
-- stage 2 was approved in an unrelated playthrough — the old derived check
-- only ever asked whether the previous step was approved by anyone.
CREATE TABLE IF NOT EXISTS journey_stage_unlocks (
  chain_run_id   uuid NOT NULL REFERENCES quest_chain_runs(id) ON DELETE CASCADE,
  step_order     integer NOT NULL CHECK (step_order >= 1),
  quest_id       uuid NOT NULL REFERENCES quests(id) ON DELETE CASCADE,
  -- Who may start it. On a relay this is one participant, not the group.
  target_user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  unlocked_at    timestamptz NOT NULL DEFAULT now(),
  -- Cleared once the unlock animation has played, so it plays exactly once
  -- and survives the app being closed when the approval landed.
  seen_at        timestamptz,
  -- When CONTINUE first assigned it. Audit only: it is NOT a gate, because
  -- an expired or rejected stage must stay retryable under the ordinary
  -- rules rather than stranding the journey forever.
  started_at     timestamptz,
  PRIMARY KEY (chain_run_id, step_order, target_user_id)
);

CREATE INDEX IF NOT EXISTS journey_stage_unlocks_quest_user_idx
  ON journey_stage_unlocks (quest_id, target_user_id);
CREATE INDEX IF NOT EXISTS journey_stage_unlocks_unseen_idx
  ON journey_stage_unlocks (target_user_id, unlocked_at DESC) WHERE seen_at IS NULL;

COMMENT ON TABLE journey_stage_unlocks IS
  'A checkpoint opened for one user in one run. The primary key is the '
  'idempotency guarantee: a replayed submission.approved inserts nothing.';

COMMIT;
