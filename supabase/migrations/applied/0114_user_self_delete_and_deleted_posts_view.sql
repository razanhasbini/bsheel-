-- ============================================================
-- MIGRATION 0114: Let owners soft-delete their own posts +
--                 expose a `deleted_posts` audit view.
--
-- Why this exists:
--   The delete UI in feed_post_details_page.dart calls
--     UPDATE submissions SET visibility='deleted', deleted_at=now()
--   But the only UPDATE policy on `submissions` (from 0009) restricts
--   updates to admins, so owner self-delete silently fails in prod.
--
-- This migration:
--   1. Adds an RLS policy `submissions_update_own` so a user can
--      update rows they own.
--   2. Adds a BEFORE UPDATE guard trigger that, for non-admin actors,
--      blocks changes to columns that would let a user fabricate XP
--      (status, xp_awarded), tamper with media (media_url, media_type),
--      or impersonate review state (reviewed_*, submitted_at, user_id).
--      Cascaded updates from inside other triggers (e.g. the 0110 XP
--      revoke trigger) are exempt via pg_trigger_depth() so internal
--      machinery keeps working.
--   3. Creates a read-only view `public.deleted_posts` over the
--      soft-deleted rows, joined with quest + profile context, so the
--      data lives in a clear named place for audit / recovery.
-- ============================================================

-- ── 1) Allow owners to UPDATE their own submissions ─────────────
DROP POLICY IF EXISTS "submissions_update_own" ON public.submissions;
CREATE POLICY "submissions_update_own"
  ON public.submissions
  FOR UPDATE
  USING  (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

-- ── 2) Column-change guard for non-admin owners ─────────────────
-- Owners may freely set visibility / deleted_at / caption / appealed /
-- appeal_note / show_in_feed. Any other column change is rejected.
-- Admins bypass the guard entirely. Cascaded internal updates from
-- inside other triggers (depth >= 2) bypass the guard so the existing
-- handle_submission_approved / 0110 revoke triggers keep working.
CREATE OR REPLACE FUNCTION public.guard_submission_owner_update()
RETURNS trigger AS $$
BEGIN
  -- Trusted contexts: admins, or updates cascaded from another trigger.
  IF public.is_admin() OR pg_trigger_depth() > 1 THEN
    RETURN new;
  END IF;

  -- Reject anything that smells like XP fraud or review tampering.
  IF (new.status        IS DISTINCT FROM old.status)        OR
     (new.user_id       IS DISTINCT FROM old.user_id)       OR
     (new.user_quest_id IS DISTINCT FROM old.user_quest_id) OR
     (new.media_url     IS DISTINCT FROM old.media_url)     OR
     (new.media_type    IS DISTINCT FROM old.media_type)    OR
     (new.reviewed_by   IS DISTINCT FROM old.reviewed_by)   OR
     (new.review_note   IS DISTINCT FROM old.review_note)   OR
     (new.reviewed_at   IS DISTINCT FROM old.reviewed_at)   OR
     (new.submitted_at  IS DISTINCT FROM old.submitted_at)  OR
     (new.xp_awarded    IS DISTINCT FROM old.xp_awarded) THEN
    RAISE EXCEPTION
      'submissions: owners may only modify visibility, deleted_at, caption, appealed, appeal_note, show_in_feed';
  END IF;

  RETURN new;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_guard_submission_owner_update ON public.submissions;
CREATE TRIGGER trg_guard_submission_owner_update
  BEFORE UPDATE ON public.submissions
  FOR EACH ROW
  EXECUTE FUNCTION public.guard_submission_owner_update();

-- ── 3) deleted_posts view ───────────────────────────────────────
-- Convenience window over soft-deleted submissions. Joins in the
-- minimum profile + quest fields needed to identify the post in an
-- admin / restore flow.
DROP VIEW IF EXISTS public.deleted_posts;
CREATE VIEW public.deleted_posts AS
SELECT
  s.id,
  s.user_id,
  s.user_quest_id,
  s.media_url,
  s.media_type,
  s.caption,
  s.status,
  s.visibility,
  s.deleted_at,
  s.submitted_at,
  s.show_in_feed,
  s.appealed,
  uq.quest_id,
  q.title       AS quest_title,
  q.category    AS quest_category,
  q.xp_reward,
  p.username,
  p.display_name,
  p.avatar_url
FROM public.submissions s
JOIN public.user_quests uq ON uq.id = s.user_quest_id
JOIN public.quests q       ON q.id = uq.quest_id
LEFT JOIN public.profiles p ON p.id = s.user_id
WHERE s.visibility = 'deleted';

COMMENT ON VIEW public.deleted_posts IS
  'All soft-deleted submissions (visibility=deleted) with quest + profile context. Read-only audit window.';

GRANT SELECT ON public.deleted_posts TO anon, authenticated, service_role;
