BEGIN;

-- The agent decides by default.
--
-- 0026 added this row as a pause switch and seeded it false, on the same
-- reasoning 0034 used for `may_auto_reject`: authority should be earned from
-- a measured number rather than asserted in a migration. Both halves of that
-- have now been settled the other way. 0046 granted rejection authority for
-- the categories where the media can actually answer the question, and the
-- deployment default is no longer shadow mode — automated verification is
-- how this product reviews proof, not an experiment running beside it.
--
-- Leaving this row false would mean a deployment that has turned everything
-- else on still reviews nothing, and the only signal would be submissions
-- quietly piling up in the human queue carrying a verdict the system had
-- already reached. That is the failure this flips.
--
-- What this does NOT change, because it is the safety and it is elsewhere:
--
--   * AGENT_SUBMISSION_VERIFICATION_ENABLED (env) is still the deploy-time
--     gate; both must be true for the pipeline to run at all.
--   * A rejection still requires a positive statement from the network or
--     the media. UNAVAILABLE evidence goes to a human, never to a reject.
--   * `may_auto_reject` is still false for provenance_only and none.
--   * An integrity finding still blocks an automated approval outright.
--
-- Still a pause switch: Settings -> AI SUBMISSION VERIFICATION turns it off
-- without a deploy, and that remains the lever to reach for if the agent
-- starts getting things wrong.
UPDATE app_config
   SET value = 'true'::jsonb,
       description = 'Pause/resume the AI submission-verification pipeline without a deploy. On by default since 0048. Requires AGENT_SUBMISSION_VERIFICATION_ENABLED=true in the environment to take effect at all.'
 WHERE key = 'agent_submission_verification_enabled';

-- A database that never ran 0026 (none should exist, but the insert is
-- cheap and makes this migration total rather than conditional on history).
INSERT INTO app_config (key, value, description, is_public) VALUES
  ('agent_submission_verification_enabled', 'true'::jsonb,
   'Pause/resume the AI submission-verification pipeline without a deploy. On by default since 0048. Requires AGENT_SUBMISSION_VERIFICATION_ENABLED=true in the environment to take effect at all.',
   false)
ON CONFLICT (key) DO NOTHING;

COMMIT;
