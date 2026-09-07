-- ============================================================
-- MIGRATION 0124: Quest reroll cooldown — server-side rate limit
-- (SEC-004, ARC-013).
--
-- The "5 rerolls per 24h" rule is enforced client-side only via
-- SharedPreferences. Reinstall / clear data resets the budget; a
-- scripted client (or a different device) bypasses it entirely. This
-- enables XP farming via repeated low-XP-quest assign → expire →
-- assign cycles.
--
-- Solution: a tiny `quest_reroll_log` table + a `record_quest_reroll`
-- RPC that the client must call (and that enforces the same 5-per-24h
-- ceiling that the UI advertises). The repository was already
-- updated to call this; previously the call was a no-op stub.
-- ============================================================

CREATE TABLE IF NOT EXISTS public.quest_reroll_log (
  id           bigserial PRIMARY KEY,
  user_id      uuid        NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  rerolled_at  timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_quest_reroll_log_user_time
  ON public.quest_reroll_log (user_id, rerolled_at DESC);

ALTER TABLE public.quest_reroll_log ENABLE ROW LEVEL SECURITY;

-- Read your own reroll history (the UI uses this for the X/5 chip).
DROP POLICY IF EXISTS quest_reroll_log_select_own ON public.quest_reroll_log;
CREATE POLICY quest_reroll_log_select_own ON public.quest_reroll_log
  FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR public.is_admin());

-- Writes only via the SECURITY DEFINER RPC below.

-- ── record_quest_reroll ─────────────────────────────────────────
-- Returns the number of rerolls remaining in the rolling 24h window
-- AFTER recording the new reroll. Throws if the cap is exceeded.
CREATE OR REPLACE FUNCTION public.record_quest_reroll()
RETURNS integer AS $$
DECLARE
  v_used      integer;
  v_max       integer := 5;
  v_window    interval := interval '24 hours';
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '42501';
  END IF;
  IF NOT public.is_account_active() THEN
    RAISE EXCEPTION 'Account not active' USING ERRCODE = '42501';
  END IF;

  SELECT count(*) INTO v_used
    FROM public.quest_reroll_log
    WHERE user_id = auth.uid()
      AND rerolled_at > now() - v_window;

  IF v_used >= v_max THEN
    RAISE EXCEPTION 'Reroll limit reached (% per 24h)', v_max
      USING ERRCODE = 'P0001';
  END IF;

  INSERT INTO public.quest_reroll_log (user_id) VALUES (auth.uid());
  RETURN v_max - (v_used + 1);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

REVOKE EXECUTE ON FUNCTION public.record_quest_reroll() FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.record_quest_reroll() TO authenticated;

-- ── get_quest_rerolls_remaining ─────────────────────────────────
-- Read-only helper for the UI to populate the X/5 chip on cold start.
CREATE OR REPLACE FUNCTION public.get_quest_rerolls_remaining()
RETURNS integer AS $$
DECLARE
  v_used integer;
  v_max  integer := 5;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN v_max;
  END IF;
  SELECT count(*) INTO v_used
    FROM public.quest_reroll_log
    WHERE user_id = auth.uid()
      AND rerolled_at > now() - interval '24 hours';
  RETURN GREATEST(0, v_max - v_used);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE;

REVOKE EXECUTE ON FUNCTION public.get_quest_rerolls_remaining() FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.get_quest_rerolls_remaining() TO authenticated;
