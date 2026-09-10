BEGIN;

-- Runtime, admin-toggleable pause switch for the AI submission-verification
-- pipeline, so it can be paused/resumed from the admin dashboard without an
-- env change and a restart. AGENT_SUBMISSION_VERIFICATION_ENABLED (env)
-- stays the deploy-time gate — is the pipeline allowed to run on this
-- environment at all. This row is the day-to-day product lever on top of
-- that: both must be true for verification to actually run.
--
-- is_public = false deliberately: this is an internal ops flag, not
-- something the mobile client reads, unlike social_login_enabled/
-- maintenance_mode from migration 0014.
INSERT INTO app_config (key, value, description, is_public) VALUES
  ('agent_submission_verification_enabled', '"false"'::jsonb,
   'Pause/resume the AI submission-verification pipeline without a deploy. Requires AGENT_SUBMISSION_VERIFICATION_ENABLED=true in the environment to take effect at all.',
   false)
ON CONFLICT (key) DO NOTHING;

COMMIT;
