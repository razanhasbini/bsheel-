-- ============================================================
-- MIGRATION 0123: Banned-user write guard (SEC-019).
--
-- Setting profiles.account_status='banned' updates a flag the mobile
-- app voluntarily checks, but a banned user with a still-valid JWT
-- can keep posting/voting/commenting/following until refresh fails
-- (~1 hour later, depending on session config). RLS never gates on
-- account_status, so the row-level checks miss this entirely.
--
-- Fix: a small `is_account_active()` helper plus updated WITH CHECK
-- predicates on every user-writable table the audit flagged. The
-- helper is also useful for SECURITY DEFINER RPCs that want to
-- early-exit on banned callers.
-- ============================================================

-- Cheap helper: is the caller's profile in 'active' status?
-- STABLE so Postgres can cache within a statement.
CREATE OR REPLACE FUNCTION public.is_account_active()
RETURNS boolean AS $$
  SELECT coalesce(
    (SELECT account_status = 'active'
       FROM public.profiles WHERE id = auth.uid()),
    false  -- if there's no profile row, fail closed
  );
$$ LANGUAGE sql STABLE SECURITY DEFINER;

REVOKE EXECUTE ON FUNCTION public.is_account_active() FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.is_account_active() TO authenticated;

-- ── submissions: insert path ────────────────────────────────────
DROP POLICY IF EXISTS submissions_insert_own ON public.submissions;
CREATE POLICY submissions_insert_own ON public.submissions
  FOR INSERT TO authenticated
  WITH CHECK (
    user_id = auth.uid()
    AND public.is_account_active()
  );

-- ── comments: insert path ───────────────────────────────────────
DROP POLICY IF EXISTS comments_insert_own ON public.comments;
CREATE POLICY comments_insert_own ON public.comments
  FOR INSERT TO authenticated
  WITH CHECK (
    user_id = auth.uid()
    AND public.is_account_active()
  );

-- ── reactions: insert path ──────────────────────────────────────
DROP POLICY IF EXISTS reactions_insert_own ON public.reactions;
CREATE POLICY reactions_insert_own ON public.reactions
  FOR INSERT TO authenticated
  WITH CHECK (
    user_id = auth.uid()
    AND public.is_account_active()
  );

-- ── follows: insert path ────────────────────────────────────────
DROP POLICY IF EXISTS follows_insert_own ON public.follows;
CREATE POLICY follows_insert_own ON public.follows
  FOR INSERT TO authenticated
  WITH CHECK (
    follower_id = auth.uid()
    AND public.is_account_active()
  );

-- ── saved_posts / saved_quests: insert path ─────────────────────
DROP POLICY IF EXISTS saved_posts_insert_own ON public.saved_posts;
CREATE POLICY saved_posts_insert_own ON public.saved_posts
  FOR INSERT TO authenticated
  WITH CHECK (
    user_id = auth.uid()
    AND public.is_account_active()
  );

DROP POLICY IF EXISTS saved_quests_insert_own ON public.saved_quests;
CREATE POLICY saved_quests_insert_own ON public.saved_quests
  FOR INSERT TO authenticated
  WITH CHECK (
    user_id = auth.uid()
    AND public.is_account_active()
  );

-- vote_collab is a SECURITY DEFINER RPC — guard there too.
CREATE OR REPLACE FUNCTION public.vote_collab(
  p_group_id      uuid,
  p_submission_id uuid
) RETURNS void AS $$
DECLARE
  v_group_record record;
  v_recent_votes integer;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
  END IF;
  IF NOT public.is_account_active() THEN
    RAISE EXCEPTION 'Account not active' USING ERRCODE = '42501';
  END IF;

  SELECT id, mode, status INTO v_group_record
    FROM public.collab_groups WHERE id = p_group_id;
  IF v_group_record IS NULL THEN
    RAISE EXCEPTION 'Group not found' USING ERRCODE = 'P0002';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.submissions s
    WHERE s.id = p_submission_id
      AND s.user_quest_id IN (
        SELECT m.user_quest_id FROM public.collab_group_members m
        WHERE m.group_id = p_group_id
      )
  ) THEN
    RAISE EXCEPTION 'Submission does not belong to that group'
      USING ERRCODE = 'P0001';
  END IF;

  SELECT count(*) INTO v_recent_votes
    FROM public.collab_votes
    WHERE voter_id = auth.uid()
      AND created_at > now() - interval '1 hour';
  IF v_recent_votes >= 30 THEN
    RAISE EXCEPTION 'Vote rate limit exceeded — try again later'
      USING ERRCODE = 'P0001';
  END IF;

  INSERT INTO public.collab_votes (group_id, voter_id, submission_id)
    VALUES (p_group_id, auth.uid(), p_submission_id)
    ON CONFLICT (group_id, voter_id) DO UPDATE
      SET submission_id = EXCLUDED.submission_id,
          created_at    = now();
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION public.vote_collab(uuid, uuid) TO authenticated;
