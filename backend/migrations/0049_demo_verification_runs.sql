BEGIN;

-- Demo verification runs: real, recorded, and never authoritative.
--
-- The hackathon demo lets an authorised operator pick which Nokia simulator
-- device a verification run asks about, so judges can watch the same proof
-- decided differently as the network evidence changes. The run is real in
-- every respect that matters — real call to Nokia, the stored CV analysis,
-- the same agent, the same deterministic policy — but its decision is NOT
-- applied: no submission status, no XP, no journey, no unlocks, no
-- notifications.
--
-- That leaves one thing to get right in the schema. A demo run must be
-- *visible* to an operator (it belongs in the Agent Evidence history beside
-- the real ones, or the demo is a second implementation nobody can audit)
-- while being *impossible to mistake for a completion*. Those pull in
-- opposite directions, so the answer is a flag rather than a new `kind`:
--
--   * a new `kind` would be filtered out by every existing dossier query,
--     and the demo would vanish from the admin panel — the opposite of what
--     it is for;
--   * a flag leaves those queries working and gives them something explicit
--     to label and, where it matters, to exclude.
--
-- Business analytics cannot see a demo run at all, and not because of this
-- column: completions are counted from `submissions` and `user_quests`,
-- which a demo evaluation never writes to. This column exists so a person
-- reading the evidence knows what they are looking at.
ALTER TABLE agent_runs
  ADD COLUMN IF NOT EXISTS is_demo boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS demo_persona text,
  ADD COLUMN IF NOT EXISTS device_source text;

COMMENT ON COLUMN agent_runs.is_demo IS
  'True for a non-authoritative demo evaluation: real Nokia call, real agent, '
  'real policy, decision deliberately not applied. Never counts as a completion.';
COMMENT ON COLUMN agent_runs.demo_persona IS
  'The Nokia simulator persona id this run asked about, for a demo run.';
COMMENT ON COLUMN agent_runs.device_source IS
  'LIVE_OPERATOR or NOKIA_SIMULATOR — which device CAMARA was asked about. '
  'Recorded so a dossier can never be read as a claim about a real subscriber.';

-- A persona only makes sense on a demo run, and a demo run must name one.
-- Without this a row could claim to be a real verification while carrying a
-- simulator persona, which is precisely the confusion this table is meant to
-- make impossible.
ALTER TABLE agent_runs DROP CONSTRAINT IF EXISTS agent_runs_demo_persona_check;
ALTER TABLE agent_runs ADD CONSTRAINT agent_runs_demo_persona_check
  CHECK ((is_demo AND demo_persona IS NOT NULL) OR (NOT is_demo AND demo_persona IS NULL));

ALTER TABLE agent_runs DROP CONSTRAINT IF EXISTS agent_runs_device_source_check;
ALTER TABLE agent_runs ADD CONSTRAINT agent_runs_device_source_check
  CHECK (device_source IS NULL OR device_source IN ('LIVE_OPERATOR', 'NOKIA_SIMULATOR'));

-- The late-evidence recovery sweep looks for runs whose geofence answer has
-- since improved. A demo run must never be picked up by it: re-running one
-- would spend Nokia and model calls on an evaluation nobody asked for, and
-- would do it under a persona chosen minutes ago for a different point.
CREATE INDEX IF NOT EXISTS agent_runs_authoritative_idx
  ON agent_runs (kind, subject_id) WHERE NOT is_demo;

COMMIT;
