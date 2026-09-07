-- ============================================================
-- MIGRATION 0138: get_following_active_quests
--
-- Powers the "WHAT EVERYONE IS DOING" strip on the home page when
-- it needs to show who's *currently doing* a quest (status =
-- 'assigned', not yet submitted) rather than only past completions.
--
-- The query is scoped to people the caller follows when there's at
-- least one followed user with an active quest, and falls back to a
-- global view of the most-recently-assigned active questers when
-- the caller follows nobody / nobody they follow is currently active.
-- This keeps the strip useful even for fresh accounts.
--
-- Read-only, security definer so it can see all follows + quests
-- without exposing the underlying rows beyond what we already
-- expose in the feed.
-- ============================================================

DROP FUNCTION IF EXISTS public.get_following_active_quests(integer);

CREATE OR REPLACE FUNCTION public.get_following_active_quests(
  p_limit integer DEFAULT 12
)
RETURNS TABLE (
  user_quest_id uuid,
  user_id       uuid,
  username      text,
  display_name  text,
  avatar_url    text,
  quest_id      uuid,
  quest_title   text,
  quest_category text,
  xp_reward     integer,
  assigned_at   timestamptz,
  expires_at    timestamptz
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_viewer uuid := auth.uid();
  v_limit  integer := LEAST(GREATEST(COALESCE(p_limit, 12), 1), 40);
  v_following_count integer := 0;
BEGIN
  IF v_viewer IS NULL THEN
    RETURN;
  END IF;

  -- Prefer followed users when there's anything to show there.
  SELECT count(*) INTO v_following_count
  FROM public.user_quests uq
  JOIN public.follows f
    ON f.following_id = uq.user_id
   AND f.follower_id  = v_viewer
  WHERE uq.status = 'assigned'
    AND uq.expires_at > now()
    AND uq.user_id <> v_viewer;

  IF v_following_count > 0 THEN
    RETURN QUERY
      SELECT
        uq.id,
        uq.user_id,
        p.username,
        p.display_name,
        p.avatar_url,
        q.id,
        q.title,
        q.category,
        q.xp_reward,
        uq.assigned_at,
        uq.expires_at
      FROM public.user_quests uq
      JOIN public.follows f
        ON f.following_id = uq.user_id
       AND f.follower_id  = v_viewer
      JOIN public.profiles p ON p.id = uq.user_id
      JOIN public.quests   q ON q.id = uq.quest_id
      WHERE uq.status = 'assigned'
        AND uq.expires_at > now()
        AND uq.user_id <> v_viewer
      ORDER BY uq.assigned_at DESC
      LIMIT v_limit;
    RETURN;
  END IF;

  -- Fallback: any user currently questing (excluding the viewer).
  RETURN QUERY
    SELECT
      uq.id,
      uq.user_id,
      p.username,
      p.display_name,
      p.avatar_url,
      q.id,
      q.title,
      q.category,
      q.xp_reward,
      uq.assigned_at,
      uq.expires_at
    FROM public.user_quests uq
    JOIN public.profiles p ON p.id = uq.user_id
    JOIN public.quests   q ON q.id = uq.quest_id
    WHERE uq.status = 'assigned'
      AND uq.expires_at > now()
      AND uq.user_id <> v_viewer
    ORDER BY uq.assigned_at DESC
    LIMIT v_limit;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_following_active_quests(integer) TO authenticated;

COMMENT ON FUNCTION public.get_following_active_quests(integer) IS
  'Returns up to N users currently mid-quest (status=assigned), preferring users the caller follows. Powers the home-page "doing now" strip.';
