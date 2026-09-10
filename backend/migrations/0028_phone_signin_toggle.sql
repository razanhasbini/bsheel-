BEGIN;

-- Client-visible switch for the "CONTINUE WITH PHONE NUMBER" button (issue
-- #1), same shape as social_login_enabled from migration 0014. is_public =
-- true deliberately: unlike agent_submission_verification_enabled (an
-- internal ops flag), the mobile app needs to read this one to decide
-- whether to render the button at all. Defaults to off so the button does
-- not appear before PHONE_SIGNIN_ENABLED and the Nokia URLs are actually
-- configured on the backend.
INSERT INTO app_config (key, value, description, is_public) VALUES
  ('phone_signin_enabled', '"false"'::jsonb,
   'Show "Continue with phone number" in the app. Requires PHONE_SIGNIN_ENABLED plus the Nokia Number Verification URLs configured on the backend to actually work — this flag does not turn those on.',
   true)
ON CONFLICT (key) DO NOTHING;

COMMIT;
