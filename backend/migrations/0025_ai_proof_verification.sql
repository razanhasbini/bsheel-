BEGIN;

-- AI proof verification (#47). The agent analyses submitted proof and records
-- a verdict; when it cannot decide, the submission is escalated to the
-- committee, who resolve it from an "unclear" queue in the admin panel.
--
-- Two decisions shape this table, and both are deliberate.
--
-- 1. `submission_status` is NOT extended.
--
--    It is an enum (pending | approved | rejected) that the highest-risk
--    invariants in CLAUDE.md branch on: one-assigned-quest-per-user, XP
--    awarded exactly once, the one-time appeal guard, the home hero zone and
--    the quest-history grouping. Adding a fourth value would touch every one
--    of those, and their integration tests, to express something that is not
--    a review state at all — it is what a machine thinks of the proof.
--
--    So the verdict lives beside the submission, which stays `pending` until
--    a human decides. "Unclear" is a property of the verdict, not of the
--    review, and the queue is a filter rather than a status.
--
-- 2. The verdict is ADVISORY. Nothing here approves a submission or awards
--    XP. The three mandatory CAMARA signals (#53) do not exist yet, so today
--    a verdict rests on image analysis alone; acting on that automatically
--    would be precisely the "always-successful verification fallback" that
--    docs/design/MAP_REQUIREMENTS.md forbids in production. The columns for
--    those signals are here and nullable so the pipeline does not change
--    shape when #53 lands.

CREATE TYPE proof_verdict AS ENUM ('pass', 'fail', 'unclear');

COMMENT ON TYPE proof_verdict IS
  'AI proof verification (#47): pass = proof supports the quest, fail = it '
  'contradicts it, unclear = the agent could not decide and a human must.';

CREATE TABLE submission_verifications (
  -- One verdict per submission. A re-run replaces it rather than appending,
  -- because the moderator needs the current answer, not a history; the audit
  -- trail for anything acted on lives in admin_audit_log.
  submission_id uuid PRIMARY KEY REFERENCES submissions(id) ON DELETE CASCADE,

  -- 'queued' rows exist so a submission awaiting analysis is distinguishable
  -- from one the agent has never seen, which is what makes the sweep for
  -- missed work possible.
  state text NOT NULL DEFAULT 'queued'
    CHECK (state IN ('queued', 'complete', 'failed', 'skipped')),

  verdict proof_verdict,
  -- Null when the model declines to commit a number. Stored as a fraction so
  -- a threshold can be tuned in config without a migration.
  confidence numeric(4, 3) CHECK (confidence IS NULL OR confidence BETWEEN 0 AND 1),
  -- Shown to the moderator. Bounded because it is rendered in a queue row.
  rationale text NOT NULL DEFAULT '' CHECK (char_length(rationale) <= 4000),
  -- Why a human is needed, when that is the outcome. Distinct from rationale:
  -- one explains the proof, the other explains the escalation.
  escalation_reason text NOT NULL DEFAULT ''
    CHECK (char_length(escalation_reason) <= 500),

  -- Exact model id, so a verdict can be re-read in light of which model
  -- produced it after a model change.
  model text NOT NULL DEFAULT '',

  -- ── CAMARA signals (#53) ────────────────────────────────────────────
  -- Null means "not available", never "false" — an absent signal must not
  -- read as a failed check. Nothing writes these until the adapter exists.
  location_verified  boolean,
  location_retrieved boolean,
  geofence_verified  boolean,

  -- Cost and latency accounting, so the spend is observable from SQL rather
  -- than only from the provider's dashboard.
  input_tokens  integer CHECK (input_tokens IS NULL OR input_tokens >= 0),
  output_tokens integer CHECK (output_tokens IS NULL OR output_tokens >= 0),
  duration_ms   integer CHECK (duration_ms IS NULL OR duration_ms >= 0),

  attempts   integer NOT NULL DEFAULT 0 CHECK (attempts >= 0),
  last_error text CHECK (last_error IS NULL OR char_length(last_error) <= 2000),

  -- Cleared when a human resolves the escalation, so the queue drains.
  resolved_by uuid REFERENCES profiles(id) ON DELETE SET NULL,
  resolved_at timestamptz,

  queued_at    timestamptz NOT NULL DEFAULT now(),
  completed_at timestamptz,

  -- A completed verdict must actually carry one; a queued row must not.
  CONSTRAINT submission_verifications_verdict_state_check CHECK (
    (state = 'complete' AND verdict IS NOT NULL AND completed_at IS NOT NULL)
    OR (state <> 'complete' AND verdict IS NULL)
  ),
  CONSTRAINT submission_verifications_resolution_check CHECK (
    (resolved_by IS NULL AND resolved_at IS NULL)
    OR (resolved_at IS NOT NULL)
  )
);

COMMENT ON TABLE submission_verifications IS
  'AI proof verification (#47). Advisory only — never approves a submission '
  'or awards XP. CAMARA signal columns stay null until #53 lands.';

-- The committee's queue: unresolved escalations, oldest first. Partial so it
-- stays small however many submissions have been verified — the queue is
-- what is unresolved, not what was ever unclear.
CREATE INDEX submission_verifications_unclear_idx
  ON submission_verifications (queued_at)
  WHERE state = 'complete' AND verdict = 'unclear' AND resolved_at IS NULL;

COMMENT ON INDEX submission_verifications_unclear_idx IS
  'The "unclear" section (#47): escalations still awaiting a human decision.';

-- Finds work the agent has not finished: fresh rows to analyse and failures
-- worth retrying. Drives the catch-up sweep, so a worker that died mid-batch
-- does not leave a submission unanalysed forever.
CREATE INDEX submission_verifications_pending_idx
  ON submission_verifications (queued_at)
  WHERE state IN ('queued', 'failed');

COMMIT;
