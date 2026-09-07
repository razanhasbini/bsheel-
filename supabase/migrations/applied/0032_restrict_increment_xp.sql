-- ============================================================
-- MIGRATION 0030: Restrict increment_xp to service_role only
-- Prevents authenticated users from calling increment_xp directly.
-- XP is now only awarded via server-side triggers/functions that
-- run as SECURITY DEFINER (e.g. submission approval trigger).
-- ============================================================

-- Remove execute permission from authenticated users
REVOKE EXECUTE ON FUNCTION public.increment_xp(uuid, integer) FROM authenticated;

-- Ensure only service_role can call it (service_role bypasses REVOKE by default,
-- but explicit grant makes intent clear).
GRANT EXECUTE ON FUNCTION public.increment_xp(uuid, integer) TO service_role;
