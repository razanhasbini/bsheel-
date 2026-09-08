-- Seed the client-visible app_config keys.
--
-- `GET /config` returns only rows with is_public = true, and the mobile app
-- treats an absent key as "off". Without these rows every client-side gate
-- was inert: the social-login kill switch could never be thrown, maintenance
-- mode could not be announced, and the force-update lever had nothing to
-- read — the app honours update_required_min_build / _force / _message but
-- no row ever existed to set.
--
-- Values are jsonb strings so the client's scalar normalisation yields the
-- same shape for every key. Defaults are deliberately inert: social login on,
-- maintenance off, no forced update.

BEGIN;

INSERT INTO app_config (key, value, description, is_public) VALUES
  ('social_login_enabled', '"true"'::jsonb,
   'Show Apple/Google sign-in buttons. Set to "false" to hide them without shipping a build.',
   true),
  ('maintenance_mode', '"false"'::jsonb,
   'Show the full-screen maintenance blocker in the mobile app.',
   true),
  ('maintenance_message', '""'::jsonb,
   'Optional custom copy for the maintenance screen. Empty falls back to the built-in text.',
   true),
  ('update_required_min_build', '"0"'::jsonb,
   'Minimum accepted build number. Builds below this see the update prompt. 0 disables the gate.',
   true),
  ('update_required_force', '"false"'::jsonb,
   'When "true" the update prompt cannot be dismissed.',
   true),
  ('update_required_message', '""'::jsonb,
   'Optional custom copy for the update prompt.',
   true)
ON CONFLICT (key) DO NOTHING;

COMMIT;
