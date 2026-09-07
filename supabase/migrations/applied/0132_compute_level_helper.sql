-- ============================================================
-- MIGRATION 0132: Single canonical level formula (ARC-016).
--
-- The same `GREATEST(1, x / 100 + 1)` expression is hand-written in
-- migrations 0054 (XP grant trigger), 0110 (XP revoke on post delete +
-- recompute), and 0113 (level fix + recompute). Three call sites means
-- three places to remember if product changes the curve.
--
-- Lift it into a tiny IMMUTABLE function and rewrite every callsite
-- to use it. The formula is unchanged so deployed users see no
-- behaviour change.
-- ============================================================

CREATE OR REPLACE FUNCTION public.compute_level(p_xp integer)
RETURNS integer
LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
  SELECT greatest(1, greatest(0, coalesce(p_xp, 0)) / 100 + 1);
$$;

GRANT EXECUTE ON FUNCTION public.compute_level(integer) TO anon, authenticated, service_role;

COMMENT ON FUNCTION public.compute_level(integer) IS
  'Single source of truth for XP→level mapping. ARC-016. '
  'Floor at 1, integer-divide XP by 100, add 1. '
  'Negative or null XP coerces to 0 first so revoke paths don''t go below level 1.';

-- Note: existing triggers/RPCs in 0054, 0110, 0113 still ship the
-- inline formula. Future redefinitions should use compute_level()
-- instead. Replacing the existing functions in-place is a separate
-- migration once we're sure no in-flight transactions are mid-update.
