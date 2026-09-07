-- ============================================================
-- MIGRATION 0058: Fix get_submission_detail visibility (H7)
-- Only return approved submissions to other users.
-- Owner can see their own submission regardless of status.
-- Preserves all columns from migration 0053.
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
  quest_title text,
  quest_description text,
  quest_category text,
  xp_reward integer,
  show_in_feed boolean,
  visibility text
) AS $$
BEGIN
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
      q.title AS quest_title,
      q.description AS quest_description,
      q.category AS quest_category,
      q.xp_reward,
      s.show_in_feed,
      s.visibility
    FROM public.submissions s
    JOIN public.profiles p ON p.id = s.user_id
    JOIN public.user_quests uq ON uq.id = s.user_quest_id
    JOIN public.quests q ON q.id = uq.quest_id
    WHERE s.id = p_submission_id
      AND (s.status = 'approved' OR s.user_id = auth.uid())
    LIMIT 1;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE;
