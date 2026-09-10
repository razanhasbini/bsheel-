BEGIN;

-- AI Agent phase, submission-verification slice only. QoS/Emergency Mode is
-- deliberately out of scope (deprioritized). Every table here is additive
-- and inert until AGENT_SUBMISSION_VERIFICATION_ENABLED, OPENAI_AGENT_ENABLED,
-- CAMARA_ENABLED and CV_PROVIDER are turned on — nothing existing changes.
--
-- The agent never mutates submissions/user_quests/profiles itself (see
-- src/modules/agent). These tables are its own audit trail: one row per
-- invocation, plus the normalized evidence that invocation collected.

CREATE TABLE agent_runs (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  kind             text NOT NULL CHECK (kind IN ('quest_time_estimation', 'xp_recommendation', 'submission_verification')),
  subject_type     text NOT NULL CHECK (subject_type IN ('user_quest', 'submission')),
  subject_id       uuid NOT NULL,
  -- Deterministic per (subject, prompt_version) so a retried enqueue can
  -- never start a second run for the same submission and prompt revision.
  idempotency_key  text NOT NULL,
  status           text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'running', 'succeeded', 'failed')),
  model            text NOT NULL,
  prompt_version   text NOT NULL,
  policy_version   text NOT NULL,
  -- The exact AgentContext handed to the model, for audit/replay. Already
  -- scrubbed of anything beyond a user id (see agent.schemas.ts).
  input_snapshot   jsonb NOT NULL,
  output           jsonb,
  error_code       text,
  error_message    text,
  started_at       timestamptz,
  completed_at     timestamptz,
  created_at       timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX agent_runs_idempotency_key_idx ON agent_runs (idempotency_key);
CREATE INDEX agent_runs_subject_idx ON agent_runs (subject_type, subject_id, created_at DESC);

-- Normalized CAMARA (or other network) evidence for one run. Bound to the
-- assignment and, for submission verification, the submission it supports.
-- This is deliberately separate from map_location_evidence (migration
-- 0022), which is pre-assignment destination-unlock evidence with only
-- three aggregate booleans and no submission binding — not sufficient
-- evidence for a post-hoc submission decision.
CREATE TABLE network_evidence (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  agent_run_id        uuid NOT NULL REFERENCES agent_runs(id) ON DELETE CASCADE,
  user_quest_id       uuid NOT NULL REFERENCES user_quests(id) ON DELETE CASCADE,
  submission_id       uuid NOT NULL REFERENCES submissions(id) ON DELETE CASCADE,
  capability          text NOT NULL CHECK (capability IN ('LOCATION_VERIFICATION', 'LOCATION_RETRIEVAL', 'GEOFENCING', 'ADDITIONAL')),
  provider            text NOT NULL,
  provider_reference  text NOT NULL,
  outcome             text NOT NULL CHECK (outcome IN ('SUPPORTED', 'CONTRADICTED', 'UNAVAILABLE', 'ERROR')),
  result              jsonb NOT NULL DEFAULT '{}'::jsonb,
  observed_at         timestamptz NOT NULL,
  valid_until         timestamptz,
  created_at          timestamptz NOT NULL DEFAULT now()
);
-- Guards against storing the same provider evidence twice on a retried run;
-- a fresh attempt (disabled/unavailable included) always carries a fresh
-- provider_reference, so this never blocks a legitimate re-check.
CREATE UNIQUE INDEX network_evidence_provider_ref_idx ON network_evidence (provider, capability, provider_reference);
CREATE INDEX network_evidence_user_quest_idx ON network_evidence (user_quest_id);
CREATE INDEX network_evidence_submission_idx ON network_evidence (submission_id);

-- Normalized computer-vision analysis of one submission's media, produced by
-- a replaceable CvEvidenceProvider (see src/integrations/computer-vision).
CREATE TABLE cv_evidence (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  agent_run_id   uuid NOT NULL REFERENCES agent_runs(id) ON DELETE CASCADE,
  submission_id  uuid NOT NULL REFERENCES submissions(id) ON DELETE CASCADE,
  provider       text NOT NULL,
  model_version  text NOT NULL,
  status         text NOT NULL CHECK (status IN ('AVAILABLE', 'UNAVAILABLE', 'FAILED')),
  result         jsonb NOT NULL DEFAULT '{}'::jsonb,
  analyzed_at    timestamptz NOT NULL,
  created_at     timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX cv_evidence_submission_idx ON cv_evidence (submission_id);

-- Optional machine-readable proof requirements an admin can attach to a
-- quest (required actions/objects/people/items, accepted media). Free-text
-- description remains the source of truth when this is null; nothing reads
-- this column yet outside the agent's context assembly.
ALTER TABLE quests ADD COLUMN IF NOT EXISTS verification_requirements jsonb;
ALTER TABLE quests DROP CONSTRAINT IF EXISTS quests_verification_requirements_is_object;
ALTER TABLE quests ADD CONSTRAINT quests_verification_requirements_is_object
  CHECK (verification_requirements IS NULL OR jsonb_typeof(verification_requirements) = 'object');

COMMENT ON TABLE agent_runs IS 'One row per AI agent invocation (quest time, XP, or submission verification). Audit trail only; the agent never mutates domain tables directly.';
COMMENT ON TABLE network_evidence IS 'Normalized CAMARA evidence collected for one agent run, bound to the assignment and submission it verified.';
COMMENT ON TABLE cv_evidence IS 'Normalized computer-vision analysis of one submission''s media.';
COMMENT ON COLUMN quests.verification_requirements IS 'Optional structured proof requirements the agent checks submissions against. Null = no structured requirement beyond the free-text description.';

COMMIT;
