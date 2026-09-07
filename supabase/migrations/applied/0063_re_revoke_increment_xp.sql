-- ============================================================
-- MIGRATION 0063: Re-apply increment_xp REVOKE (New Critical)
-- Migration 0032 exists but was never applied to live DB.
-- This ensures it is applied regardless of migration state.
-- ============================================================

REVOKE EXECUTE ON FUNCTION public.increment_xp(uuid, integer) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.increment_xp(uuid, integer) TO service_role;
