-- ============================================================
-- MIGRATION 0112: INJECT feature audit fixes
--
-- Audit findings addressed here (paired with admin_web changes):
--   1. Restore 0079's intent: do NOT tip the user off when an
--      admin injects a quest. 0099 accidentally re-added the
--      "A quest awaits" push during a refactor for input
--      validation. The injected quest is supposed to surface
--      silently the next time the user rolls.
--   2. Drop dead functions get_pending_injection() and
--      consume_injection(uuid). Migration 0109 replaced them with
--      get_quest_picker_options(), which atomically pops + marks
--      consumed. No client calls them anymore.
--
-- Audit log + input bounds from 0099 are kept.
-- ============================================================

DROP FUNCTION IF EXISTS public.inject_quest_for_user(uuid, text, text, text, text, integer, integer);

CREATE OR REPLACE FUNCTION public.inject_quest_for_user(
  p_target_user_id uuid,
  p_title text,
  p_description text,
  p_category text,
  p_difficulty text,
  p_xp_reward integer,
  p_duration_hours integer
)
RETURNS public.quests AS $$
DECLARE
  v_admin_id uuid := auth.uid();
  v_quest public.quests;
  v_title text := coalesce(trim(p_title), '');
  v_desc  text := coalesce(trim(p_description), '');
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.admins WHERE user_id = v_admin_id) THEN
    RAISE EXCEPTION 'Not authorized' USING ERRCODE = '42501';
  END IF;

  IF p_xp_reward IS NULL OR p_xp_reward < 5 OR p_xp_reward > 1000 THEN
    RAISE EXCEPTION 'xp_reward must be between 5 and 1000 (got %)', p_xp_reward
      USING ERRCODE = '23514';
  END IF;
  IF p_duration_hours IS NULL OR p_duration_hours < 1 OR p_duration_hours > 168 THEN
    RAISE EXCEPTION 'duration_hours must be between 1 and 168 (got %)', p_duration_hours
      USING ERRCODE = '23514';
  END IF;
  IF p_difficulty IS NULL OR lower(p_difficulty) NOT IN ('easy', 'medium', 'hard') THEN
    RAISE EXCEPTION 'difficulty must be one of easy/medium/hard (got %)', p_difficulty
      USING ERRCODE = '23514';
  END IF;
  IF v_title = '' OR length(v_title) > 100 THEN
    RAISE EXCEPTION 'title must be 1..100 chars' USING ERRCODE = '23514';
  END IF;
  IF v_desc = '' OR length(v_desc) > 500 THEN
    RAISE EXCEPTION 'description must be 1..500 chars' USING ERRCODE = '23514';
  END IF;

  INSERT INTO public.quests (
    title, description, category, difficulty,
    xp_reward, duration_hours, is_active, created_by
  )
  VALUES (
    v_title, v_desc, p_category, lower(p_difficulty),
    p_xp_reward, p_duration_hours, true, v_admin_id
  )
  RETURNING * INTO v_quest;

  INSERT INTO public.admin_quest_injections (target_user_id, quest_id, created_by)
  VALUES (p_target_user_id, v_quest.id, v_admin_id);

  -- Notification intentionally omitted (0079 + this migration). Admins do
  -- not want the user tipped off; the quest surfaces on their next roll.

  PERFORM public.log_admin_action(
    'quest.inject',
    'user',
    p_target_user_id::text,
    jsonb_build_object(
      'quest_id', v_quest.id,
      'xp_reward', p_xp_reward,
      'difficulty', lower(p_difficulty),
      'duration_hours', p_duration_hours
    )
  );

  RETURN v_quest;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP FUNCTION IF EXISTS public.get_pending_injection();
DROP FUNCTION IF EXISTS public.consume_injection(uuid);

-- ============================================================
-- 3. Drop the legacy 5-100 CHECK on quests.xp_reward
--
-- 0002 created `xp_reward_range` (5-100). 0099 layered on
-- `quests_xp_reward_range` (5-1000) intending to widen the cap,
-- but never dropped the original — so inserts above 100 still
-- failed and the inject RPC's 5-1000 validation was unreachable.
-- ============================================================
ALTER TABLE public.quests DROP CONSTRAINT IF EXISTS xp_reward_range;

