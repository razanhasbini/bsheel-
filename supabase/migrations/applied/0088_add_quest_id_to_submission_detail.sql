-- ============================================================
-- MIGRATION 0088: Add quest_id to get_submission_detail RPC
-- Needed so the BSHEEEL feature can assign the quest from a
-- feed post detail view.
-- ============================================================

DROP FUNCTION IF EXISTS public.get_submission_detail(uuid);

CREATE OR REPLACE FUNCTION public.get_submission_detail(p_submission_id uuid)
RETURNS TABLE (
  submission_id uuid,
  media_url text,
  media_type text,
  caption text,
  submitted_at timestamptz,
  user_id uuid,
  username text,
  display_name text,
  avatar_url text,
  bio text,
  quest_id uuid,
  quest_title text,
  quest_description text,
  quest_category text,
  xp_reward integer,
  show_in_feed boolean,
  visibility text,
  is_collab boolean,
  collab_group_id uuid,
  collab_mode text,
  collab_member_count bigint,
  collab_members json
) AS $$
DECLARE
  v_group_id uuid;
  v_leader_submission_id uuid;
BEGIN
  SELECT gm.group_id INTO v_group_id
  FROM public.submissions s
  JOIN public.collab_group_members gm ON gm.user_quest_id = s.user_quest_id
  WHERE s.id = p_submission_id
  LIMIT 1;

  IF v_group_id IS NOT NULL THEN
    SELECT ms.id INTO v_leader_submission_id
    FROM public.collab_groups g
    JOIN public.collab_group_members gm
      ON gm.group_id = g.id AND gm.user_id = g.creator_id
    JOIN public.submissions ms ON ms.user_quest_id = gm.user_quest_id
    WHERE g.id = v_group_id
    LIMIT 1;
  END IF;

  RETURN QUERY
    SELECT
      s.id AS submission_id,
      s.media_url,
      s.media_type,
      s.caption,
      s.submitted_at,
      p.id AS user_id,
      p.username,
      p.display_name,
      p.avatar_url,
      p.bio,
      q.id AS quest_id,
      q.title AS quest_title,
      q.description AS quest_description,
      q.category AS quest_category,
      q.xp_reward,
      s.show_in_feed,
      s.visibility,
      (gm.group_id IS NOT NULL) AS is_collab,
      gm.group_id AS collab_group_id,
      g.mode AS collab_mode,
      COALESCE(mc.cnt, 0)::bigint AS collab_member_count,
      CASE WHEN gm.group_id IS NOT NULL THEN (
        SELECT json_agg(json_build_object(
          'user_id', mp.id,
          'username', mp.username,
          'display_name', mp.display_name,
          'avatar_url', mp.avatar_url,
          'bio', mp.bio,
          'submission_id', ms.id,
          'media_url', ms.media_url,
          'media_type', ms.media_type,
          'submission_status', ms.status,
          'caption', ms.caption,
          'show_in_feed', ms.show_in_feed,
          'vote_count', COALESCE(vc.cnt, 0)
        ) ORDER BY m2.joined_at)
        FROM public.collab_group_members m2
        JOIN public.profiles mp ON mp.id = m2.user_id
        LEFT JOIN public.submissions ms ON ms.user_quest_id = m2.user_quest_id
        LEFT JOIN (
          SELECT cv.submission_id AS sid, count(*) AS cnt
          FROM public.collab_votes cv
          WHERE cv.group_id = gm.group_id
          GROUP BY cv.submission_id
        ) vc ON vc.sid = ms.id
        WHERE m2.group_id = gm.group_id
      ) ELSE NULL END AS collab_members
    FROM public.submissions s
    JOIN public.profiles p ON p.id = s.user_id
    JOIN public.user_quests uq ON uq.id = s.user_quest_id
    JOIN public.quests q ON q.id = uq.quest_id
    LEFT JOIN public.collab_group_members gm ON gm.user_quest_id = uq.id
    LEFT JOIN public.collab_groups g ON g.id = gm.group_id
    LEFT JOIN (
      SELECT group_id, count(*) AS cnt
      FROM public.collab_group_members GROUP BY group_id
    ) mc ON mc.group_id = gm.group_id
    WHERE s.id = COALESCE(v_leader_submission_id, p_submission_id)
      AND (s.status = 'approved' OR s.user_id = auth.uid())
    LIMIT 1;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE;
