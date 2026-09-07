-- ============================================================
-- MIGRATION 0029: Restrict FCM token visibility
-- Moves fcm_token from public.profiles (world-readable) into
-- a private schema table accessible only by service_role.
-- ============================================================

-- Create private schema if it doesn't exist
CREATE SCHEMA IF NOT EXISTS private;

-- Create private tokens table
CREATE TABLE IF NOT EXISTS private.profile_tokens (
  user_id  uuid PRIMARY KEY REFERENCES public.profiles(id) ON DELETE CASCADE,
  fcm_token text
);

-- Move existing tokens
INSERT INTO private.profile_tokens (user_id, fcm_token)
SELECT id, fcm_token
FROM public.profiles
WHERE fcm_token IS NOT NULL
ON CONFLICT (user_id) DO UPDATE SET fcm_token = EXCLUDED.fcm_token;

-- Drop fcm_token from public profiles
ALTER TABLE public.profiles DROP COLUMN IF EXISTS fcm_token;

-- Grant access to service_role only (no public/authenticated access)
REVOKE ALL ON private.profile_tokens FROM PUBLIC, anon, authenticated;
GRANT ALL ON private.profile_tokens TO service_role;
