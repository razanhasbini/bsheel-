-- ============================================================
-- MIGRATION 0069: Content Moderation (Apple Guideline 1.2)
-- Adds: reports table, blocked_users table, EULA acceptance,
-- RPCs for reporting, blocking, and admin moderation.
-- ============================================================

-- ── 1. EULA acceptance tracking ─────────────────────────────
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS accepted_terms_at timestamptz;

-- ── 2. Content Reports ──────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.reports (
  id            uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  reporter_id   uuid        NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  reported_type text        NOT NULL CHECK (reported_type IN ('submission', 'comment', 'user')),
  reported_id   text        NOT NULL,  -- UUID of the submission, comment, or user
  reason        text        NOT NULL CHECK (char_length(reason) BETWEEN 1 AND 500),
  status        text        NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'reviewed', 'actioned', 'dismissed')),
  admin_note    text,
  created_at    timestamptz NOT NULL DEFAULT now(),
  reviewed_at   timestamptz,
  reviewed_by   uuid        REFERENCES public.profiles(id)
);

ALTER TABLE public.reports ENABLE ROW LEVEL SECURITY;

-- Users can see their own reports
CREATE POLICY "reports_select_own" ON public.reports
  FOR SELECT USING (reporter_id = auth.uid());

-- Users can insert their own reports
CREATE POLICY "reports_insert_own" ON public.reports
  FOR INSERT WITH CHECK (reporter_id = auth.uid());

-- Admins can see and update all reports
CREATE POLICY "reports_select_admin" ON public.reports
  FOR SELECT USING (public.is_admin());

CREATE POLICY "reports_update_admin" ON public.reports
  FOR UPDATE USING (public.is_admin());

-- ── 3. Blocked Users ────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.blocked_users (
  id            uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  blocker_id    uuid        NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  blocked_id    uuid        NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  created_at    timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT unique_block UNIQUE (blocker_id, blocked_id),
  CONSTRAINT no_self_block CHECK (blocker_id != blocked_id)
);

ALTER TABLE public.blocked_users ENABLE ROW LEVEL SECURITY;

-- Users can see their own blocks
CREATE POLICY "blocked_users_select_own" ON public.blocked_users
  FOR SELECT USING (blocker_id = auth.uid());

-- Users can insert their own blocks
CREATE POLICY "blocked_users_insert_own" ON public.blocked_users
  FOR INSERT WITH CHECK (blocker_id = auth.uid());

-- Users can delete their own blocks (unblock)
CREATE POLICY "blocked_users_delete_own" ON public.blocked_users
  FOR DELETE USING (blocker_id = auth.uid());

-- Admins can see all blocks
CREATE POLICY "blocked_users_select_admin" ON public.blocked_users
  FOR SELECT USING (public.is_admin());

-- ── 4. RPCs ─────────────────────────────────────────────────

-- Accept EULA/Terms
CREATE OR REPLACE FUNCTION public.accept_terms()
RETURNS void AS $$
BEGIN
  UPDATE public.profiles
    SET accepted_terms_at = now()
    WHERE id = auth.uid();
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Report content
CREATE OR REPLACE FUNCTION public.report_content(
  p_reported_type text,
  p_reported_id   text,
  p_reason        text
)
RETURNS uuid AS $$
DECLARE
  v_id uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  -- Prevent duplicate reports from same user on same item
  IF EXISTS (
    SELECT 1 FROM public.reports
    WHERE reporter_id = auth.uid()
      AND reported_type = p_reported_type
      AND reported_id = p_reported_id
      AND status = 'pending'
  ) THEN
    RAISE EXCEPTION 'You have already reported this content';
  END IF;

  INSERT INTO public.reports (reporter_id, reported_type, reported_id, reason)
  VALUES (auth.uid(), p_reported_type, p_reported_id, p_reason)
  RETURNING id INTO v_id;

  -- Notify all admins about the new report
  INSERT INTO public.notifications (user_id, title, body, type, reference_id)
  SELECT a.user_id,
         'New Content Report',
         'A user reported ' || p_reported_type || ': ' || left(p_reason, 100),
         'content_report',
         v_id::text
  FROM public.admins a;

  RETURN v_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Block a user (also creates a report automatically)
CREATE OR REPLACE FUNCTION public.block_user(
  p_blocked_id uuid,
  p_reason     text DEFAULT 'Blocked by user'
)
RETURNS void AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  IF auth.uid() = p_blocked_id THEN
    RAISE EXCEPTION 'Cannot block yourself';
  END IF;

  -- Insert block
  INSERT INTO public.blocked_users (blocker_id, blocked_id)
  VALUES (auth.uid(), p_blocked_id)
  ON CONFLICT (blocker_id, blocked_id) DO NOTHING;

  -- Auto-report the blocked user to admins
  INSERT INTO public.reports (reporter_id, reported_type, reported_id, reason)
  VALUES (auth.uid(), 'user', p_blocked_id::text, p_reason)
  ON CONFLICT DO NOTHING;

  -- Notify admins
  INSERT INTO public.notifications (user_id, title, body, type, reference_id)
  SELECT a.user_id,
         'User Blocked',
         'A user was blocked. Reason: ' || left(p_reason, 100),
         'content_report',
         p_blocked_id::text
  FROM public.admins a;

  -- Remove any follow relationships
  DELETE FROM public.follows
    WHERE (follower_id = auth.uid() AND following_id = p_blocked_id)
       OR (follower_id = p_blocked_id AND following_id = auth.uid());
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Unblock a user
CREATE OR REPLACE FUNCTION public.unblock_user(p_blocked_id uuid)
RETURNS void AS $$
BEGIN
  DELETE FROM public.blocked_users
    WHERE blocker_id = auth.uid() AND blocked_id = p_blocked_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Update get_feed to exclude blocked users' content
-- (Replaces migration 0065 version)
DROP FUNCTION IF EXISTS public.get_feed(integer, integer);

CREATE OR REPLACE FUNCTION public.get_feed(p_limit integer DEFAULT 20, p_offset integer DEFAULT 0)
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
  reaction_count bigint
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
      COALESCE(rc.cnt, 0)::bigint AS reaction_count
    FROM public.submissions s
    JOIN public.profiles p ON p.id = s.user_id
    JOIN public.user_quests uq ON uq.id = s.user_quest_id
    JOIN public.quests q ON q.id = uq.quest_id
    LEFT JOIN (
      SELECT reactions.submission_id AS sid, count(*) AS cnt
      FROM public.reactions
      GROUP BY reactions.submission_id
    ) rc ON rc.sid = s.id
    WHERE s.status = 'approved'
      AND s.show_in_feed = true
      AND s.visibility = 'visible'
      -- Exclude content from blocked users
      AND NOT EXISTS (
        SELECT 1 FROM public.blocked_users bu
        WHERE bu.blocker_id = auth.uid() AND bu.blocked_id = s.user_id
      )
    ORDER BY s.submitted_at DESC
    LIMIT p_limit
    OFFSET p_offset;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE;

-- Add 'content_report' to notification type allowlist
-- (The notifications table CHECK may not include it yet)
ALTER TABLE public.notifications DROP CONSTRAINT IF EXISTS notifications_type_check;
