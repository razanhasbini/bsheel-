-- ============================================================
-- MIGRATION 0083: Add profile_completed flag to profiles
--
-- Replaces the fragile heuristic of checking username prefix
-- and display_name to determine if a user completed onboarding.
-- ============================================================

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS profile_completed boolean NOT NULL DEFAULT false;

-- Mark all existing users with real usernames as completed
UPDATE public.profiles
SET profile_completed = true
WHERE username IS NOT NULL
  AND NOT (username LIKE 'user\_%' AND display_name = 'New User');
