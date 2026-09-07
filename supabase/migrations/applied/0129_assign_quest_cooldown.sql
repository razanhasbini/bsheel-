-- ============================================================
-- MIGRATION 0129: 30-second cooldown on quest assignment (SEC-025).
--
-- assign_random_quest / assign_specific_quest have no rate limit, so a
-- scripted client can repeatedly assign → check XP → expire → assign
-- until they hit a high-XP quest, then submit it. That gacha-roll
-- pattern is the missing half of SEC-004's reroll cap.
--
-- Implemented as a BEFORE INSERT trigger on user_quests so it covers
-- every assignment path uniformly (random, specific, picker,
-- injection) without rewriting any of the assign_* RPCs.
-- ============================================================

CREATE OR REPLACE FUNCTION public.enforce_assign_quest_cooldown()
RETURNS trigger AS $$
DECLARE
  v_recent_at timestamptz;
  v_cooldown   interval := interval '30 seconds';
BEGIN
  -- Admins, service-role, and cascaded internal updates bypass.
  IF auth.uid() IS NULL OR public.is_admin() OR pg_trigger_depth() > 1 THEN
    RETURN new;
  END IF;

  SELECT max(assigned_at) INTO v_recent_at
    FROM public.user_quests
    WHERE user_id = new.user_id;

  IF v_recent_at IS NOT NULL AND now() - v_recent_at < v_cooldown THEN
    RAISE EXCEPTION 'Quest assignment cooldown — try again in a moment'
      USING ERRCODE = 'P0001';
  END IF;
  RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_enforce_assign_quest_cooldown ON public.user_quests;
CREATE TRIGGER trg_enforce_assign_quest_cooldown
  BEFORE INSERT ON public.user_quests
  FOR EACH ROW EXECUTE FUNCTION public.enforce_assign_quest_cooldown();

COMMENT ON FUNCTION public.enforce_assign_quest_cooldown() IS
  '30s/user assign cooldown. Blocks the gacha-roll farm flagged in SEC-025. Admins exempt.';
