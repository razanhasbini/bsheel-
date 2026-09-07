-- ============================================================
-- MIGRATION 0079: Fix injection RPC return shape + drop the
-- auto-notification from inject_quest_for_user.
--
-- * get_pending_injection now returns SETOF quests so the
--   postgrest client always sees a list (empty or 1 row). The
--   previous RETURNS public.quests came back as a single JSON
--   object which the mobile client was failing to parse.
-- * inject_quest_for_user no longer inserts a notification —
--   admins don't want the user tipped off.
-- ============================================================

DROP FUNCTION IF EXISTS public.get_pending_injection();

CREATE OR REPLACE FUNCTION public.get_pending_injection()
RETURNS SETOF public.quests AS $$
  SELECT q.*
  FROM public.admin_quest_injections i
  JOIN public.quests q ON q.id = i.quest_id
  WHERE i.target_user_id = auth.uid()
    AND i.consumed_at IS NULL
  ORDER BY i.created_at ASC
  LIMIT 1;
$$ LANGUAGE sql SECURITY DEFINER STABLE;

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
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.admins WHERE user_id = v_admin_id) THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;

  INSERT INTO public.quests (
    title, description, category, difficulty,
    xp_reward, duration_hours, is_active, created_by
  )
  VALUES (
    p_title, p_description, p_category, p_difficulty,
    p_xp_reward, p_duration_hours, true, v_admin_id
  )
  RETURNING * INTO v_quest;

  INSERT INTO public.admin_quest_injections (
    target_user_id, quest_id, created_by
  )
  VALUES (p_target_user_id, v_quest.id, v_admin_id);

  RETURN v_quest;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
